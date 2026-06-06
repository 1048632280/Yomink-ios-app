import Foundation

final class AppFileStore: @unchecked Sendable {
    enum StoreError: LocalizedError {
        case missingSystemDirectory(FileManager.SearchPathDirectory)
        case invalidRelativePath(String)

        var errorDescription: String? {
            switch self {
            case let .missingSystemDirectory(directory):
                return "Missing system directory: \(directory)"
            case let .invalidRelativePath(path):
                return "Invalid relative path: \(path)"
            }
        }
    }

    let booksURL: URL
    let applicationSupportURL: URL
    let databaseURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let supportRootURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.missingSystemDirectory(.applicationSupportDirectory)
        }

        let applicationSupportURL = supportRootURL
            .appendingPathComponent("Yomink", isDirectory: true)
        let booksURL = applicationSupportURL.appendingPathComponent("Books", isDirectory: true)
        let databaseURL = applicationSupportURL
            .appendingPathComponent("yomink.sqlite", isDirectory: false)

        try Self.createRequiredDirectories(
            fileManager: fileManager,
            booksURL: booksURL,
            applicationSupportURL: applicationSupportURL
        )

        self.booksURL = booksURL
        self.applicationSupportURL = applicationSupportURL
        self.databaseURL = databaseURL
    }

    private init(
        booksURL: URL,
        applicationSupportURL: URL,
        databaseURL: URL
    ) {
        self.booksURL = booksURL
        self.applicationSupportURL = applicationSupportURL
        self.databaseURL = databaseURL
    }

    static func preview(rootURL: URL? = nil) throws -> AppFileStore {
        let fileManager = FileManager.default
        let rootURL = rootURL ?? fileManager.temporaryDirectory
            .appendingPathComponent("YominkPreview", isDirectory: true)
        let supportURL = rootURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Yomink", isDirectory: true)
        let booksURL = supportURL.appendingPathComponent("Books", isDirectory: true)

        try createRequiredDirectories(
            fileManager: fileManager,
            booksURL: booksURL,
            applicationSupportURL: supportURL
        )

        return AppFileStore(
            booksURL: booksURL,
            applicationSupportURL: supportURL,
            databaseURL: supportURL.appendingPathComponent("preview.sqlite")
        )
    }

    func bookDirectoryURL(for bookID: UUID) -> URL {
        booksURL.appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
    }

    func contentURL(for bookID: UUID) -> URL {
        bookDirectoryURL(for: bookID)
            .appendingPathComponent("content.txt", isDirectory: false)
    }

    func removeBookFiles(id bookID: UUID) throws {
        try Self.removeBookFiles(at: bookDirectoryURL(for: bookID))
    }

    func stageBookFilesForDeletion(id bookID: UUID) throws -> URL? {
        let bookDirectoryURL = bookDirectoryURL(for: bookID)
        guard FileManager.default.fileExists(atPath: bookDirectoryURL.path) else {
            return nil
        }

        let deletionStagingURL = deletionStagingURL()
        try FileManager.default.createDirectory(
            at: deletionStagingURL,
            withIntermediateDirectories: true
        )

        let stagedURL = deletionStagingURL.appendingPathComponent(
            "\(bookID.uuidString.lowercased())-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.moveItem(at: bookDirectoryURL, to: stagedURL)
        return stagedURL
    }

    func restoreStagedBookFiles(_ stagedURL: URL, id bookID: UUID) throws {
        let bookDirectoryURL = bookDirectoryURL(for: bookID)
        if FileManager.default.fileExists(atPath: bookDirectoryURL.path) {
            try FileManager.default.removeItem(at: bookDirectoryURL)
        }
        try FileManager.default.moveItem(at: stagedURL, to: bookDirectoryURL)
        try removeEmptyDeletionStagingDirectoryIfNeeded()
    }

    func removeStagedBookFiles(_ stagedURL: URL) throws {
        guard FileManager.default.fileExists(atPath: stagedURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: stagedURL)
        try removeEmptyDeletionStagingDirectoryIfNeeded()
    }

    func recoverStagedBookDeletions(validBookIDs: Set<UUID>) throws {
        let stagingURL = deletionStagingURL()
        guard FileManager.default.fileExists(atPath: stagingURL.path) else {
            return
        }

        let stagedURLs = try FileManager.default.contentsOfDirectory(
            at: stagingURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for stagedURL in stagedURLs {
            let values = try stagedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                try removeStagedBookFiles(stagedURL)
                continue
            }

            guard let bookID = Self.bookID(fromStagedDeletionURL: stagedURL) else {
                try removeStagedBookFiles(stagedURL)
                continue
            }

            let bookDirectoryURL = bookDirectoryURL(for: bookID)
            if validBookIDs.contains(bookID),
               !FileManager.default.fileExists(atPath: bookDirectoryURL.path) {
                try restoreStagedBookFiles(stagedURL, id: bookID)
            } else {
                try removeStagedBookFiles(stagedURL)
            }
        }

        try removeEmptyDeletionStagingDirectoryIfNeeded()
    }

    static func removeBookFiles(at bookDirectoryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: bookDirectoryURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: bookDirectoryURL)
    }

    /// Returns a database-safe path for files stored below the app's private storage root.
    func relativePath(for url: URL) throws -> String {
        let rootURL = applicationSupportURL.standardizedFileURL
        let targetURL = url.standardizedFileURL
        let rootPath = rootURL.path
        let targetPath = targetURL.path

        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else {
            throw StoreError.invalidRelativePath(targetPath)
        }

        let relativePath = String(targetPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath
    }

    func url(forRelativePath relativePath: String) throws -> URL {
        let pathComponents = relativePath.split(separator: "/")
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !pathComponents.contains("..")
        else {
            throw StoreError.invalidRelativePath(relativePath)
        }

        return applicationSupportURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func createRequiredDirectories(
        fileManager: FileManager,
        booksURL: URL,
        applicationSupportURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: booksURL,
            withIntermediateDirectories: true
        )
    }

    private func deletionStagingURL() -> URL {
        booksURL.appendingPathComponent(".deleting", isDirectory: true)
    }

    private func removeEmptyDeletionStagingDirectoryIfNeeded() throws {
        let stagingURL = deletionStagingURL()
        guard FileManager.default.fileExists(atPath: stagingURL.path) else {
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: stagingURL,
            includingPropertiesForKeys: nil
        )
        if contents.isEmpty {
            try FileManager.default.removeItem(at: stagingURL)
        }
    }

    private static func bookID(fromStagedDeletionURL stagedURL: URL) -> UUID? {
        let name = stagedURL.lastPathComponent
        guard name.count > 36 else {
            return nil
        }
        let idString = String(name.prefix(36))
        return UUID(uuidString: idString)
    }
}
