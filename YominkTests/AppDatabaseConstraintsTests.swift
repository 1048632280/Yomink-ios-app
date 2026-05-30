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
}
