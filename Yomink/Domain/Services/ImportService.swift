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
}

final class ImportService {
    enum ImportResult: Sendable {
        case imported(Book)
        case duplicate(Book)
    }

    enum ImportError: LocalizedError, Equatable {
        case unsupportedFileType
        case cannotReadFile
        case cannotWriteUTF8Content
        case emptyContent

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return NSLocalizedString("import.error.unsupportedFileType", comment: "")
            case .cannotReadFile:
                return NSLocalizedString("import.error.cannotReadFile", comment: "")
            case .cannotWriteUTF8Content:
                return NSLocalizedString("import.error.cannotWriteUTF8Content", comment: "")
            case .emptyContent:
                return NSLocalizedString("import.error.emptyContent", comment: "")
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
        let candidate = try await prepareImportCandidate(
            from: sourceURL,
            metadata: metadata
        )
        try Task.checkCancellation()

        if let existingBook = try await findExistingBook(
            contentHash: candidate.contentHash
        ) {
            return .duplicate(existingBook)
        }

        let preparedImport = try await finalizeImport(from: candidate)
        do {
            try Task.checkCancellation()
            let book = try await libraryRepository.insertImportedBook(preparedImport.draft)
            try Task.checkCancellation()
            return .imported(book)
        } catch {
            await cleanUpFailedImport(preparedImport, deletingDatabaseRecord: error is CancellationError)
            throw error
        }
    }

    @discardableResult
    func importBook(
        from sourceURL: URL,
        metadata: ImportBookMetadata? = nil
    ) async throws -> Book {
        let candidate = try await prepareImportCandidate(
            from: sourceURL,
            metadata: metadata
        )
        try Task.checkCancellation()
        let preparedImport = try await finalizeImport(from: candidate)
        do {
            try Task.checkCancellation()
            let book = try await libraryRepository.insertImportedBook(preparedImport.draft)
            try Task.checkCancellation()
            return book
        } catch {
            await cleanUpFailedImport(preparedImport, deletingDatabaseRecord: error is CancellationError)
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

    private func prepareImportCandidate(
        from sourceURL: URL,
        metadata: ImportBookMetadata?
    ) async throws -> ImportPreparationCandidate {
        let fileStore = fileStore
        let decoder = decoder
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
            let contentURL = fileStore.contentURL(for: bookID)
            let contentPath = try fileStore.relativePath(for: contentURL)

            let data: Data
            do {
                data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
            } catch {
                throw ImportError.cannotReadFile
            }
            try Task.checkCancellation()
            let decodedText = try decoder.decode(data)
            guard Self.containsVisibleContent(decodedText.text) else {
                throw ImportError.emptyContent
            }
            let utf8Data = Data(decodedText.text.utf8)
            let contentHash = Self.sha256Hex(for: utf8Data)

            return ImportPreparationCandidate(
                bookID: bookID,
                bookDirectoryURL: fileStore.bookDirectoryURL(for: bookID),
                contentURL: contentURL,
                contentPath: contentPath,
                sourceDisplayPath: sourceDisplayPath,
                sourceFileName: sourceFileName,
                sourceTitle: sourceTitle,
                sourceAuthor: sourceAuthor,
                sourceIntro: sourceIntro,
                decodedText: decodedText,
                utf8Data: utf8Data,
                contentHash: contentHash
            )
        }.value
    }

    private func finalizeImport(
        from candidate: ImportPreparationCandidate
    ) async throws -> PreparedImport {
        let chapterIndexer = chapterIndexer
        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default

            do {
                try fileManager.createDirectory(
                    at: candidate.bookDirectoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                throw ImportError.cannotReadFile
            }

            do {
                try Task.checkCancellation()
                do {
                    try candidate.utf8Data.write(to: candidate.contentURL, options: .atomic)
                } catch {
                    throw ImportError.cannotWriteUTF8Content
                }
                try Task.checkCancellation()

                let importedAt = Date()
                let draft = ImportedBookDraft(
                    id: candidate.bookID,
                    title: candidate.sourceTitle,
                    author: candidate.sourceAuthor,
                    intro: candidate.sourceIntro,
                    fileName: candidate.sourceFileName,
                    fileSize: Int64(candidate.utf8Data.count),
                    encoding: candidate.decodedText.encodingName,
                    wordCount: Self.visibleCharacterCount(in: candidate.decodedText.text),
                    contentHash: candidate.contentHash,
                    chapters: chapterIndexer.indexChapters(for: candidate.decodedText.text),
                    importedAt: importedAt,
                    importSourceDisplayPath: candidate.sourceDisplayPath,
                    sourcePath: candidate.contentPath
                )
                return PreparedImport(
                    draft: draft,
                    bookDirectoryURL: candidate.bookDirectoryURL
                )
            } catch {
                try? AppFileStore.removeBookFiles(at: candidate.bookDirectoryURL)
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
    ) async {
        let bookID = preparedImport.draft.id
        let bookDirectoryURL = preparedImport.bookDirectoryURL
        try? AppFileStore.removeBookFiles(at: bookDirectoryURL)

        guard deletingDatabaseRecord else {
            return
        }

        let libraryRepository = libraryRepository
        await Task.detached {
            try? await libraryRepository.deleteBook(id: bookID)
        }.value
    }

    private static func visibleCharacterCount(in text: String) -> Int {
        text.unicodeScalars.lazy.filter { !$0.properties.isWhitespace }.count
    }

    private static func containsVisibleContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { !$0.properties.isWhitespace }
    }
}

private struct PreparedImport {
    let draft: ImportedBookDraft
    let bookDirectoryURL: URL
}

private struct ImportPreparationCandidate: Sendable {
    let bookID: UUID
    let bookDirectoryURL: URL
    let contentURL: URL
    let contentPath: String
    let sourceDisplayPath: String
    let sourceFileName: String
    let sourceTitle: String
    let sourceAuthor: String?
    let sourceIntro: String?
    let decodedText: TXTTextDecoder.DecodedText
    let utf8Data: Data
    let contentHash: String
}
