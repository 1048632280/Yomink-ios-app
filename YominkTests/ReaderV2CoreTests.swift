import XCTest
import UIKit
@testable import Yomink

final class ReaderV2CoreTests: XCTestCase {
    func testPageIndexUsesProgressTimesPageCountAndClamps() {
        XCTAssertEqual(
            ReaderPageCalculator.pageIndex(
                pageCount: 10,
                pageIndex: 0,
                progress: 0.5,
                usesPageIndex: false
            ),
            5
        )
        XCTAssertEqual(
            ReaderPageCalculator.pageIndex(
                pageCount: 10,
                pageIndex: 99,
                progress: 0,
                usesPageIndex: true
            ),
            9
        )
        XCTAssertEqual(
            ReaderPageCalculator.pageIndex(
                pageCount: 0,
                pageIndex: 3,
                progress: 0.5,
                usesPageIndex: true
            ),
            0
        )
    }

    func testPageProgressMatchesOriginalReaderFormula() {
        XCTAssertEqual(
            ReaderPageCalculator.pageProgress(
                pageCount: 10,
                pageIndex: 0,
                progress: 0.4,
                usesPageIndex: true
            ),
            0
        )
        XCTAssertEqual(
            ReaderPageCalculator.pageProgress(
                pageCount: 10,
                pageIndex: 9,
                progress: 0.4,
                usesPageIndex: true
            ),
            1
        )
        XCTAssertEqual(
            ReaderPageCalculator.pageProgress(
                pageCount: 10,
                pageIndex: 3,
                progress: 0.4,
                usesPageIndex: true
            ),
            Double(3) / Double(9),
            accuracy: 0.0001
        )
        XCTAssertEqual(
            ReaderPageCalculator.pageProgress(
                pageCount: 10,
                pageIndex: 3,
                progress: 0.4,
                usesPageIndex: false
            ),
            0.4
        )
    }

    func testProgressBridgeMapsStoredProgressToReaderRecord() {
        let fixture = makeBookFixture()
        let bookID = fixture.book.id
        let secondChapterID = fixture.chapters[1].id
        let bridge = ReaderProgressBridge(book: fixture.book, chapters: fixture.chapters)
        let record = bridge.record(
            from: ReadingProgress(
                bookID: bookID,
                chapterID: secondChapterID,
                chapterOffset: 50,
                globalProgress: 0.5
            )
        )

        XCTAssertEqual(record.chapterIndex, 1)
        XCTAssertEqual(record.chapterTitle, "第二章")
        XCTAssertEqual(record.progress, 0.25, accuracy: 0.0001)
    }

    func testProgressBridgeFallsBackToGlobalProgressWhenChapterIDIsMissing() {
        let fixture = makeBookFixture()
        let bridge = ReaderProgressBridge(book: fixture.book, chapters: fixture.chapters)
        let record = bridge.record(
            from: ReadingProgress(
                bookID: fixture.book.id,
                chapterID: nil,
                chapterOffset: 0,
                globalProgress: 0.5
            )
        )

        XCTAssertEqual(record.chapterIndex, 1)
        XCTAssertEqual(record.chapterTitle, "第二章")
        XCTAssertEqual(record.progress, 0.25, accuracy: 0.0001)
    }

    func testProgressBridgeIgnoresProgressFromAnotherBook() {
        let fixture = makeBookFixture()
        let bridge = ReaderProgressBridge(book: fixture.book, chapters: fixture.chapters)
        let record = bridge.record(
            from: ReadingProgress(
                bookID: UUID(),
                chapterID: fixture.chapters[1].id,
                chapterOffset: 50,
                globalProgress: 0.5
            )
        )

        XCTAssertEqual(record.chapterIndex, 0)
        XCTAssertEqual(record.chapterTitle, "第一章")
        XCTAssertEqual(record.progress, 0)
    }

