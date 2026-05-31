import Foundation
import XCTest
@testable import Yomink

final class AppDatabaseConstraintsTests: XCTestCase {
    func testImportedBookDraftBoundsAreNormalizedBeforePersisting() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let chapterID = UUID()

        let book = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Bounds",
                author: nil,
                intro: nil,
                fileName: "bounds.txt",
                fileSize: -1,
                encoding: "utf-8",
                wordCount: -10,
                contentHash: "hash-\(UUID().uuidString)",
                chapters: [
                    ImportedChapterDraft(
                        id: chapterID,
                        title: "Chapter",
                        startOffset: -20,
                        endOffset: -30,
                        sortOrder: -1,
                        source: .regex
                    )
                ],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
            )
        )
        let chapters = try await repository.fetchChapters(bookID: bookID)

        XCTAssertEqual(book.fileSize, 0)
        XCTAssertEqual(book.wordCount, 0)
        XCTAssertEqual(chapters.first?.startOffset, 0)
        XCTAssertEqual(chapters.first?.endOffset, 0)
        XCTAssertEqual(chapters.first?.sortOrder, 0)
    }

    func testReadingProgressBoundsAreNormalizedBeforePersisting() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let chapterID = UUID()

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Progress",
                author: nil,
                intro: nil,
                fileName: "progress.txt",
                fileSize: 10,
                encoding: "utf-8",
                wordCount: 2,
                contentHash: "hash-\(UUID().uuidString)",
                chapters: [
                    ImportedChapterDraft(
                        id: chapterID,
                        title: "Chapter",
                        startOffset: 0,
                        endOffset: 10,
                        sortOrder: 0,
                        source: .pseudo
                    )
                ],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
            )
        )

        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: bookID,
                chapterID: chapterID,
                chapterOffset: -5,
                globalProgress: 1.5
            )
        )

        let progress = try await repository.fetchReadingProgress(bookID: bookID)
        XCTAssertEqual(progress?.chapterOffset, 0)
        XCTAssertEqual(progress?.globalProgress, 1)
    }

    func testLegacyOversizedChapterRepairSplitsAndRemapsReaderState() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let database = try AppDatabase(fileStore: fileStore)
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let prefaceChapterID = UUID()
        let legacyChapterID = UUID()
        let tailChapterID = UUID()
        let prefix = "Preface\n"
        let body = String(repeating: "a", count: ChapterIndexer.oversizedChapterByteLength + 10)
        let tail = "\nTail"
        let content = prefix + body + tail
        let prefixByteLength = prefix.utf8.count
        let bodyByteLength = body.utf8.count
        let tailStartOffset = prefixByteLength + bodyByteLength
        let targetChapterOffset = ChapterIndexer.oversizedChapterByteLength + 5
        let targetAbsoluteOffset = prefixByteLength + targetChapterOffset

        try FileManager.default.createDirectory(
            at: fileStore.bookDirectoryURL(for: bookID),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: fileStore.contentURL(for: bookID), options: .atomic)

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Legacy",
                author: nil,
                intro: nil,
                fileName: "legacy.txt",
                fileSize: Int64(content.utf8.count),
                encoding: "utf-8",
                wordCount: content.count,
                contentHash: "hash-\(UUID().uuidString)",
                chapters: [
                    ImportedChapterDraft(
                        id: prefaceChapterID,
                        title: "Preface",
                        startOffset: 0,
                        endOffset: prefixByteLength,
                        sortOrder: 0,
                        source: .pseudo
                    ),
                    ImportedChapterDraft(
                        id: legacyChapterID,
                        title: "Big",
                        startOffset: prefixByteLength,
                        endOffset: tailStartOffset,
                        sortOrder: 1,
                        source: .regex
                    ),
                    ImportedChapterDraft(
                        id: tailChapterID,
                        title: "Tail",
                        startOffset: tailStartOffset,
                        endOffset: content.utf8.count,
                        sortOrder: 2,
                        source: .pseudo
                    )
                ],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: try fileStore.relativePath(for: fileStore.contentURL(for: bookID))
            )
        )

        try await repository.saveReadingProgress(
            ReadingProgress(
                bookID: bookID,
                chapterID: legacyChapterID,
                chapterOffset: Int64(targetChapterOffset),
                globalProgress: 0.5
            )
        )
        _ = try await repository.createBookmark(
            bookID: bookID,
            chapterID: legacyChapterID,
            offset: targetChapterOffset,
            preview: "target"
        )
        try await repository.markBookOpened(id: bookID, at: Date(timeIntervalSince1970: 1))

        try database.repairLegacyOversizedChaptersIfNeeded()

        let chapters = try await repository.fetchChapters(bookID: bookID)
        let expectedSegment = try XCTUnwrap(
            chapters.first {
                targetAbsoluteOffset >= $0.startOffset && targetAbsoluteOffset < $0.endOffset
            }
        )
        let expectedSegmentOffset = targetAbsoluteOffset - expectedSegment.startOffset
        let progress = try await repository.fetchReadingProgress(bookID: bookID)
        let bookmarks = try await repository.fetchBookmarks(bookID: bookID)
        let history = try await repository.fetchReadingHistory(limit: 1)

        XCTAssertGreaterThan(chapters.count, 3)
        XCTAssertEqual(chapters.map(\.sortOrder), Array(chapters.indices))
        XCTAssertLessThanOrEqual(
            chapters.map { $0.endOffset - $0.startOffset }.max() ?? 0,
            ChapterIndexer.oversizedChapterByteLength
        )
        XCTAssertNotEqual(expectedSegment.id, legacyChapterID)
        XCTAssertEqual(progress?.chapterID, expectedSegment.id)
        XCTAssertEqual(progress?.chapterOffset, Int64(expectedSegmentOffset))
        XCTAssertEqual(bookmarks.first?.chapterID, expectedSegment.id)
        XCTAssertEqual(bookmarks.first?.offset, expectedSegmentOffset)
        XCTAssertEqual(history.first?.chapterTitle, "Big (2)")
        XCTAssertEqual(history.first?.offset, expectedSegmentOffset)
    }
}

