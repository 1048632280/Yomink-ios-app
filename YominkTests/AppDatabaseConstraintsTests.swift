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

    func testChapterSourceTriggerRejectsInvalidValuesAfterMigration() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let chapterID = UUID()

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Source",
                author: nil,
                intro: nil,
                fileName: "source.txt",
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

        do {
            try await database.writer.write { db in
                try db.execute(
                    sql: "UPDATE chapters SET source = 'invalid' WHERE id = ?",
                    arguments: [chapterID.uuidString]
                )
            }
            XCTFail("Invalid chapter source should fail")
        } catch {
            let chapters = try await repository.fetchChapters(bookID: bookID)
            XCTAssertEqual(chapters.first?.source, .pseudo)
        }
    }

    func testImportedBookContentHashIsUnique() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let contentHash = "hash-\(UUID().uuidString)"
        let firstID = UUID()
        let secondID = UUID()

        let firstBook = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: firstID,
                title: "First",
                author: nil,
                intro: nil,
                fileName: "first.txt",
                fileSize: 1,
                encoding: "utf-8",
                wordCount: 1,
                contentHash: contentHash,
                chapters: [],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "Books/\(firstID.uuidString.lowercased())/content.txt"
            )
        )

        do {
            _ = try await repository.insertImportedBook(
                ImportedBookDraft(
                    id: secondID,
                    title: "Second",
                    author: nil,
                    intro: nil,
                    fileName: "second.txt",
                    fileSize: 1,
                    encoding: "utf-8",
                    wordCount: 1,
                    contentHash: contentHash,
                    chapters: [],
                    importedAt: Date(timeIntervalSince1970: 1),
                    importSourceDisplayPath: nil,
                    sourcePath: "Books/\(secondID.uuidString.lowercased())/content.txt"
                )
            )
            XCTFail("Duplicate content hash should fail")
        } catch let error as LibraryRepositoryError {
            switch error {
            case .duplicateBookContent(let existingBook):
                XCTAssertEqual(existingBook.id, firstBook.id)
            default:
                XCTFail("Unexpected repository error: \(error)")
            }
        }

        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        XCTAssertEqual(books.count, 1)
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

    func testReadingProgressPageSnapshotIsPersistedAsOffsetSupplement() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let chapterID = UUID()

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Progress Snapshot",
                author: nil,
                intro: nil,
                fileName: "progress-snapshot.txt",
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
                chapterOffset: 6,
                globalProgress: 0.6,
                pageIndex: 3,
                pageCount: 9,
                usesPageIndex: true,
                paginationSignature: "layout-a"
            )
        )

        let progress = try await repository.fetchReadingProgress(bookID: bookID)
        XCTAssertEqual(progress?.chapterOffset, 6)
        XCTAssertEqual(progress?.globalProgress, 0.6)
        XCTAssertEqual(progress?.pageIndex, 3)
        XCTAssertEqual(progress?.pageCount, 9)
        XCTAssertEqual(progress?.usesPageIndex, true)
        XCTAssertEqual(progress?.paginationSignature, "layout-a")
    }

    func testReadingProgressPageSnapshotTriggerRejectsInvalidValuesAfterMigration() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let bookID = UUID()
        let chapterID = UUID()

        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: bookID,
                title: "Progress Snapshot Trigger",
                author: nil,
                intro: nil,
                fileName: "progress-snapshot-trigger.txt",
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
                chapterOffset: 1,
                globalProgress: 0.1,
                pageIndex: 0,
                pageCount: 2,
                usesPageIndex: true
            )
        )

        do {
            try await database.writer.write { db in
                try db.execute(
                    sql: """
                    UPDATE reading_progress
                    SET pageIndex = NULL, usesPageIndex = 1
                    WHERE bookId = ?
                    """,
                    arguments: [bookID.uuidString]
                )
            }
            XCTFail("Invalid reading progress page snapshot should fail")
        } catch {
            let progress = try await repository.fetchReadingProgress(bookID: bookID)
            XCTAssertEqual(progress?.pageIndex, 0)
            XCTAssertEqual(progress?.pageCount, 2)
            XCTAssertEqual(progress?.usesPageIndex, true)
        }
    }
}

