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

    func testReaderFontManagerNormalizesFontAndStrokeValues() {
        let manager = ReaderFontManager(fontName: "Missing Reader Font")

        XCTAssertEqual(manager.bodyFont(size: .nan).pointSize, 20, accuracy: 0.0001)
        XCTAssertEqual(manager.titleFont(size: 2).pointSize, 8, accuracy: 0.0001)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(-12), -10)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(12), 10)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(.infinity), 0)
    }

    func testPaibanManagerBuildsTitleAndBodyAttributes() {
        var layout = ReaderLayout.phone
        layout.fontSize = 22
        layout.fontWeight = -12
        layout.titleFontWeight = 12
        layout.wordSpacing = 1.5
        layout.titleWordSpacing = 2.5
        let manager = PaibanManager(layout: layout, theme: .standard)
        let attributed = manager.attributedText(
            text: "正文第一行\n正文第二行",
            chapterTitle: "标题"
        )
        let titleAttributes = attributed.attributes(at: 0, effectiveRange: nil)
        let bodyIndex = ("标题\n" as NSString).length
        let bodyAttributes = attributed.attributes(at: bodyIndex, effectiveRange: nil)

        XCTAssertEqual((titleAttributes[.font] as? UIFont)?.pointSize ?? 0, 23, accuracy: 0.0001)
        XCTAssertEqual((bodyAttributes[.font] as? UIFont)?.pointSize ?? 0, 22, accuracy: 0.0001)
        XCTAssertEqual((titleAttributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual((bodyAttributes[.strokeWidth] as? NSNumber)?.doubleValue ?? 0, -10, accuracy: 0.0001)
        XCTAssertEqual((titleAttributes[.kern] as? NSNumber)?.doubleValue ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual((bodyAttributes[.kern] as? NSNumber)?.doubleValue ?? 0, 1.5, accuracy: 0.0001)

        let bodyParagraph = bodyAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(bodyParagraph?.firstLineHeadIndent ?? 0, 44, accuracy: 0.0001)
    }

    func testPaibanManagerPaginatesSingleChapterIntoContinuousRanges() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let text = readerV2LongText(repeating: 90)
        let result = manager.divideText(
            text,
            chapterTitle: "第一章",
            chapterIndex: 0,
            pageSize: CGSize(width: 240, height: 320)
        )

        XCTAssertGreaterThan(result.pageCount, 1)
        XCTAssertEqual(result.pages.first?.displayRange.location, 0)
        for index in 1..<result.pages.count {
            let previous = result.pages[index - 1].displayRange
            let current = result.pages[index].displayRange
            XCTAssertEqual(current.location, previous.location + previous.length)
        }
        XCTAssertEqual(
            result.pages.map(\.attributedText.string).joined(),
            manager.attributedText(text: text, chapterTitle: "第一章").string
        )
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

    func testPaibanManagerReflowsWhenFontMarginsOrLineSpacingChange() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let text = readerV2LongText(repeating: 160)
        let baseLayout = ReaderLayout.phone
        let baseResult = PaibanManager(layout: baseLayout, theme: .standard).divideText(
            text,
            chapterTitle: "重排测试",
            chapterIndex: 0,
            pageSize: baseLayout.contentRect(in: bounds).size
        )

        var largeLayout = baseLayout
        largeLayout.fontSize = 28
        largeLayout.lineSpacing = 18
        let largeResult = PaibanManager(layout: largeLayout, theme: .standard).divideText(
            text,
            chapterTitle: "重排测试",
            chapterIndex: 0,
            pageSize: largeLayout.contentRect(in: bounds).size
        )

        var narrowLayout = baseLayout
        narrowLayout.leftMargin = 64
        narrowLayout.rightMargin = 64
        let narrowSize = narrowLayout.contentRect(in: bounds).size
        let narrowResult = PaibanManager(layout: narrowLayout, theme: .standard).divideText(
            text,
            chapterTitle: "重排测试",
            chapterIndex: 0,
            pageSize: narrowSize
        )

        XCTAssertGreaterThan(largeResult.pageCount, baseResult.pageCount)
        XCTAssertLessThan(narrowSize.width, baseLayout.contentRect(in: bounds).width)
        XCTAssertGreaterThanOrEqual(narrowResult.pageCount, baseResult.pageCount)
    }

    func testPaibanManagerReturnsMeasuredHeightsForVerticalMode() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let fixed = manager.divideText(
            "短正文。",
            chapterTitle: "高度",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360),
            returnsHeights: false
        )
        let measured = manager.divideText(
            "短正文。",
            chapterTitle: "高度",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360),
            returnsHeights: true
        )

        XCTAssertEqual(fixed.pageHeights.first ?? 0, 360, accuracy: 0.0001)
        XCTAssertEqual(measured.pageHeights.count, measured.pageCount)
        XCTAssertTrue(measured.pageHeights.allSatisfy { $0 > 0 && $0 <= 360 })
        XCTAssertLessThan(measured.pageHeights.first ?? 360, 360)
    }

    func testPaibanManagerKeepsDoubleColumnAPIAsSingleColumnFallback() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let text = readerV2LongText(repeating: 60)
        let single = manager.divideText(
            text,
            chapterTitle: "双栏接口",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360),
            doubleColumn: false
        )
        let requestedDouble = manager.divideText(
            text,
            chapterTitle: "双栏接口",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360),
            doubleColumn: true
        )

        XCTAssertFalse(single.requestedDoubleColumn)
        XCTAssertTrue(requestedDouble.requestedDoubleColumn)
        XCTAssertFalse(requestedDouble.usesDoubleColumn)
        XCTAssertEqual(requestedDouble.pageSize, CGSize(width: 260, height: 360))
        XCTAssertEqual(requestedDouble.pageCount, single.pageCount)
    }

    func testPaibanManagerTinyPageStillConsumesText() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let text = "一二三四五六"
        let result = manager.divideText(
            text,
            chapterTitle: "",
            chapterIndex: 0,
            pageSize: CGSize(width: 0, height: 0)
        )

        XCTAssertGreaterThan(result.pageCount, 0)
        XCTAssertTrue(result.pages.allSatisfy { $0.displayRange.length > 0 })
        XCTAssertEqual(
            result.pages.map(\.attributedText.string).joined(),
            manager.attributedText(text: text, chapterTitle: "").string
        )
    }

    func testPaibanManagerExposesPageProgressConversion() {
        let manager = PaibanManager(layout: .phone, theme: .standard)

        XCTAssertEqual(
            manager.pageIndex(
                pageCount: 10,
                pageIndex: 0,
                progress: 0.5,
                usesPageIndex: false
            ),
            5
        )
        XCTAssertEqual(
            manager.pageProgress(
                pageCount: 10,
                pageIndex: 5,
                progress: 0,
                usesPageIndex: true
            ),
            Double(5) / Double(9),
            accuracy: 0.0001
        )
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

    private func readerV2LongText(repeating count: Int) -> String {
        Array(
            repeating: "这是一段用于 ReaderV2 分页验证的正文，包含足够多的中文字符和标点，方便 CoreText 稳定换行。",
            count: count
        )
        .joined(separator: "\n")
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