final class AppFileStoreDeletionStagingTests: XCTestCase {
    func testStagedDeletionRecoveryRestoresFilesForExistingBook() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let bookID = UUID()
        let contentURL = fileStore.contentURL(for: bookID)
        try FileManager.default.createDirectory(
            at: fileStore.bookDirectoryURL(for: bookID),
            withIntermediateDirectories: true
        )
        try Data("body".utf8).write(to: contentURL)

        let stagedURL = try XCTUnwrap(fileStore.stageBookFilesForDeletion(id: bookID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: contentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))

        try fileStore.recoverStagedBookDeletions(validBookIDs: [bookID])

        XCTAssertTrue(FileManager.default.fileExists(atPath: contentURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testStagedDeletionRecoveryRemovesFilesForDeletedBook() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let bookID = UUID()
        try FileManager.default.createDirectory(
            at: fileStore.bookDirectoryURL(for: bookID),
            withIntermediateDirectories: true
        )
        try Data("body".utf8).write(to: fileStore.contentURL(for: bookID))

        let stagedURL = try XCTUnwrap(fileStore.stageBookFilesForDeletion(id: bookID))
        try fileStore.recoverStagedBookDeletions(validBookIDs: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileStore.bookDirectoryURL(for: bookID).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }
}

final class BookExportServiceTests: XCTestCase {
    func testExportURLsDeduplicatesFileNamesForSameTitle() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            BookExportService.cleanupExportDirectory()
            try? FileManager.default.removeItem(at: rootURL)
        }

        let firstBook = try makeBook(title: "Same", content: "first", fileStore: fileStore)
        let secondBook = try makeBook(title: "Same", content: "second", fileStore: fileStore)

        let urls = try BookExportService.exportURLs(
            for: [firstBook, secondBook],
            fileStore: fileStore
        )

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Same.txt", "Same 2.txt"])
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: urls[1], encoding: .utf8), "second")
    }

    private func makeBook(
        title: String,
        content: String,
        fileStore: AppFileStore
    ) throws -> Book {
        let bookID = UUID()
        let contentURL = fileStore.contentURL(for: bookID)
        try FileManager.default.createDirectory(
            at: fileStore.bookDirectoryURL(for: bookID),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: contentURL, options: .atomic)

        return Book(
            id: bookID,
            title: title,
            author: nil,
            intro: nil,
            fileName: contentURL.lastPathComponent,
            fileSize: Int64(content.utf8.count),
            encoding: "utf-8",
            wordCount: content.count,
            importedAt: Date(timeIntervalSince1970: 0),
            lastReadAt: nil,
            groupID: nil,
            progressPercentage: 0,
            contentHash: nil,
            sourcePath: try fileStore.relativePath(for: contentURL)
        )
    }
}

