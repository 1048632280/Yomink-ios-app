import Foundation

final class AppFileStore {
    enum StoreError: LocalizedError {
        case missingSystemDirectory(FileManager.SearchPathDirectory)

        var errorDescription: String? {
            switch self {
            case let .missingSystemDirectory(directory):
                return "Missing system directory: \(directory)"
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

        try fileManager.createDirectory(
            at: booksURL,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )

        self.documentsURL = documentsURL
        self.booksURL = booksURL
        self.applicationSupportURL = applicationSupportURL
        self.databaseURL = databaseURL
    }

    func bookDirectoryURL(for bookID: UUID) -> URL {
        booksURL.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }
}

