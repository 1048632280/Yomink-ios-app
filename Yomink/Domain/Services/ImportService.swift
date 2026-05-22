import Foundation

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

    init(
        fileStore: AppFileStore,
        libraryRepository: any LibraryRepository,
        decoder: TXTTextDecoder = TXTTextDecoder()
    ) {
        self.fileStore = fileStore
        self.libraryRepository = libraryRepository
        self.decoder = decoder
    }

    @discardableResult
    func importBook(from sourceURL: URL) async throws -> Book {
        let preparedImport = try await prepareImport(from: sourceURL)
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

    private func prepareImport(from sourceURL: URL) async throws -> PreparedImport {
        let fileStore = fileStore
        let decoder = decoder
        let sourceDisplayPath = sourceURL.path
        let sourceFileName = sourceURL.lastPathComponent
        let sourceTitle = Self.title(from: sourceURL)

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
                    fileName: sourceFileName,
                    fileSize: Int64(data.count),
                    encoding: decodedText.encodingName,
                    wordCount: Self.visibleCharacterCount(in: decodedText.text),
                    chapters: Self.pseudoChapters(
                        for: decodedText.text,
                        title: sourceTitle
                    ),
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

    private static func isSupportedTextFile(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "txt"
    }

    private static func title(from url: URL) -> String {
        let title = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? NSLocalizedString("book.untitled", comment: "") : title
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

    private static func pseudoChapters(
        for text: String,
        title: String
    ) -> [ImportedChapterDraft] {
        let characterCount = text.count
        let chapterCount = max(1, (characterCount + pseudoChapterLength - 1) / pseudoChapterLength)

        return (0..<chapterCount).map { index in
            let startOffset = index * pseudoChapterLength
            let endOffset = min(startOffset + pseudoChapterLength, characterCount)
            return ImportedChapterDraft(
                id: UUID(),
                title: chapterCount == 1 ? title : "\(title) \(index + 1)",
                startOffset: startOffset,
                endOffset: endOffset,
                sortOrder: index
            )
        }
    }

    private static let pseudoChapterLength = 128_000
}

private struct PreparedImport {
    let draft: ImportedBookDraft
    let bookDirectoryURL: URL
}
