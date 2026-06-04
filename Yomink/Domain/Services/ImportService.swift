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

enum ImportBatchProgressPhase: Equatable, Sendable {
    case scanning
    case downloading
    case importing
}

struct ImportBatchProgress: Equatable, Sendable {
    var phase: ImportBatchProgressPhase
    var processedCount: Int
    var totalCount: Int
    var currentFileName: String?
}

struct ImportBatchFailure: Equatable, Sendable {
    var fileName: String
    var errorDescription: String
}

struct ImportBatchSummary: Equatable, Sendable {
    var totalCount: Int
    var importedBooks: [Book]
    var duplicateBooks: [Book]
    var failures: [ImportBatchFailure]

    var importedCount: Int {
        importedBooks.count
    }

    var duplicateCount: Int {
        duplicateBooks.count
    }

    var failedCount: Int {
        failures.count
    }
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
    private static let ubiquitousDownloadTimeout: TimeInterval = 180
    private static let ubiquitousDownloadPollInterval: TimeInterval = 0.25

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
        } catch let error as LibraryRepositoryError {
            if case .duplicateBookContent(let existingBook) = error {
                await cleanUpFailedImport(preparedImport, deletingDatabaseRecord: false)
                return .duplicate(existingBook)
            }
            await cleanUpFailedImport(preparedImport, deletingDatabaseRecord: false)
            throw error
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
            fileName: Self.sourceFileName(from: sourceURL),
            title: Self.title(from: sourceURL),
            author: nil,
            intro: nil
        )
    }

    func importBooks(
        in directoryURL: URL,
        progress: ((ImportBatchProgress) async -> Void)? = nil
    ) async throws -> ImportBatchSummary {
        let accessGranted = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        if let progress = progress {
            await progress(
                ImportBatchProgress(
                    phase: .scanning,
                    processedCount: 0,
                    totalCount: 0,
                    currentFileName: nil
                )
            )
        }

        let sourceURLs = try await supportedTextFiles(in: directoryURL)
        var summary = ImportBatchSummary(
            totalCount: sourceURLs.count,
            importedBooks: [],
            duplicateBooks: [],
            failures: []
        )

        guard !sourceURLs.isEmpty else {
            return summary
        }

        for (index, sourceURL) in sourceURLs.enumerated() {
            try Task.checkCancellation()
            if await needsUbiquitousDownload(sourceURL),
               let progress = progress {
                await progress(
                    ImportBatchProgress(
                        phase: .downloading,
                        processedCount: index,
                        totalCount: sourceURLs.count,
                        currentFileName: Self.sourceFileName(from: sourceURL)
                    )
                )
            }

            if let progress = progress {
                await progress(
                    ImportBatchProgress(
                        phase: .importing,
                        processedCount: index,
                        totalCount: sourceURLs.count,
                        currentFileName: Self.sourceFileName(from: sourceURL)
                    )
                )
            }

            do {
                switch try await importBookCheckingDuplicate(from: sourceURL) {
                case let .imported(book):
                    summary.importedBooks.append(book)
                case let .duplicate(book):
                    summary.duplicateBooks.append(book)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                summary.failures.append(
                    ImportBatchFailure(
                        fileName: Self.sourceFileName(from: sourceURL),
                        errorDescription: error.localizedDescription
                    )
                )
            }

            if let progress = progress {
                await progress(
                    ImportBatchProgress(
                        phase: .importing,
                        processedCount: index + 1,
                        totalCount: sourceURLs.count,
                        currentFileName: nil
                    )
                )
            }
        }

        return summary
    }

    func findExistingBook(for sourceURL: URL) async throws -> Book? {
        let contentHash = try await contentHash(for: sourceURL)
        return try await findExistingBook(contentHash: contentHash)
    }

    private func supportedTextFiles(in directoryURL: URL) async throws -> [URL] {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let directoryValues: URLResourceValues
            do {
                directoryValues = try directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                throw ImportError.cannotReadFile
            }

            guard directoryValues.isDirectory == true else {
                throw ImportError.cannotReadFile
            }

            let resourceKeys: [URLResourceKey] = [
                .isRegularFileKey,
                .isDirectoryKey,
                .isPackageKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: resourceKeys,
                options: [
                    .skipsPackageDescendants
                ],
                errorHandler: { _, _ in true }
            ) else {
                throw ImportError.cannotReadFile
            }

            var sourceURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                try Task.checkCancellation()

                guard Self.isSupportedTextFile(fileURL) else {
                    continue
                }

                let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
                guard values?.isDirectory != true,
                      values?.isPackage != true
                else {
                    continue
                }

                sourceURLs.append(fileURL)
            }

            return sourceURLs.sorted { lhs, rhs in
                lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
        }.value
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
            guard let url = try? fileStore.url(forRelativePath: book.sourcePath) else {
                continue
            }
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
        let sourceFileName = Self.sourceFileName(from: sourceURL)
        let sourceTitle = Self.normalizedTitle(
            metadata?.title,
            fallback: Self.title(from: sourceURL)
        )
        let sourceAuthor = Self.normalizedOptionalText(metadata?.author)
        let sourceIntro = Self.normalizedOptionalText(metadata?.intro)

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

            try Self.downloadUbiquitousItemIfNeeded(sourceURL)

            let bookID = UUID()
            let contentURL = fileStore.contentURL(for: bookID)
            let contentPath = try fileStore.relativePath(for: contentURL)

            let data: Data
            do {
                data = try Self.readDataCoordinated(from: sourceURL)
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

            try Self.downloadUbiquitousItemIfNeeded(sourceURL)

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

            try Self.downloadUbiquitousItemIfNeeded(sourceURL)

            let data: Data
            do {
                data = try Self.readDataCoordinated(from: sourceURL)
            } catch {
                throw ImportError.cannotReadFile
            }
            let decodedText = try decoder.decode(data)
            return Self.sha256Hex(for: Data(decodedText.text.utf8))
        }.value
    }

    private func needsUbiquitousDownload(_ sourceURL: URL) async -> Bool {
        (try? await Task.detached(priority: .utility) {
            let accessGranted = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let values = try sourceURL.resourceValues(
                forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ]
            )
            guard values.isUbiquitousItem == true else {
                return false
            }

            return !Self.isUbiquitousItemAvailable(values.ubiquitousItemDownloadingStatus)
        }.value) ?? false
    }

    private static func downloadUbiquitousItemIfNeeded(_ sourceURL: URL) throws {
        let fileManager = FileManager.default
        let initialValues = try? sourceURL.resourceValues(
            forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
        )
        guard initialValues?.isUbiquitousItem == true else {
            return
        }

        if isUbiquitousItemAvailable(initialValues?.ubiquitousItemDownloadingStatus) {
            return
        }

        do {
            try fileManager.startDownloadingUbiquitousItem(at: sourceURL)
        } catch {
            throw ImportError.cannotReadFile
        }

        let deadline = Date().addingTimeInterval(ubiquitousDownloadTimeout)
        while Date() < deadline {
            try Task.checkCancellation()

            let values = try? sourceURL.resourceValues(
                forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .ubiquitousItemDownloadingErrorKey
                ]
            )
            if values?.ubiquitousItemDownloadingError != nil {
                throw ImportError.cannotReadFile
            }
            if isUbiquitousItemAvailable(values?.ubiquitousItemDownloadingStatus) {
                return
            }

            Thread.sleep(forTimeInterval: ubiquitousDownloadPollInterval)
        }

        throw ImportError.cannotReadFile
    }

    private static func isUbiquitousItemAvailable(
        _ status: URLUbiquitousItemDownloadingStatus?
    ) -> Bool {
        status == .current || status == .downloaded
    }

    private static func readDataCoordinated(from sourceURL: URL) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            do {
                readResult = .success(
                    try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                )
            } catch {
                readResult = .failure(error)
            }
        }

        if coordinatorError != nil {
            throw ImportError.cannotReadFile
        }

        switch readResult {
        case let .success(data):
            return data
        case .failure, .none:
            throw ImportError.cannotReadFile
        }
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
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "txt" {
            return true
        }
        if pathExtension == "icloud" {
            return url.deletingPathExtension().pathExtension.lowercased() == "txt"
        }
        return false
    }

    private static func title(from url: URL) -> String {
        let title = (sourceFileName(from: url) as NSString)
            .deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? NSLocalizedString("book.untitled", comment: "") : title
    }

    private static func sourceFileName(from url: URL) -> String {
        var fileName = url.lastPathComponent
        if url.pathExtension.lowercased() == "icloud" {
            fileName = url.deletingPathExtension().lastPathComponent
            if fileName.hasPrefix(".") {
                fileName.removeFirst()
            }
        }
        return fileName
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