final class ReadingHistoryLimitTests: XCTestCase {
    func testFetchReadingHistoryReturnsEmptyWhenLimitIsNotPositive() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "History",
                author: nil,
                intro: nil,
                fileName: "history.txt",
                fileSize: 10,
                encoding: "utf-8",
                wordCount: 2,
                contentHash: "hash-\(UUID().uuidString)",
                chapters: [],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
            )
        )
        try await repository.markBookOpened(id: bookID, at: Date(timeIntervalSince1970: 1))

        let positiveHistory = try await repository.fetchReadingHistory(limit: 1)
        let zeroLimitHistory = try await repository.fetchReadingHistory(limit: 0)
        let negativeLimitHistory = try await repository.fetchReadingHistory(limit: -1)

        XCTAssertEqual(positiveHistory.count, 1)
        XCTAssertTrue(zeroLimitHistory.isEmpty)
        XCTAssertTrue(negativeLimitHistory.isEmpty)
    }

    func testPreviewReadingHistoryReturnsEmptyWhenLimitIsNotPositive() async throws {
        let repository = PreviewLibraryRepository()

        let positiveHistory = try await repository.fetchReadingHistory(limit: 1)
        let zeroLimitHistory = try await repository.fetchReadingHistory(limit: 0)
        let negativeLimitHistory = try await repository.fetchReadingHistory(limit: -1)

        XCTAssertEqual(positiveHistory.count, 1)
        XCTAssertTrue(zeroLimitHistory.isEmpty)
        XCTAssertTrue(negativeLimitHistory.isEmpty)
    }
}

final class BookSearchEscapingTests: XCTestCase {
    func testSearchBooksTreatsPercentAndUnderscoreAsLiteralCharacters() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)

        _ = try await insertBook(
            title: "100% Real",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )
        _ = try await insertBook(
            title: "100x Real",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )
        _ = try await insertBook(
            title: "Under_score",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )
        _ = try await insertBook(
            title: "UnderXscore",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )

        let percentResults = try await repository.searchBooks(
            keyword: "100%",
            sortOrder: .importedAt
        )
        let underscoreResults = try await repository.searchBooks(
            keyword: "Under_",
            sortOrder: .importedAt
        )

        XCTAssertEqual(percentResults.map(\.title), ["100% Real"])
        XCTAssertEqual(underscoreResults.map(\.title), ["Under_score"])
    }

    private func insertBook(
        title: String,
        contentHash: String,
        repository: GRDBLibraryRepository
    ) async throws -> Book {
        let bookID = UUID()
        return try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: title,
                author: nil,
                intro: nil,
                fileName: "\(bookID.uuidString).txt",
                fileSize: 10,
                encoding: "utf-8",
                wordCount: 2,
                contentHash: contentHash,
                chapters: [],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
            )
        )
    }
}

final class ImportServiceDuplicateTests: XCTestCase {
    func testDuplicateImportDoesNotCreateSecondBookDirectory() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let database = try AppDatabase(fileStore: fileStore)
        let repository = GRDBLibraryRepository(database: database)
        let importService = ImportService(
            fileStore: fileStore,
            libraryRepository: repository
        )
        let sourceURL = rootURL.appendingPathComponent("source.txt", isDirectory: false)
        try Data("Chapter 1\nBody".utf8).write(to: sourceURL, options: .atomic)

        let firstResult = try await importService.importBookCheckingDuplicate(from: sourceURL)
        let importedBook: Book
        switch firstResult {
        case let .imported(book):
            importedBook = book
        case .duplicate:
            XCTFail("First import should create a book")
            return
        }

        let secondResult = try await importService.importBookCheckingDuplicate(from: sourceURL)
        switch secondResult {
        case .imported:
            XCTFail("Second import should be detected as duplicate")
        case let .duplicate(book):
            XCTAssertEqual(book.id, importedBook.id)
        }

        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        let bookDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStore.booksURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && url.lastPathComponent != ".deleting"
        }

        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(bookDirectories.count, 1)
    }
}
