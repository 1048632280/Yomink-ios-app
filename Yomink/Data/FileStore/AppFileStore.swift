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

    let documentsURL: URL
    let booksURL: URL
    let applicationSupportURL: URL
    let databaseURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.missingSystemDirectory(.documentDirectory)
        }

        guard let supportRootURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.missingSystemDirectory(.applicationSupportDirectory)
        }

        let booksURL = documentsURL.appendingPathComponent("Books", isDirectory: true)
        let applicationSupportURL = supportRootURL
            .appendingPathComponent("Yomink", isDirectory: true)
        let databaseURL = applicationSupportURL
            .appendingPathComponent("yomink.sqlite", isDirectory: false)

        try Self.createRequiredDirectories(
            fileManager: fileManager,
            documentsURL: documentsURL,
            booksURL: booksURL,
            applicationSupportURL: applicationSupportURL
        )

        self.documentsURL = documentsURL
        self.booksURL = booksURL
        self.applicationSupportURL = applicationSupportURL
        self.databaseURL = databaseURL
    }

    private init(
        documentsURL: URL,
        booksURL: URL,
        applicationSupportURL: URL,
        databaseURL: URL
    ) {
        self.documentsURL = documentsURL
        self.booksURL = booksURL
        self.applicationSupportURL = applicationSupportURL
        self.databaseURL = databaseURL
    }

    static func preview() throws -> AppFileStore {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("YominkPreview", isDirectory: true)
        let booksURL = rootURL.appendingPathComponent("Books", isDirectory: true)
        let supportURL = rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true)

        try createRequiredDirectories(
            fileManager: fileManager,
            documentsURL: rootURL,
            booksURL: booksURL,
            applicationSupportURL: supportURL
        )

        return AppFileStore(
            documentsURL: rootURL,
            booksURL: booksURL,
            applicationSupportURL: supportURL,
            databaseURL: supportURL.appendingPathComponent("preview.sqlite")
        )
    }

    func bookDirectoryURL(for bookID: UUID) -> URL {
        booksURL.appendingPathComponent(bookID.uuidString.lowercased(), isDirectory: true)
    }

    func sourceURL(for bookID: UUID) -> URL {
        bookDirectoryURL(for: bookID)
            .appendingPathComponent("source.txt", isDirectory: false)
    }

    func normalizedURL(for bookID: UUID) -> URL {
        bookDirectoryURL(for: bookID)
            .appendingPathComponent("normalized.txt", isDirectory: false)
    }

    func removeBookFiles(id bookID: UUID) throws {
        try Self.removeBookFiles(at: bookDirectoryURL(for: bookID))
    }

    static func removeBookFiles(at bookDirectoryURL: URL) throws {
        guard FileManager.default.fileExists(atPath: bookDirectoryURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: bookDirectoryURL)
    }

    /// Returns a database-safe path for files stored below the app Documents directory.
    func relativePath(for url: URL) throws -> String {
        let rootURL = documentsURL.standardizedFileURL
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

        return documentsURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func createRequiredDirectories(
        fileManager: FileManager,
        documentsURL: URL,
        booksURL: URL,
        applicationSupportURL: URL
    ) throws {
        try fileManager.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: booksURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )
    }
}