    func testProgressBridgeMapsReaderPageModelBackToStoredProgress() {
        let fixture = makeBookFixture()
        let bridge = ReaderProgressBridge(book: fixture.book, chapters: fixture.chapters)
        let progress = bridge.readingProgress(
            from: ReaderPageModel(
                chapterCount: fixture.chapters.count,
                chapterIndex: 1,
                pageCount: 10,
                pageIndex: 3,
                chapterProgress: 0,
                usesPageIndex: true
            )
        )

        XCTAssertEqual(progress?.bookID, fixture.book.id)
        XCTAssertEqual(progress?.chapterID, fixture.chapters[1].id)
        XCTAssertEqual(progress?.chapterOffset, 66)
        XCTAssertEqual(progress?.globalProgress ?? 0, Double(166) / Double(300), accuracy: 0.0001)
    }

    func testReaderLayoutContentRectUsesFlippedCoreTextMargins() {
        let rect = ReaderLayout.notchedPhone.contentRect(
            in: CGRect(x: 0, y: 0, width: 390, height: 844)
        )

        XCTAssertEqual(rect.origin.x, 20)
        XCTAssertEqual(rect.origin.y, 46)
        XCTAssertEqual(rect.width, 350)
        XCTAssertEqual(rect.height, 726)
    }

    func testReaderThemeParsesGrayscaleAndRGBStrings() {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(ReaderTheme.color(rgbString: "249").getWhite(&white, alpha: &alpha))
        XCTAssertEqual(white, CGFloat(249.0 / 255.0), accuracy: 0.0001)
        XCTAssertEqual(alpha, 1, accuracy: 0.0001)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        XCTAssertTrue(ReaderTheme.color(rgbString: "147,151,158").getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, CGFloat(147.0 / 255.0), accuracy: 0.0001)
        XCTAssertEqual(green, CGFloat(151.0 / 255.0), accuracy: 0.0001)
        XCTAssertEqual(blue, CGFloat(158.0 / 255.0), accuracy: 0.0001)
    }

