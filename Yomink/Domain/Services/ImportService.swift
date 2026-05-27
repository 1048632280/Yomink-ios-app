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
    enum ImportError: LocalizedError {
        case unsupportedFileType
        case cannotReadFile
        case cannotWriteUTF8Cache

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return NSLocalizedString("import.error.unsupportedFileType", comment: "")
            case .cannotReadFile:
                return NSLocalizedString("import.error.cannotReadFile", comment: "")
            case .cannotWriteUTF8Cache:
                return NSLocalizedString("import.error.cannotWriteUTF8Cache", comment: "")
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
            let sourceCopyURL = fileStore.sourceURL(for: bookID)
            let normalizedURL = fileStore.normalizedURL(for: bookID)
            let sourcePath = try fileStore.relativePath(for: sourceCopyURL)
            let normalizedPath = try fileStore.relativePath(for: normalizedURL)

            do {
                try fileManager.createDirectory(
                    at: bookDirectoryURL,
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: sourceCopyURL)
            } catch {
                try? AppFileStore.removeBookFiles(at: bookDirectoryURL)
                throw ImportError.cannotReadFile
            }

            do {
                try Task.checkCancellation()
                let data = try Data(contentsOf: sourceCopyURL, options: .mappedIfSafe)
                try Task.checkCancellation()
                let decodedText = try decoder.decode(data)
                let contentHash = Self.sha256Hex(for: decodedText.text)
                do {
                    try decodedText.text.write(
                        to: normalizedURL,
                        atomically: true,
                        encoding: .utf8
                    )
                } catch {
                    throw ImportError.cannotWriteUTF8Cache
                }
                try Task.checkCancellation()

                let importedAt = Date()
                let draft = ImportedBookDraft(
                    id: bookID,
                    title: sourceTitle,
                    author: sourceAuthor,
                    intro: sourceIntro,
                    fileName: sourceFileName,
                    fileSize: Int64(data.count),
                    encoding: decodedText.encodingName,
                    wordCount: Self.visibleCharacterCount(in: decodedText.text),
                    contentHash: contentHash,
                    chapters: chapterIndexer.indexChapters(for: decodedText.text),
                    importedAt: importedAt,
                    importSourceDisplayPath: sourceDisplayPath,
                    sourcePath: sourcePath,
                    normalizedPath: normalizedPath
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

            let data: Data
            do {
                data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            } catch {
                throw ImportError.cannotReadFile
            }
            let decodedText = try decoder.decode(data)
            return Self.sha256Hex(for: decodedText.text)
        }.value
    }

    private func contentHashForReadableFile(at url: URL) async throws -> String {
        let decoder = decoder
        try await Task.detached(priority: .utility) {
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                throw ImportError.cannotReadFile
            }
            let decodedText = try decoder.decode(data)
            return Self.sha256Hex(for: decodedText.text)
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

    private static func sha256Hex(for text: String) -> String {
        sha256Hex(for: Data(text.utf8))
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