final class DomainModelBoundsTests: XCTestCase {
    func testBookProgressAndSizeBoundsAreNormalized() {
        let id = UUID()
        var book = Book(
            id: id,
            title: "Bounds",
            author: nil,
            intro: nil,
            fileName: "bounds.txt",
            fileSize: -10,
            encoding: "utf-8",
            wordCount: -2,
            importedAt: Date(timeIntervalSince1970: 0),
            lastReadAt: nil,
            groupID: nil,
            progressPercentage: 1.5,
            contentHash: nil,
            sourcePath: "Books/\(id.uuidString.lowercased())/content.txt"
        )

        XCTAssertEqual(book.fileSize, 0)
        XCTAssertEqual(book.wordCount, 0)
        XCTAssertEqual(book.progressPercentage, 1)

        book.fileSize = -1
        book.wordCount = -1
        book.progressPercentage = .nan

        XCTAssertEqual(book.fileSize, 0)
        XCTAssertEqual(book.wordCount, 0)
        XCTAssertEqual(book.progressPercentage, 0)
    }

    func testReaderOffsetsAndProgressBoundsAreNormalized() {
        let bookID = UUID()
        var progress = ReadingProgress(
            bookID: bookID,
            chapterID: nil,
            chapterOffset: -1,
            globalProgress: 2
        )
        var chapter = Chapter(
            id: UUID(),
            bookID: bookID,
            title: "Chapter",
            startOffset: -10,
            endOffset: -20,
            sortOrder: -1,
            source: .pseudo
        )
        var bookmark = Bookmark(
            id: UUID(),
            bookID: bookID,
            chapterID: nil,
            offset: -1,
            preview: "",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(progress.chapterOffset, 0)
        XCTAssertEqual(progress.globalProgress, 1)
        XCTAssertEqual(chapter.startOffset, 0)
        XCTAssertEqual(chapter.endOffset, 0)
        XCTAssertEqual(chapter.sortOrder, 0)
        XCTAssertEqual(bookmark.offset, 0)

        progress.chapterOffset = -5
        progress.globalProgress = -Double.infinity
        chapter.startOffset = 50
        chapter.endOffset = 10
        chapter.sortOrder = -3
        bookmark.offset = -7

        XCTAssertEqual(progress.chapterOffset, 0)
        XCTAssertEqual(progress.globalProgress, 0)
        XCTAssertEqual(chapter.startOffset, 50)
        XCTAssertEqual(chapter.endOffset, 50)
        XCTAssertEqual(chapter.sortOrder, 0)
        XCTAssertEqual(bookmark.offset, 0)

        var pageProgress = ReadingProgress(
            bookID: bookID,
            chapterID: nil,
            chapterOffset: 0,
            globalProgress: 0,
            pageIndex: -3,
            pageCount: 0,
            usesPageIndex: true
        )

        XCTAssertEqual(pageProgress.pageIndex, 0)
        XCTAssertNil(pageProgress.pageCount)
        XCTAssertFalse(pageProgress.usesPageIndex)

        pageProgress.pageCount = 4
        pageProgress.usesPageIndex = true
        XCTAssertTrue(pageProgress.usesPageIndex)

        pageProgress.pageIndex = nil
        XCTAssertFalse(pageProgress.usesPageIndex)
    }

    func testImportedDraftBoundsAreNormalized() {
        let bookID = UUID()
        let chapter = ImportedChapterDraft(
            id: UUID(),
            title: "Chapter",
            startOffset: -10,
            endOffset: -20,
            sortOrder: -1,
            source: .regex
        )
        var draft = ImportedBookDraft(
            id: bookID,
            title: "Draft",
            author: nil,
            intro: nil,
            fileName: "draft.txt",
            fileSize: -10,
            encoding: "utf-8",
            wordCount: -2,
            contentHash: "hash",
            chapters: [chapter],
            importedAt: Date(timeIntervalSince1970: 0),
            importSourceDisplayPath: nil,
            sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
        )

        XCTAssertEqual(draft.fileSize, 0)
        XCTAssertEqual(draft.wordCount, 0)
        XCTAssertEqual(draft.chapters[0].startOffset, 0)
        XCTAssertEqual(draft.chapters[0].endOffset, 0)
        XCTAssertEqual(draft.chapters[0].sortOrder, 0)

        draft.fileSize = -1
        draft.wordCount = -1

        XCTAssertEqual(draft.fileSize, 0)
        XCTAssertEqual(draft.wordCount, 0)
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
            try? FileManager.default.removeItem(at: rootURL)
        }

        let firstBook = try makeBook(title: "Same", content: "first", fileStore: fileStore)
        let secondBook = try makeBook(title: "Same", content: "second", fileStore: fileStore)

        let export = try BookExportService.exportURLs(
            for: [firstBook, secondBook],
            fileStore: fileStore
        )
        defer {
            BookExportService.cleanupExportDirectory(export.directoryURL)
        }
        let urls = export.urls

        XCTAssertEqual(urls.map(\.lastPathComponent), ["Same.txt", "Same 2.txt"])
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: urls[1], encoding: .utf8), "second")
    }

    func testSeparateExportsUseIndependentDirectories() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let book = try makeBook(title: "Export", content: "body", fileStore: fileStore)
        let firstExport = try BookExportService.exportURLs(for: [book], fileStore: fileStore)
        let secondExport = try BookExportService.exportURLs(for: [book], fileStore: fileStore)
        defer {
            BookExportService.cleanupExportDirectory(firstExport.directoryURL)
            BookExportService.cleanupExportDirectory(secondExport.directoryURL)
        }

        XCTAssertNotEqual(firstExport.directoryURL, secondExport.directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstExport.urls[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondExport.urls[0].path))

        BookExportService.cleanupExportDirectory(firstExport.directoryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstExport.urls[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondExport.urls[0].path))
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

    func testBookTagsCanBeCreatedAssignedAndQueried() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let firstBook = try await insertBook(
            title: "Tagged",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )
        let secondBook = try await insertBook(
            title: "Untagged",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )

        let tag = try await repository.createTag(name: "仙侠")
        let duplicateTag = try await repository.createTag(name: "  仙侠  ")
        try await repository.setBookTags(bookID: firstBook.id, tagIDs: [tag.id])

        let firstBookTags = try await repository.fetchTags(bookID: firstBook.id)
        let secondBookTags = try await repository.fetchTags(bookID: secondBook.id)
        let usages = try await repository.fetchTagsWithUsage()
        let taggedBooks = try await repository.fetchBooks(
            scope: .tag(tag.id),
            sortOrder: .importedAt
        )

        XCTAssertEqual(duplicateTag.id, tag.id)
        XCTAssertEqual(firstBookTags.map(\.id), [tag.id])
        XCTAssertTrue(secondBookTags.isEmpty)
        XCTAssertEqual(usages.first?.tag.id, tag.id)
        XCTAssertEqual(usages.first?.bookCount, 1)
        XCTAssertEqual(taggedBooks.map(\.id), [firstBook.id])

        try await repository.setBookTags(bookID: firstBook.id, tagIDs: [])
        let clearedTags = try await repository.fetchTags(bookID: firstBook.id)
        let clearedUsages = try await repository.fetchTagsWithUsage()
        let clearedUsage = clearedUsages.first { $0.id == tag.id }

        XCTAssertTrue(clearedTags.isEmpty)
        XCTAssertEqual(clearedUsage?.bookCount, 0)
    }

    func testFavoriteScopeIsVirtualAndUsesFavoriteTimeForAddedSort() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBLibraryRepository(database: database)
        let group = try await repository.createGroup(name: "Group")
        let firstBook = try await insertBook(
            title: "First Favorite",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )
        let secondBook = try await insertBook(
            title: "Second Favorite",
            contentHash: "hash-\(UUID().uuidString)",
            repository: repository
        )

        try await repository.moveBooks(ids: [firstBook.id], to: group.id)
        _ = try await repository.setBookFavorite(id: firstBook.id, isFavorite: true)
        _ = try await repository.setBookFavorite(id: secondBook.id, isFavorite: true)

        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE books SET favoriteAt = ? WHERE id = ?",
                arguments: [
                    DatabaseDateFormatter.string(from: Date(timeIntervalSince1970: 10)),
                    firstBook.id.uuidString
                ]
            )
            try db.execute(
                sql: "UPDATE books SET favoriteAt = ? WHERE id = ?",
                arguments: [
                    DatabaseDateFormatter.string(from: Date(timeIntervalSince1970: 20)),
                    secondBook.id.uuidString
                ]
            )
        }

        let favoriteBooks = try await repository.fetchBooks(
            scope: .favorites,
            sortOrder: .importedAt
        )
        let groupedBooks = try await repository.fetchBooks(
            scope: .group(group.id),
            sortOrder: .importedAt
        )

        XCTAssertEqual(favoriteBooks.map(\.id), [secondBook.id, firstBook.id])
        XCTAssertEqual(groupedBooks.map(\.id), [firstBook.id])
        XCTAssertEqual(favoriteBooks.first { $0.id == firstBook.id }?.groupID, group.id)

        let updatedSecondBook = try await repository.setBookFavorite(id: secondBook.id, isFavorite: false)
        let favoriteBooksAfterCancel = try await repository.fetchBooks(
            scope: .favorites,
            sortOrder: .importedAt
        )

        XCTAssertNil(updatedSecondBook.favoriteAt)
        XCTAssertEqual(favoriteBooksAfterCancel.map(\.id), [firstBook.id])
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

    func testImportCanTargetGroup() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let database = try AppDatabase(fileStore: fileStore)
        let repository = GRDBLibraryRepository(database: database)
        let group = try await repository.createGroup(name: "Target")
        let importService = ImportService(
            fileStore: fileStore,
            libraryRepository: repository
        )
        let sourceURL = rootURL.appendingPathComponent("grouped.txt", isDirectory: false)
        try Data("Chapter 1\nGrouped".utf8).write(to: sourceURL, options: .atomic)

        let result = try await importService.importBookCheckingDuplicate(
            from: sourceURL,
            targetGroupID: group.id
        )
        let importedBook: Book
        switch result {
        case let .imported(book):
            importedBook = book
        case .duplicate:
            XCTFail("First import should create a book")
            return
        }

        let groupedBooks = try await repository.fetchBooks(
            scope: .group(group.id),
            sortOrder: .importedAt
        )
        let ungroupedBooks = try await repository.fetchBooks(
            scope: .ungrouped,
            sortOrder: .importedAt
        )

        XCTAssertEqual(importedBook.groupID, group.id)
        XCTAssertEqual(groupedBooks.map(\.id), [importedBook.id])
        XCTAssertTrue(ungroupedBooks.isEmpty)
    }

    func testConcurrentDuplicateImportKeepsSingleBook() async throws {
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
        let sourceURL = rootURL.appendingPathComponent("concurrent.txt", isDirectory: false)
        try Data("Chapter 1\nBody".utf8).write(to: sourceURL, options: .atomic)

        async let firstResult = importService.importBookCheckingDuplicate(from: sourceURL)
        async let secondResult = importService.importBookCheckingDuplicate(from: sourceURL)
        let first = try await firstResult
        let second = try await secondResult
        let results = [first, second]
        let importedCount = results.filter { result in
            if case .imported = result {
                return true
            }
            return false
        }.count

        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        let bookDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStore.booksURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && url.lastPathComponent != ".deleting"
        }

        XCTAssertGreaterThanOrEqual(importedCount, 1)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(bookDirectories.count, 1)
    }

    func testEmptyTextImportIsRejectedWithoutCreatingBookDirectory() async throws {
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
        let sourceURL = rootURL.appendingPathComponent("empty.txt", isDirectory: false)
        try Data(" \n\t ".utf8).write(to: sourceURL, options: .atomic)

        do {
            _ = try await importService.importBookCheckingDuplicate(from: sourceURL)
            XCTFail("Empty text import should fail")
        } catch let error as ImportService.ImportError {
            XCTAssertEqual(error, .emptyContent)
        }

        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        let bookDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStore.booksURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && url.lastPathComponent != ".deleting"
        }

        XCTAssertTrue(books.isEmpty)
        XCTAssertTrue(bookDirectories.isEmpty)
    }

    func testLegacyUnreadableDuplicateCandidateIsSkipped() async throws {
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
        let legacyBookID = UUID()
        _ = try await repository.insertImportedBook(
            ImportedBookDraft(
                id: legacyBookID,
                title: "Legacy",
                author: nil,
                intro: nil,
                fileName: "legacy.txt",
                fileSize: 1,
                encoding: "utf-8",
                wordCount: 1,
                contentHash: "legacy-\(UUID().uuidString)",
                chapters: [],
                importedAt: Date(timeIntervalSince1970: 0),
                importSourceDisplayPath: nil,
                sourcePath: "../bad.txt"
            )
        )
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE books SET contentHash = NULL WHERE id = ?",
                arguments: [legacyBookID.uuidString]
            )
        }
        let sourceURL = rootURL.appendingPathComponent("new.txt", isDirectory: false)
        try Data("Chapter 1\nNew".utf8).write(to: sourceURL, options: .atomic)

        let result = try await importService.importBookCheckingDuplicate(from: sourceURL)
        guard case .imported = result else {
            XCTFail("Unreadable legacy sourcePath should not block import")
            return
        }

        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        XCTAssertEqual(books.count, 2)
    }

    func testBatchImportImportsTextFilesAndReportsFailures() async throws {
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
        let importDirectoryURL = rootURL.appendingPathComponent("Batch", isDirectory: true)
        let nestedDirectoryURL = importDirectoryURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(
            at: nestedDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("Chapter 1\nFirst".utf8).write(
            to: importDirectoryURL.appendingPathComponent("First.txt"),
            options: .atomic
        )
        try Data("Chapter 1\nSecond".utf8).write(
            to: nestedDirectoryURL.appendingPathComponent("Second.txt"),
            options: .atomic
        )
        try Data("Chapter 1\nCloud".utf8).write(
            to: importDirectoryURL.appendingPathComponent(".Cloud.txt.icloud"),
            options: .atomic
        )
        try Data(" \n\t ".utf8).write(
            to: importDirectoryURL.appendingPathComponent("Empty.txt"),
            options: .atomic
        )
        try Data("Ignored".utf8).write(
            to: importDirectoryURL.appendingPathComponent("Ignored.md"),
            options: .atomic
        )

        let progressRecorder = ImportBatchProgressRecorder()
        let summary = try await importService.importBooks(in: importDirectoryURL) { progress in
            await progressRecorder.append(progress)
        }
        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        let progressEvents = await progressRecorder.events

        XCTAssertEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.importedCount, 3)
        XCTAssertEqual(summary.duplicateCount, 0)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.failures.first?.fileName, "Empty.txt")
        XCTAssertEqual(Set(summary.importedBooks.map(\.fileName)), Set(["Cloud.txt", "First.txt", "Second.txt"]))
        XCTAssertEqual(Set(summary.importedBooks.map(\.title)), Set(["Cloud", "First", "Second"]))
        XCTAssertEqual(books.count, 3)
        XCTAssertEqual(progressEvents.first?.phase, .scanning)
        XCTAssertEqual(progressEvents.last?.processedCount, 4)
        XCTAssertEqual(progressEvents.last?.totalCount, 4)
    }

    func testBatchImportReportsDuplicatesWithoutCreatingExtraBooks() async throws {
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
        let importDirectoryURL = rootURL.appendingPathComponent("Batch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: importDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("Chapter 1\nSame".utf8).write(
            to: importDirectoryURL.appendingPathComponent("A.txt"),
            options: .atomic
        )
        try Data("Chapter 1\nSame".utf8).write(
            to: importDirectoryURL.appendingPathComponent("B.txt"),
            options: .atomic
        )

        let summary = try await importService.importBooks(in: importDirectoryURL)
        let books = try await repository.fetchBooks(scope: .all, sortOrder: .importedAt)
        let bookDirectories = try FileManager.default.contentsOfDirectory(
            at: fileStore.booksURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true && url.lastPathComponent != ".deleting"
        }

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(bookDirectories.count, 1)
    }
}

private actor ImportBatchProgressRecorder {
    private var storedEvents: [ImportBatchProgress] = []

    var events: [ImportBatchProgress] {
        storedEvents
    }

    func append(_ progress: ImportBatchProgress) {
        storedEvents.append(progress)
    }
}