    func testPaibanManagerReturnsPlaceholderPageForEmptyChapter() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let result = manager.divideText(
            "",
            chapterTitle: "Empty",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360)
        )

        XCTAssertGreaterThan(result.pageCount, 0)
        XCTAssertGreaterThan(result.pages[0].attributedText.length, 0)
        XCTAssertGreaterThan(result.pages[0].displayRange.length, 0)
    }

    func testBookAdapterExposesReaderV2BridgeComponents() throws {
        let fixture = try makeFileBackedBookFixture()
        let adapter = ReaderBookAdapter(
            book: fixture.book,
            chapters: fixture.chapters,
            fileStore: fixture.fileStore
        )

        XCTAssertEqual(adapter.chapterProvider.chapterCount, 2)
        XCTAssertEqual(adapter.progressBridge.record(from: nil).chapterTitle, "Chapter One")
        XCTAssertEqual(adapter.recordBridge.record(chapterIndex: 1)?.chapterTitle, "Chapter Two")
    }

    func testChapterProviderReadsUTF8ChapterText() async throws {
        let fixture = try makeFileBackedBookFixture()
        let provider = ReaderChapterProvider(
            book: fixture.book,
            chapters: fixture.chapters,
            fileStore: fixture.fileStore
        )

        XCTAssertEqual(try provider.text(forChapterAt: 0), fixture.firstText)
        XCTAssertEqual(try await provider.textAsync(forChapterAt: 1), fixture.secondText)
    }

    func testChapterProviderThrowsForMissingChapter() throws {
        let fixture = try makeFileBackedBookFixture()
        let provider = ReaderChapterProvider(
            book: fixture.book,
            chapters: fixture.chapters,
            fileStore: fixture.fileStore
        )

        XCTAssertThrowsError(try provider.text(forChapterAt: 9)) { error in
            XCTAssertEqual(error as? ReaderChapterProviderError, .missingChapter)
        }
    }

    func testRecordBridgeMapsChaptersTargetsAndBookmarksToReaderRecords() {
        let fixture = makeBookFixture()
        let bridge = ReaderRecordBridge(chapters: fixture.chapters)
        let target = ReaderContentTarget(
            chapterID: fixture.chapters[1].id,
            offset: 50
        )
        let bookmark = Bookmark(
            id: UUID(),
            bookID: fixture.book.id,
            chapterID: fixture.chapters[1].id,
            offset: 50,
            preview: "Preview",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let legacyBookmark = Bookmark(
            id: UUID(),
            bookID: fixture.book.id,
            chapterID: nil,
            offset: 50,
            preview: "Legacy",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(bridge.record(chapterIndex: 0)?.chapterTitle, "第一章")
        XCTAssertEqual(bridge.record(from: target)?.chapterIndex, 1)
        XCTAssertEqual(bridge.record(from: target)?.progress ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(bridge.record(from: bookmark)?.chapterTitle, "第二章")
        XCTAssertNil(bridge.record(from: legacyBookmark))
    }

    private func makeBookFixture() -> (book: Book, chapters: [Chapter]) {
        let bookID = UUID()
        let firstChapterID = UUID()
        let secondChapterID = UUID()
        let book = Book(
            id: bookID,
            title: "Book",
            author: nil,
            intro: nil,
            fileName: "book.txt",
            fileSize: 300,
            encoding: "utf-8",
            wordCount: 100,
            importedAt: Date(timeIntervalSince1970: 0),
            lastReadAt: nil,
            groupID: nil,
            progressPercentage: 0,
            contentHash: nil,
            sourcePath: "Books/\(bookID.uuidString.lowercased())/content.txt"
        )
        let chapters = [
            Chapter(
                id: firstChapterID,
                bookID: bookID,
                title: "第一章",
                startOffset: 0,
                endOffset: 100,
                sortOrder: 0,
                source: .regex
            ),
            Chapter(
                id: secondChapterID,
                bookID: bookID,
                title: "第二章",
                startOffset: 100,
                endOffset: 300,
                sortOrder: 1,
                source: .regex
            )
        ]
        return (book, chapters)
    }

    private func makeFileBackedBookFixture() throws -> (
        book: Book,
        chapters: [Chapter],
        fileStore: AppFileStore,
        firstText: String,
        secondText: String
    ) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReaderV2CoreTests-\(UUID().uuidString)", isDirectory: true)
        let fileStore = try AppFileStore.preview(rootURL: rootURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let bookID = UUID()
        let firstChapterID = UUID()
        let secondChapterID = UUID()
        let firstText = "Chapter one line.\n第二行。\n"
        let secondText = "Chapter two line.\n下一页。\n"
        let content = firstText + secondText
        let contentURL = fileStore.contentURL(for: bookID)
        try FileManager.default.createDirectory(
            at: contentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: contentURL, options: .atomic)

        let firstEndOffset = firstText.utf8.count
        let book = Book(
            id: bookID,
            title: "File Backed Book",
            author: nil,
            intro: nil,
            fileName: "content.txt",
            fileSize: Int64(content.utf8.count),
            encoding: "utf-8",
            wordCount: 0,
            importedAt: Date(timeIntervalSince1970: 0),
            lastReadAt: nil,
            groupID: nil,
            progressPercentage: 0,
            contentHash: nil,
            sourcePath: try fileStore.relativePath(for: contentURL)
        )
        let chapters = [
            Chapter(
                id: firstChapterID,
                bookID: bookID,
                title: "Chapter One",
                startOffset: 0,
                endOffset: firstEndOffset,
                sortOrder: 0,
                source: .regex
            ),
            Chapter(
                id: secondChapterID,
                bookID: bookID,
                title: "Chapter Two",
                startOffset: firstEndOffset,
                endOffset: content.utf8.count,
                sortOrder: 1,
                source: .regex
            )
        ]
        return (book, chapters, fileStore, firstText, secondText)
    }
}
