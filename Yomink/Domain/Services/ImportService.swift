import CryptoKit
import Foundation

struct ImportBookMetadata: Equatable, Sendable {
    var title: String
    var author: String?
    var intro: String?
}

struct ImportBookPreview: Equatable, Sendable {
    var sourceURL: URL
    var fileName: String
    var title: String
    var author: String?
    var intro: String?

    var metadata: ImportBookMetadata {
        ImportBookMetadata(
            title: title,
            author: author,
            intro: intro
        )
    }
}

final class ImportService {
    enum ImportResult: Sendable {
        case imported(Book)
        case duplicate(Book)
    }

    enum ImportError: LocalizedError {
        case unsupportedFileType
        case cannotReadFile
        case cannotWriteUTF8Content

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return NSLocalizedString("import.error.unsupportedFileType", comment: "")
            case .cannotReadFile:
                return NSLocalizedString("import.error.cannotReadFile", comment: "")
            case .cannotWriteUTF8Content:
                return NSLocalizedString("import.error.cannotWriteUTF8Content", comment: "")
            }
        }
    }

    private let fileStore: AppFileStore
    private let libraryRepository: any LibraryRepository
    private let decoder: TXTTextDecoder
    private let chapterIndexer: ChapterIndexer

    init(
        fileStore: AppFileStore,
        libraryRepository: any LibraryRepository,
        decoder: TXTTextDecoder = TXTTextDecoder(),
        chapterIndexer: ChapterIndexer = ChapterIndexer()
    ) {
        self.fileStore = fileStore
        self.libraryRepository = libraryRepository
        self.decoder = decoder
        self.chapterIndexer = chapterIndexer
    }

    @discardableResult
    func importBookCheckingDuplicate(
        from sourceURL: URL,
        metadata: ImportBookMetadata? = nil
    ) async throws -> ImportResult {
        let preparedImport = try await prepareImport(
            from: sourceURL,
            metadata: metadata
        )
        do {
            try Task.checkCancellation()
            if let existingBook = try await findExistingBook(
                contentHash: preparedImport.draft.contentHash
            ) {
                cleanUpFailedImport(preparedImport, deletingDatabaseRecord: false)
                return .duplicate(existingBook)
            }

            let book = try await libraryRepository.insertImportedBook(preparedImport.draft)
            try Task.checkCancellation()
            return .imported(book)
        } catch {
            cleanUpFailedImport(preparedImport, deletingDatabaseRecord: error is CancellationError)
            throw error
        }
    }

    @discardableResult
    func importBook(
        from sourceURL: URL,
        metadata: ImportBookMetadata? = nil
    ) async throws -> Book {
        let preparedImport = try await prepareImport(
            from: sourceURL,
            metadata: metadata
        )
        do {
            try Task.checkCancellation()
            let book = try await libraryRepository.insertImportedBook(preparedImport.draft)
            try Task.checkCancellation()
            return book
        } catch {
            cleanUpFailedImport(preparedImport, deletingDatabaseRecord: error is CancellationError)
            throw error
        }
    }

    func previewImport(from sourceURL: URL) async throws -> ImportBookPreview {
        try await validateImportSource(sourceURL)
        return ImportBookPreview(
            sourceURL: sourceURL,
            fileName: sourceURL.lastPathComponent,
            title: Self.title(from: sourceURL),
            author: nil,
            intro: nil
        )
    }

    func findExistingBook(for sourceURL: URL) async throws -> Book? {
        let contentHash = try await contentHash(for: sourceURL)
        return try await findExistingBook(contentHash: contentHash)
    }

    private func findExistingBook(contentHash: String) async throws -> Book? {
        if let existingBook = try await libraryRepository.findBook(contentHash: contentHash) {
            return existingBook
        }

        let books = try await libraryRepository.fetchBooks(
            scope: .all,
            sortOrder: .importedAt
        )
        for book in books where book.contentHash == nil {
            let url = try fileStore.url(forRelativePath: book.sourcePath)
            guard let hash = try? await contentHashForReadableFile(at: url),
                  hash == contentHash else {
                continue
            }
            return book
        }
        return nil
    }

    private func prepareImport(
        from sourceURL: URL,
        metadata: ImportBookMetadata?
    ) async throws -> PreparedImport {
        let fileStore = fileStore
        let decoder = decoder
        let chapterIndexer = chapterIndexer
        let sourceDisplayPath = sourceURL.path
        let sourceFileName = sourceURL.lastPathComponent
        let sourceTitle = Self.normalizedTitle(
            metadata?.title,
            fallback: Self.title(from: sourceURL)
        )
        let sourceAuthor = Self.normalizedOptionalText(metadata?.author)
        let sourceIntro = Self.normalizedOptionalText(metadata?.intro)

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard Self.isSupportedTextFile(sourceURL) else {
                throw ImportError.unsupportedFileType
            }

            let bookID = UUID()
            let bookDirectoryURL = fileStore.bookDirectoryURL(for: bookID)
            let contentURL = fileStore.contentURL(for: bookID)
            let contentPath = try fileStore.relativePath(for: contentURL)

            do {
                try fileManager.createDirectory(
                    at: bookDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                try? AppFileStore.removeBookFiles(at: bookDirectoryURL)
                throw ImportError.cannotReadFile
            }

            do {
                try Task.checkCancellation()
                let data: Data
                do {
                    data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
                } catch {
                    throw ImportError.cannotReadFile
                }
                try Task.checkCancellation()
                let decodedText = try decoder.decode(data)
                let utf8Data = Data(decodedText.text.utf8)
                let contentHash = Self.sha256Hex(for: utf8Data)
                do {
                    try utf8Data.write(to: contentURL, options: .atomic)
                } catch {
                    throw ImportError.cannotWriteUTF8Content
                }
                try Task.checkCancellation()

                let importedAt = Date()
                let draft = ImportedBookDraft(
                    id: bookID,
                    title: sourceTitle,
                    author: sourceAuthor,
                    intro: sourceIntro,
                    fileName: sourceFileName,
                    fileSize: Int64(utf8Data.count),
                    encoding: decodedText.encodingName,
                    wordCount: Self.visibleCharacterCount(in: decodedText.text),
                    contentHash: contentHash,
                    chapters: chapterIndexer.indexChapters(for: decodedText.text),
                    importedAt: importedAt,
                    importSourceDisplayPath: sourceDisplayPath,
                    sourcePath: contentPath
                )
                return PreparedImport(
                    draft: draft,
                    bookDirectoryURL: bookDirectoryURL
                )
            } catch {
                try? AppFileStore.removeBookFiles(at: bookDirectoryURL)
                throw error
            }
        }.value
    }

    private func validateImportSource(_ sourceURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard Self.isSupportedTextFile(sourceURL) else {
                throw ImportError.unsupportedFileType
            }

            guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
                throw ImportError.cannotReadFile
            }
        }.value
    }

    private func contentHash(for sourceURL: URL) async throws -> String {
        let decoder = decoder
        return try await Task.detached(priority: .userInitiated) {
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard Self.isSupportedTextFile(sourceURL) else {
                throw ImportError.unsupportedFileType
            }

            let data: Data
            do {
                data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            } catch {
                throw ImportError.cannotReadFile
            }
            let decodedText = try decoder.decode(data)
            return Self.sha256Hex(for: Data(decodedText.text.utf8))
        }.value
    }

    private func contentHashForReadableFile(at url: URL) async throws -> String {
        return try await Task.detached(priority: .utility) {
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw ImportError.cannotReadFile
            }
            return Self.sha256Hex(for: data)
        }.value
    }

    private static func isSupportedTextFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "txt"
    }

    private static func title(from url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? NSLocalizedString("book.untitled", comment: "") : title
    }

    private static func normalizedTitle(_ title: String?, fallback: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func cleanUpFailedImport(
        _ preparedImport: PreparedImport,
        deletingDatabaseRecord: Bool
    ) {
        let bookID = preparedImport.draft.id
        let bookDirectoryURL = preparedImport.bookDirectoryURL
        try? AppFileStore.removeBookFiles(at: bookDirectoryURL)

        guard deletingDatabaseRecord else {
            return
        }

        let libraryRepository = libraryRepository
        _ = Task.detached {
            // Cancellation can arrive after DB insertion; cleanup must not inherit it.
            try? await libraryRepository.deleteBook(id: bookID)
        }
    }

    private static func visibleCharacterCount(in text: String) -> Int {
        text.unicodeScalars.lazy.filter { !$0.properties.isWhitespace }.count
    }
}

private struct PreparedImport {
    let draft: ImportedBookDraft
    let bookDirectoryURL: URL
}
