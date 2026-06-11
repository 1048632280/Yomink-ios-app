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
        XCTAssertEqual(ReaderFontManager.normalizedFontWeightValue(.infinity), 0)
        XCTAssertEqual(ReaderFontManager.normalizedFontWeightValue(-1), 0)
        XCTAssertEqual(ReaderFontManager.normalizedFontWeightValue(7), 5)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(-12), -10)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(12), 10)
        XCTAssertEqual(ReaderFontManager.clampedStrokeWidth(.infinity), 0)
    }

    func testPaibanManagerBuildsTitleAndBodyAttributes() {
        var layout = ReaderLayout.phone
        layout.fontSize = 22
        layout.fontWeight = 0
        layout.titleFontWeight = 3
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
        XCTAssertNil(titleAttributes[.strokeWidth])
        XCTAssertNil(bodyAttributes[.strokeWidth])
        XCTAssertTrue((titleAttributes[.foregroundColor] as? UIColor)?.isEqual(ReaderTheme.standard.contentColor) == true)
        XCTAssertTrue((bodyAttributes[.foregroundColor] as? UIColor)?.isEqual(ReaderTheme.standard.contentColor) == true)
        XCTAssertEqual((titleAttributes[.kern] as? NSNumber)?.doubleValue ?? 0, 2.5, accuracy: 0.0001)
        XCTAssertEqual((bodyAttributes[.kern] as? NSNumber)?.doubleValue ?? 0, 1.5, accuracy: 0.0001)

        let bodyParagraph = bodyAttributes[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(bodyParagraph?.firstLineHeadIndent ?? 0, 44, accuracy: 0.0001)
    }

    func testPaibanManagerRemovesDuplicateBodyTitleAndLeadingWhitespace() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let attributed = manager.attributedText(
            text: "  Chapter 1  \n\u{3000}\tFirst paragraph\n  Second paragraph",
            chapterTitle: "Chapter 1"
        )

        XCTAssertEqual(
            attributed.string,
            "Chapter 1\nFirst paragraph\nSecond paragraph"
        )
        XCTAssertFalse(attributed.string.contains("Chapter 1\nChapter 1"))
        XCTAssertEqual(
            manager.attributedText(text: " Chapter 1 ", chapterTitle: "Chapter 1").string,
            "Chapter 1"
        )
    }

    func testPaibanManagerRemovesContinuationPageFirstLineIndent() {
        var layout = ReaderLayout.phone
        layout.fontSize = 20
        layout.headIndent = 2
        layout.lineSpacing = 0
        layout.paragraphSpacing = 0
        let manager = PaibanManager(layout: layout, theme: .standard)
        let text = Array(repeating: "word", count: 160).joined(separator: " ")
        let result = manager.divideText(
            text,
            chapterTitle: "",
            chapterIndex: 0,
            pageSize: CGSize(width: 180, height: 42)
        )

        let sourceText = result.pages.first?.sourceAttributedText.string ?? ""
        guard let continuationPage = result.pages.first(where: { page in
            guard page.displayRange.location > 0 else {
                return false
            }
            let previous = (sourceText as NSString).substring(
                with: NSRange(location: page.displayRange.location - 1, length: 1)
            )
            return previous != "\n"
        }) else {
            XCTFail("Expected at least one continuation page")
            return
        }

        let continuationParagraph = continuationPage.attributedText.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(continuationParagraph?.firstLineHeadIndent ?? -1, 0, accuracy: 0.0001)

        let originalParagraph = continuationPage.sourceAttributedText.attribute(
            .paragraphStyle,
            at: continuationPage.displayRange.location,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertEqual(originalParagraph?.firstLineHeadIndent ?? 0, 40, accuracy: 0.0001)
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

    @MainActor
    func testReaderPageBackgroundViewAppliesAndClearsThemeImage() {
        let backgroundView = ReaderPageBackgroundView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )

        backgroundView.apply(theme: .standard)

        XCTAssertEqual(backgroundView.displayedImageName, "theme_bg5")
        XCTAssertTrue(backgroundView.backgroundColor?.isEqual(ReaderTheme.standard.backgroundColor) ?? false)
        if UIImage(named: "theme_bg5") != nil {
            XCTAssertTrue(backgroundView.usesPatternImage)
        }

        backgroundView.apply(theme: .dark)

        XCTAssertNil(backgroundView.displayedImageName)
        XCTAssertFalse(backgroundView.usesPatternImage)
        XCTAssertTrue(backgroundView.backgroundColor?.isEqual(ReaderTheme.dark.backgroundColor) ?? false)
    }

    @MainActor
    func testTextReadViewRefreshesContentColor() {
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.contentColor = .red
        view.setAttributedText(NSAttributedString(string: "正文颜色"))

        let red = view.attributedText.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? UIColor
        XCTAssertTrue(red?.isEqual(UIColor.red) ?? false)

        view.contentColor = .blue
        let blue = view.attributedText.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? UIColor
        XCTAssertTrue(blue?.isEqual(UIColor.blue) ?? false)
    }

    @MainActor
    func testTextReadViewBuildsDecorationRectsAndReflowsOnBoundsChange() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let attributed = manager.attributedText(
            text: readerV2LongText(repeating: 20),
            chapterTitle: "绘制测试"
        )
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 340, height: 520))
        view.layout = .phone
        view.setAttributedText(attributed)
        view.layoutIfNeeded()

        let range = NSRange(location: 0, length: min(220, view.attributedText.length))
        let wideRects = view.textRects(for: range)

        XCTAssertNotNil(view.frameRef)
        XCTAssertFalse(wideRects.isEmpty)
        XCTAssertTrue(wideRects.allSatisfy { view.bounds.insetBy(dx: -1, dy: -1).intersects($0) })

        view.frame = CGRect(x: 0, y: 0, width: 220, height: 520)
        view.layoutIfNeeded()
        let narrowRects = view.textRects(for: range)

        XCTAssertNotNil(view.frameRef)
        XCTAssertFalse(narrowRects.isEmpty)
        XCTAssertTrue(narrowRects.allSatisfy { view.bounds.insetBy(dx: -1, dy: -1).intersects($0) })
        XCTAssertGreaterThanOrEqual(narrowRects.count, wideRects.count)
    }

    @MainActor
    func testTextReadViewUsesOriginalDisplayRangeForVerticalPages() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let result = manager.divideText(
            readerV2LongText(repeating: 80),
            chapterTitle: "Display Range",
            chapterIndex: 0,
            pageSize: CGSize(width: 220, height: 260)
        )
        guard result.pages.count > 1 else {
            XCTFail("Expected multiple pages")
            return
        }
        let page = result.pages[1]
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 220, height: 260))
        view.contentRectOverride = view.bounds
        view.setAttributedText(page.sourceAttributedText, displayRange: page.displayRange)
        view.layoutIfNeeded()

        let rects = view.textRects(for: NSRange(location: page.displayRange.location, length: 1))

        XCTAssertNotNil(view.frameRef)
        XCTAssertEqual(view.displayRange, Optional(page.displayRange))
        XCTAssertFalse(rects.isEmpty)
    }

    @MainActor
    func testTextReadViewClampsHighlightRanges() {
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.setAttributedText(NSAttributedString(string: "abcdef"))

        view.setHighlightedRanges([
            NSRange(location: 2, length: 99),
            NSRange(location: 20, length: 1)
        ])

        XCTAssertEqual(view.highlightedRanges, [NSRange(location: 2, length: 4)])
    }

    @MainActor
    func testTextReadViewSelectionTextTrimsEdgesAndKeepsInternalWhitespace() {
        let text = "  first line\nsecond line  "
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.setAttributedText(NSAttributedString(string: text))

        let range = NSRange(location: 0, length: (text as NSString).length)

        XCTAssertEqual(
            view.selectedString(in: range),
            "first line\nsecond line"
        )
    }

    @MainActor
    func testTextReadViewParagraphSelectionTrimsVisibleParagraphEdges() {
        let text = "  first paragraph  \nsecond paragraph"
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.setAttributedText(NSAttributedString(string: text))

        let firstIndex = (text as NSString).range(of: "first").location
        let range = view.paragraphRange(containing: firstIndex)

        XCTAssertEqual(
            range.map { view.selectedString(in: $0, trimsWhitespace: false) },
            Optional("first paragraph")
        )
    }

    @MainActor
    func testTextReadViewSelectionRangeKeepsComposedCharactersWhole() {
        let flag = "\u{1F1E8}\u{1F1F3}"
        let text = "A\(flag)B"
        let view = TextReadView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.setAttributedText(NSAttributedString(string: text))

        let flagRange = (text as NSString).range(of: flag)
        let range = view.normalizedSelectionRange(
            start: flagRange.location + 1,
            end: flagRange.location + 2
        )

        XCTAssertEqual(
            range.map { view.selectedString(in: $0, trimsWhitespace: false) },
            Optional(flag)
        )
    }

    @MainActor
    func testReaderPageViewControllerAppliesThemeAndDecorationRanges() {
        let manager = PaibanManager(layout: .phone, theme: .standard)
        let result = manager.divideText(
            readerV2LongText(repeating: 10),
            chapterTitle: "页面",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360)
        )
        guard let page = result.pages.first else {
            XCTFail("Expected at least one rendered page")
            return
        }
        let model = ReaderPageModel(
            chapterCount: 1,
            chapterIndex: 0,
            pageCount: result.pageCount,
            pageIndex: 0,
            chapterProgress: 0,
            usesPageIndex: true
        )
        let controller = ReaderPageViewController()

        controller.configure(
            page: page,
            pageModel: model,
            layout: .phone,
            theme: .standard
        )
        controller.loadViewIfNeeded()
        controller.setHighlightedRanges([NSRange(location: 0, length: 8)])

        XCTAssertEqual(controller.backgroundView.displayedImageName, "theme_bg5")
        XCTAssertTrue(controller.textView.contentColor.isEqual(ReaderTheme.standard.contentColor))
        XCTAssertEqual(controller.textView.highlightedRanges, [NSRange(location: 0, length: 8)])

        controller.configure(
            page: page,
            pageModel: model,
            layout: .phone,
            theme: .dark
        )

        XCTAssertNil(controller.backgroundView.displayedImageName)
        XCTAssertTrue(controller.textView.contentColor.isEqual(ReaderTheme.dark.contentColor))
    }

    @MainActor
    func testReaderPageViewControllerUpdatesReaderWidgets() {
        let manager = PaibanManager(layout: .notchedPhone, theme: .standard)
        let result = manager.divideText(
            readerV2LongText(repeating: 4),
            chapterTitle: "章节标题",
            chapterIndex: 0,
            pageSize: CGSize(width: 260, height: 360)
        )
        guard let page = result.pages.first else {
            XCTFail("Expected at least one rendered page")
            return
        }
        let model = ReaderPageModel(
            chapterCount: 1,
            chapterIndex: 0,
            pageCount: result.pageCount,
            pageIndex: 0,
            chapterProgress: 0,
            usesPageIndex: true
        )
        var visibility = ReaderSettings.WidgetVisibility.default
        visibility.time = true
        visibility.batteryIcon = true
        visibility.batteryPercentage = true
        visibility.globalProgress = true

        let controller = ReaderPageViewController()
        controller.configure(
            page: page,
            pageModel: model,
            layout: .notchedPhone,
            theme: .standard,
            chapterTitle: "章节标题",
            bookTitle: "Book Title",
            fullProgress: 0.1245,
            widgetVisibility: visibility
        )
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.chapterTitleLabel.text, Optional("Book Title"))
        XCTAssertFalse(controller.chapterTitleLabel.isHidden)
        XCTAssertEqual(controller.chapterTitleLabel.frame.minY, 43, accuracy: 0.1)
        XCTAssertFalse(controller.bottomWidgetView.progressLabel.isHidden)
        XCTAssertEqual(controller.bottomWidgetView.progressLabel.text, Optional("1/\(result.pageCount)  12.45%"))
        XCTAssertFalse(controller.bottomWidgetView.timeLabel.isHidden)
        XCTAssertFalse(controller.bottomWidgetView.batteryView.isHidden)
        XCTAssertFalse(controller.bottomWidgetView.batteryLabel.isHidden)
        XCTAssertEqual(controller.bottomWidgetView.batteryLabel.frame.minX, 0, accuracy: 0.1)
        XCTAssertEqual(controller.bottomWidgetView.batteryView.bounds.size.width, 17, accuracy: 0.1)
        XCTAssertEqual(controller.bottomWidgetView.batteryView.bounds.size.height, 8, accuracy: 0.1)
        XCTAssertLessThan(
            controller.bottomWidgetView.batteryLabel.frame.minX,
            controller.bottomWidgetView.batteryView.frame.minX
        )
        XCTAssertLessThan(
            controller.bottomWidgetView.batteryView.frame.minX,
            controller.bottomWidgetView.timeLabel.frame.minX
        )
        XCTAssertEqual(
            controller.bottomWidgetView.batteryView.frame.minX - controller.bottomWidgetView.batteryLabel.frame.maxX,
            3,
            accuracy: 0.1
        )
        XCTAssertEqual(
            controller.bottomWidgetView.timeLabel.frame.minX - controller.bottomWidgetView.batteryView.frame.maxX,
            3,
            accuracy: 0.1
        )
        XCTAssertEqual(
            controller.bottomWidgetView.batteryLabel.frame.midY,
            controller.bottomWidgetView.batteryView.frame.midY,
            accuracy: 0.1
        )
        XCTAssertEqual(
            controller.bottomWidgetView.batteryView.frame.midY,
            controller.bottomWidgetView.timeLabel.frame.midY,
            accuracy: 0.1
        )
    }

    @MainActor
    func testReaderPageHeaderUsesChapterTitleAfterFirstPage() {
        let controller = ReaderPageViewController()
        let model = readerV2PageModel(pageIndex: 1, pageCount: 3)
        controller.configure(
            page: ReaderDivisionPage(
                attributedText: NSAttributedString(string: "Second page"),
                displayRange: NSRange(location: 0, length: 11),
                usedHeight: 120
            ),
            pageModel: model,
            layout: .phone,
            theme: .standard,
            chapterTitle: "Chapter Title",
            bookTitle: "Book Title"
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.chapterTitleLabel.text, Optional("Chapter Title"))
    }

    @MainActor
    func testBottomWidgetTurnsBatteryLevelGreenWhileCharging() {
        let widget = ReaderBottomWidgetView(frame: CGRect(x: 0, y: 0, width: 180, height: 14))
        widget.batterySnapshotProvider = {
            ReaderBatterySnapshot(level: 0.75, state: .charging)
        }
        widget.updateSettings(
            showTime: true,
            showBatteryView: true,
            showBatteryLabel: true,
            showChapterTitle: true,
            showPageProgress: true,
            showFullProgress: false
        )
        widget.updateContent(
            chapterTitle: "Chapter",
            pageIndex: 0,
            pageCount: 1,
            fullProgress: 0
        )
        widget.layoutIfNeeded()

        XCTAssertEqual(widget.batteryLabel.text, Optional("75%"))
        XCTAssertTrue(widget.batteryLabel.textColor.isEqual(ReaderTheme.standard.headerColor))
        let chargeColor = UIColor(red: 48.0 / 255.0, green: 208.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)
        XCTAssertTrue(widget.batteryView.fillColor.isEqual(chargeColor))
    }

    @MainActor
    func testBottomWidgetTurnsBatteryRedBelowTenPercent() {
        let widget = ReaderBottomWidgetView(frame: CGRect(x: 0, y: 0, width: 180, height: 14))
        widget.batterySnapshotProvider = {
            ReaderBatterySnapshot(level: 0.09, state: .unplugged)
        }
        widget.updateSettings(
            showTime: true,
            showBatteryView: true,
            showBatteryLabel: true,
            showChapterTitle: true,
            showPageProgress: true,
            showFullProgress: false
        )
        widget.updateContent(
            chapterTitle: "Chapter",
            pageIndex: 0,
            pageCount: 1,
            fullProgress: 0
        )
        widget.layoutIfNeeded()

        XCTAssertEqual(widget.batteryLabel.text, Optional("9%"))
        XCTAssertTrue(widget.batteryLabel.textColor.isEqual(ReaderTheme.standard.headerColor))
        XCTAssertTrue(widget.batteryView.fillColor.isEqual(UIColor.red))
    }

    @MainActor
    func testBottomWidgetKeepsBatteryHeaderColorAtTenPercent() {
        let widget = ReaderBottomWidgetView(frame: CGRect(x: 0, y: 0, width: 180, height: 14))
        widget.batterySnapshotProvider = {
            ReaderBatterySnapshot(level: 0.10, state: .unplugged)
        }
        widget.updateSettings(
            showTime: true,
            showBatteryView: true,
            showBatteryLabel: true,
            showChapterTitle: true,
            showPageProgress: true,
            showFullProgress: false
        )
        widget.updateContent(
            chapterTitle: "Chapter",
            pageIndex: 0,
            pageCount: 1,
            fullProgress: 0
        )
        widget.layoutIfNeeded()

        XCTAssertEqual(widget.batteryLabel.text, Optional("10%"))
        XCTAssertTrue(widget.batteryLabel.textColor.isEqual(ReaderTheme.standard.headerColor))
        XCTAssertTrue(widget.batteryView.fillColor.isEqual(ReaderTheme.standard.headerColor))
    }

    @MainActor
    func testReaderPageContainersExposeExpectedModes() {
        let pageContainer = ReaderPageContainer()
        pageContainer.loadViewIfNeeded()

        XCTAssertEqual(pageContainer.turnPageType, .horizontalScroll)
        XCTAssertFalse(pageContainer.pageViewController.isDoubleSided)

        let curlContainer = ReaderPageCurlContainer()
        curlContainer.loadViewIfNeeded()

        XCTAssertEqual(curlContainer.turnPageType, .pageCurl)
        XCTAssertTrue(curlContainer.pageViewController.isDoubleSided)
        XCTAssertEqual(
            curlContainer.pageViewController(
                curlContainer.pageViewController,
                spineLocationFor: .portrait
            ),
            .min
        )
    }

    @MainActor
    func testReaderPageContainerDisplaysAdjacentPagesAndNotifiesCompletion() {
        let container = ReaderPageContainer()
        container.loadViewIfNeeded()
        let firstModel = readerV2PageModel(pageIndex: 0, pageCount: 2)
        let secondModel = readerV2PageModel(pageIndex: 1, pageCount: 2)
        let firstController = readerV2PageController(pageModel: firstModel)
        var completedModel: ReaderPageModel?

        container.makePageController = { [weak self] model in
            self?.readerV2PageController(pageModel: model)
        }
        container.adjacentPageModel = { model, delta in
            guard model.pageIndex == 0, delta == 1 else {
                return nil
            }
            return secondModel
        }
        container.onPageTurnCompleted = { model in
            completedModel = model
        }

        container.display(
            pageModel: firstModel,
            pageController: firstController,
            direction: .forward,
            animated: false
        )
        let next = container.pageViewController(
            container.pageViewController,
            viewControllerAfter: firstController
        ) as? ReaderPageViewController

        XCTAssertEqual(container.currentPageModel, Optional(firstModel))
        XCTAssertEqual(next?.pageModel, Optional(secondModel))

        let secondController = readerV2PageController(pageModel: secondModel)
        container.pageViewController.setViewControllers(
            [secondController],
            direction: .forward,
            animated: false
        )
        container.pageViewController(
            container.pageViewController,
            didFinishAnimating: true,
            previousViewControllers: [firstController],
            transitionCompleted: true
        )

        XCTAssertEqual(completedModel, Optional(secondModel))
        XCTAssertEqual(container.currentPageModel, Optional(secondModel))
    }

    @MainActor
    func testReaderScrollContainerLoadsSectionsRowsAndHeights() {
        let container = ReaderScrollContainer()
        container.loadViewIfNeeded()
        let firstModel = readerV2PageModel(pageIndex: 0, pageCount: 2)
        let secondModel = readerV2PageModel(pageIndex: 1, pageCount: 2)
        let section = ReaderScrollSection(
            chapterIndex: 0,
            title: "滚动章节",
            timestamp: Date(timeIntervalSince1970: 0),
            items: [
                NSAttributedString(string: "第一页"),
                NSAttributedString(string: "第二页")
            ],
            heights: [120, 180],
            pageModels: [firstModel, secondModel],
            fullProgresses: [0.1, 0.2],
            bookTitle: "Book Title"
        )

        container.reload(
            sections: [section],
            layout: .phone,
            theme: .standard
        )
        container.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        container.view.layoutIfNeeded()

        XCTAssertEqual(container.turnPageType, .verticalContinuous)
        XCTAssertFalse(container.tableView.showsVerticalScrollIndicator)
        XCTAssertNil(container.tableView.layer.mask)
        XCTAssertEqual(container.tableView.contentInset.top, 50, accuracy: 0.1)
        XCTAssertEqual(container.tableView.contentInset.bottom, 35, accuracy: 0.1)
        XCTAssertFalse(container.bottomWidgetView.progressLabel.isHidden)
        XCTAssertEqual(container.tableView.numberOfSections, 1)
        XCTAssertEqual(container.tableView.numberOfRows(inSection: 0), 2)
        XCTAssertEqual(
            container.tableView(
                container.tableView,
                heightForRowAt: IndexPath(row: 1, section: 0)
            ),
            180
        )
        XCTAssertEqual(container.indexPath(for: secondModel), Optional(IndexPath(row: 1, section: 0)))

        container.display(
            pageModel: firstModel,
            pageController: readerV2PageController(pageModel: firstModel),
            direction: .forward,
            animated: false
        )

        XCTAssertEqual(container.currentPageModel, Optional(firstModel))
        XCTAssertEqual(container.chapterTitleLabel.text, Optional("滚动章节"))
    }

    @MainActor
    func testReaderScrollContainerAppendsAndPrependsSections() {
        let container = ReaderScrollContainer()
        container.loadViewIfNeeded()
        container.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let firstModel = readerV2PageModel(pageIndex: 0, pageCount: 1, chapterIndex: 1)
        let nextModel = readerV2PageModel(pageIndex: 0, pageCount: 1, chapterIndex: 2)
        let previousModel = readerV2PageModel(pageIndex: 0, pageCount: 1, chapterIndex: 0)
        let first = readerV2ScrollSection(chapterIndex: 1, model: firstModel)
        let next = readerV2ScrollSection(chapterIndex: 2, model: nextModel)
        let previous = readerV2ScrollSection(chapterIndex: 0, model: previousModel)

        container.reload(sections: [first], layout: .phone, theme: .standard)
        container.appendSections([next])
        container.prependSections([previous])
        container.view.layoutIfNeeded()

        XCTAssertEqual(container.tableView.numberOfSections, 3)
        XCTAssertEqual(container.indexPath(for: previousModel), Optional(IndexPath(row: 0, section: 0)))
        XCTAssertEqual(container.indexPath(for: firstModel), Optional(IndexPath(row: 0, section: 1)))
        XCTAssertEqual(container.indexPath(for: nextModel), Optional(IndexPath(row: 0, section: 2)))
    }

    @MainActor
    func testReaderScrollPageCellConfiguresPageModelAndText() {
        let cell = ReaderScrollPageCell(
            style: .default,
            reuseIdentifier: ReaderScrollPageCell.reuseIdentifier
        )
        let model = readerV2PageModel(pageIndex: 0, pageCount: 1)

        cell.configure(
            attributedText: NSAttributedString(string: "纵向页面"),
            pageModel: model,
            layout: .phone,
            theme: .dark
        )
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        cell.layoutIfNeeded()

        XCTAssertEqual(cell.pageModel, Optional(model))
    }

    func testReaderThemeManagerMapsSettingsAndInvalidatesPagination() {
        var settings = ReaderSettings.default
        settings.pageMode = .curl
        settings.theme = .dark
        settings.layoutPreset = .relaxed
        settings.fontSize = 24

        let layout = ReaderThemeManager.layout(from: settings)
        let theme = ReaderThemeManager.theme(from: settings)

        XCTAssertEqual(ReaderThemeManager.turnPageType(from: settings), .pageCurl)
        XCTAssertEqual(layout.fontSize, 24)
        XCTAssertEqual(layout.topMargin, CGFloat(ReaderSettings.LayoutValues.relaxed.bodyTopMargin))
        XCTAssertTrue(theme.isDark)

        var themeChanged = settings
        themeChanged.theme = .white
        XCTAssertTrue(ReaderThemeManager.needsRepagination(from: settings, to: themeChanged))
        XCTAssertTrue(ReaderThemeManager.needsChromeRefresh(from: settings, to: themeChanged))

        var chromeOnlyChanged = settings
        chromeOnlyChanged.keepScreenAwake.toggle()
        XCTAssertFalse(ReaderThemeManager.needsRepagination(from: settings, to: chromeOnlyChanged))
        XCTAssertTrue(ReaderThemeManager.needsChromeRefresh(from: settings, to: chromeOnlyChanged))
    }

    @MainActor
    func testReaderV2SettingsPanelEmitsSettingsChanges() {
        let panel = ReaderV2SettingsPanelView()
        var emittedSettings: [ReaderSettings] = []
        panel.onChange = { settings in
            emittedSettings.append(settings)
        }

        panel.pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases.firstIndex(of: .scroll) ?? 0
        panel.pageModeControl.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.pageMode, .scroll)

        panel.themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases.firstIndex(of: .dark) ?? 0
        panel.themeControl.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.theme, .dark)

        panel.layoutControl.selectedSegmentIndex = ReaderSettings.LayoutPreset.allCases.firstIndex(of: .compact) ?? 0
        panel.layoutControl.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.layoutPreset, .compact)

        var fontSettings = ReaderSettings.default
        fontSettings.fontSize = 21
        panel.setSettings(fontSettings)
        panel.fontIncreaseButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(emittedSettings.last?.fontSize, 22)

        panel.quickControl.selectedSegmentIndex = 1
        panel.quickControl.sendActions(for: .valueChanged)
        XCTAssertEqual(panel.quickControl.selectedSegmentIndex, 1)

        panel.keepAwakeSwitch.isOn = true
        panel.keepAwakeSwitch.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.keepScreenAwake, true)

        panel.homeIndicatorSwitch.isOn = false
        panel.homeIndicatorSwitch.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.autoHideHomeIndicator, false)

        panel.statusBarSwitch.isOn = false
        panel.statusBarSwitch.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.autoHideStatusBar, false)

        panel.edgeSwipeBackSwitch.isOn = false
        panel.edgeSwipeBackSwitch.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.edgeSwipeBackEnabled, false)

        panel.chapterTitleSwitch.isOn = false
        panel.globalProgressSwitch.isOn = true
        panel.globalProgressSwitch.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSettings.last?.widgetVisibility.chapterTitle, false)
        XCTAssertEqual(emittedSettings.last?.widgetVisibility.globalProgress, true)
    }

    @MainActor
    func testReaderV2MenuViewShowsHidesAndDispatchesActions() {
        let menuView = ReaderV2MenuView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let model = readerV2PageModel(pageIndex: 1, pageCount: 3)
        var closeCount = 0
        var catalogCount = 0
        var bookmarkCount = 0
        var settingsCount = 0
        var previousChapterCount = 0
        var autoReadCount = 0
        var nextChapterCount = 0
        var darkModeCount = 0
        var bookDetailCount = 0
        var contentSearchCount = 0
        var contentFilterCount = 0
        var pageTouchAreasCount = 0
        var progressBeganCount = 0
        var changedProgress: Double?
        var finishedProgress: Double?

        menuView.onClose = {
            closeCount += 1
        }
        menuView.onCatalog = {
            catalogCount += 1
        }
        menuView.onBookmark = {
            bookmarkCount += 1
        }
        menuView.onSettings = {
            settingsCount += 1
        }
        menuView.onPreviousChapter = {
            previousChapterCount += 1
        }
        menuView.onAutoRead = {
            autoReadCount += 1
        }
        menuView.onNextChapter = {
            nextChapterCount += 1
        }
        menuView.onDarkMode = {
            darkModeCount += 1
        }
        menuView.onMoreBookDetail = {
            bookDetailCount += 1
        }
        menuView.onMoreContentSearch = {
            contentSearchCount += 1
        }
        menuView.onMoreContentFilter = {
            contentFilterCount += 1
        }
        menuView.onMorePageTouchAreas = {
            pageTouchAreasCount += 1
        }
        menuView.onProgressSliderBegan = {
            progressBeganCount += 1
        }
        menuView.onProgressSliderChanged = { progress in
            changedProgress = progress
        }
        menuView.onProgressSliderFinished = { progress in
            finishedProgress = progress
        }
        menuView.configure(bookTitle: "Book")
        menuView.updateProgress(
            chapterTitle: "Chapter",
            chapterProgress: model.chapterProgress,
            globalProgress: 0.42,
            pageIndex: model.pageIndex,
            pageCount: model.pageCount
        )
        menuView.updateChapterNavigation(canGoPrevious: true, canGoNext: true)

        menuView.setMenuVisible(true, animated: false)
        XCTAssertTrue(menuView.isMenuVisible)
        XCTAssertFalse(menuView.isHidden)
        XCTAssertTrue(menuView.isUserInteractionEnabled)

        menuView.closeButton.sendActions(for: .touchUpInside)
        menuView.catalogButton.sendActions(for: .touchUpInside)
        menuView.bookmarkButton.sendActions(for: .touchUpInside)
        menuView.settingsButton.sendActions(for: .touchUpInside)
        menuView.previousChapterButton.sendActions(for: .touchUpInside)
        menuView.autoReadButton.sendActions(for: .touchUpInside)
        menuView.nextChapterButton.sendActions(for: .touchUpInside)
        menuView.darkModeButton.sendActions(for: .touchUpInside)

        menuView.moreButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(menuView.isMoreMenuVisible)
        menuView.moreButton.sendActions(for: .touchUpInside)
        XCTAssertFalse(menuView.isMoreMenuVisible)
        XCTAssertTrue(menuView.isMenuVisible)
        menuView.moreButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(menuView.isMoreMenuVisible)
        menuView.moreBookDetailButton.sendActions(for: .touchUpInside)
        menuView.setMoreMenuVisible(true, animated: false)
        menuView.moreContentSearchButton.sendActions(for: .touchUpInside)
        menuView.setMoreMenuVisible(true, animated: false)
        menuView.moreContentFilterButton.sendActions(for: .touchUpInside)
        menuView.setMoreMenuVisible(true, animated: false)
        menuView.morePageTouchAreasButton.sendActions(for: .touchUpInside)

        menuView.progressSlider.sendActions(for: .touchDown)
        menuView.progressSlider.value = 0.75
        menuView.progressSlider.sendActions(for: .valueChanged)
        menuView.progressSlider.sendActions(for: .touchUpInside)

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(catalogCount, 1)
        XCTAssertEqual(bookmarkCount, 1)
        XCTAssertEqual(settingsCount, 1)
        XCTAssertEqual(previousChapterCount, 1)
        XCTAssertEqual(autoReadCount, 1)
        XCTAssertEqual(nextChapterCount, 1)
        XCTAssertEqual(darkModeCount, 1)
        XCTAssertEqual(bookDetailCount, 1)
        XCTAssertEqual(contentSearchCount, 1)
        XCTAssertEqual(contentFilterCount, 1)
        XCTAssertEqual(pageTouchAreasCount, 1)
        XCTAssertEqual(progressBeganCount, 1)
        XCTAssertEqual(changedProgress ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(finishedProgress ?? 0, 0.75, accuracy: 0.0001)

        menuView.updateBookmark(isBookmarked: true)
        XCTAssertEqual(
            menuView.bookmarkButton.accessibilityLabel,
            NSLocalizedString("reader.bookmark.remove", comment: "")
        )
        menuView.setBookmarkButtonEnabled(false)
        XCTAssertFalse(menuView.bookmarkButton.isEnabled)
        menuView.updateChapterNavigation(canGoPrevious: false, canGoNext: true)
        XCTAssertFalse(menuView.previousChapterButton.isEnabled)
        XCTAssertTrue(menuView.nextChapterButton.isEnabled)

        menuView.setMenuVisible(false, animated: false)
        XCTAssertFalse(menuView.isMenuVisible)
        XCTAssertFalse(menuView.isMoreMenuVisible)
        XCTAssertTrue(menuView.isHidden)
        XCTAssertFalse(menuView.isUserInteractionEnabled)
    }

    @MainActor
    func testReaderSystemAppearanceControllerFollowsReaderRules() {
        let controller = ReaderSystemAppearanceController()
        var settings = ReaderSettings.default

        controller.update(
            settings: settings,
            theme: .standard,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertTrue(controller.prefersStatusBarHidden)
        XCTAssertEqual(controller.preferredStatusBarStyle, .darkContent)

        controller.update(
            settings: settings,
            theme: .standard,
            isViewVisible: true,
            isMenuVisible: true,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertFalse(controller.prefersStatusBarHidden)

        controller.update(
            settings: settings,
            theme: .standard,
            isViewVisible: true,
            isMenuVisible: true,
            isSettingsPanelVisible: true,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertTrue(controller.prefersStatusBarHidden)

        controller.update(
            settings: settings,
            theme: .standard,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: true,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertTrue(controller.prefersStatusBarHidden)

        controller.update(
            settings: settings,
            theme: .dark,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertTrue(controller.prefersStatusBarHidden)
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)

        controller.update(
            settings: settings,
            theme: .dark,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: true,
            isAutoReading: false
        )
        XCTAssertTrue(controller.prefersStatusBarHidden)

        settings.autoHideStatusBar = false
        settings.autoHideHomeIndicator = false
        controller.update(
            settings: settings,
            theme: .dark,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertFalse(controller.prefersStatusBarHidden)
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)

        controller.update(
            settings: settings,
            theme: .dark,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: true,
            isAutoReadPanelVisible: false,
            isAutoReading: false
        )
        XCTAssertFalse(controller.prefersStatusBarHidden)

        controller.update(
            settings: settings,
            theme: .dark,
            isViewVisible: true,
            isMenuVisible: false,
            isSettingsPanelVisible: false,
            isAutoReadPanelVisible: false,
            isAutoReading: true
        )
        XCTAssertFalse(controller.prefersStatusBarHidden)

        controller.reset()
        XCTAssertFalse(controller.prefersStatusBarHidden)
    }

    @MainActor
    func testReaderV2HomeIndicatorPreferencesFollowReaderSettings() {
        var settings = ReaderSettings.default

        XCTAssertFalse(ReaderV2ViewController.homeIndicatorAutoHidden(for: settings))
        XCTAssertEqual(ReaderV2ViewController.screenEdgesDeferringSystemGestures(for: settings), .bottom)

        settings.autoHideHomeIndicator = false

        XCTAssertFalse(ReaderV2ViewController.homeIndicatorAutoHidden(for: settings))
        XCTAssertEqual(ReaderV2ViewController.screenEdgesDeferringSystemGestures(for: settings), [])
    }

    @MainActor
    func testReaderAutoReadControllerLifecycleAndAdvance() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 1_000)
        let controller = ReaderAutoReadController()
        var saveCount = 0
        controller.onProgressSaveNeeded = {
            saveCount += 1
        }

        controller.start(scrollView: scrollView, speed: 120)
        XCTAssertTrue(controller.isReading)
        XCTAssertTrue(controller.hasDisplayLink)

        controller.advance(by: 0.5)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)

        controller.pauseForBackground()
        XCTAssertTrue(controller.isReading)
        XCTAssertTrue(controller.isPausedForBackground)
        XCTAssertFalse(controller.hasDisplayLink)
        XCTAssertGreaterThanOrEqual(saveCount, 1)

        controller.resumeAfterBackgroundIfNeeded(scrollView: scrollView)
        XCTAssertTrue(controller.isReading)
        XCTAssertFalse(controller.isPausedForBackground)
        XCTAssertTrue(controller.hasDisplayLink)

        controller.stop()
        XCTAssertFalse(controller.isReading)
        XCTAssertFalse(controller.hasDisplayLink)
    }

    @MainActor
    func testReaderAutoReadSpeedRangeStaysPointBased() {
        XCTAssertEqual(ReaderSettings.minimumAutoReadSpeed, 20)
        XCTAssertEqual(ReaderSettings.maximumAutoReadSpeed, 180)
        XCTAssertEqual(ReaderAutoReadController.normalizedSpeed(1), 20)
        XCTAssertEqual(ReaderAutoReadController.normalizedSpeed(400), 180)
    }

    @MainActor
    func testReaderAutoReadControllerStopsAtContentEnd() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 100)
        let controller = ReaderAutoReadController()
        var reachedEndCount = 0
        controller.onReachedEnd = {
            reachedEndCount += 1
            return false
        }

        controller.start(scrollView: scrollView, speed: 120)
        controller.advance(by: 0.5)

        XCTAssertEqual(reachedEndCount, 1)
        XCTAssertFalse(controller.isReading)
        XCTAssertFalse(controller.hasDisplayLink)
    }

    @MainActor
    func testReaderAutoReadControllerPausesAtLoadedEndWhenContinuationStarts() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 100)
        let controller = ReaderAutoReadController()
        var reachedEndCount = 0
        controller.onReachedEnd = {
            reachedEndCount += 1
            return true
        }

        controller.start(scrollView: scrollView, speed: 120)
        controller.advance(by: 0.5)

        XCTAssertEqual(reachedEndCount, 1)
        XCTAssertTrue(controller.isReading)
        XCTAssertTrue(controller.isPausedForContentLoad)
        XCTAssertFalse(controller.hasDisplayLink)

        controller.resumeAfterContentLoadIfNeeded(scrollView: scrollView)
        XCTAssertTrue(controller.isReading)
        XCTAssertFalse(controller.isPausedForContentLoad)
        XCTAssertTrue(controller.hasDisplayLink)
    }

    @MainActor
    func testReaderV2AutoReadPanelEmitsSpeedAndExit() {
        let panel = ReaderV2AutoReadPanelView()
        var emittedSpeed: Double?
        var exitCount = 0
        panel.onSpeedChange = { speed in
            emittedSpeed = speed
        }
        panel.onExit = {
            exitCount += 1
        }

        panel.setSpeed(400)
        XCTAssertEqual(panel.speedSlider.value, Float(ReaderSettings.maximumAutoReadSpeed))

        panel.speedSlider.value = 96
        panel.speedSlider.sendActions(for: .valueChanged)
        XCTAssertEqual(emittedSpeed ?? 0, 96, accuracy: 0.01)

        panel.exitButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(exitCount, 1)

        panel.setPanelVisible(true, animated: false)
        XCTAssertTrue(panel.isPanelVisible)
        panel.setPanelVisible(false, animated: false)
        XCTAssertFalse(panel.isPanelVisible)
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
        let secondText = try await provider.textAsync(forChapterAt: 1)
        XCTAssertEqual(secondText, fixture.secondText)
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

    private func readerV2PageModel(
        pageIndex: Int,
        pageCount: Int,
        chapterIndex: Int = 0
    ) -> ReaderPageModel {
        ReaderPageModel(
            chapterCount: 1,
            chapterIndex: chapterIndex,
            pageCount: pageCount,
            pageIndex: pageIndex,
            chapterProgress: ReaderPageCalculator.pageProgress(
                pageCount: pageCount,
                pageIndex: pageIndex,
                progress: 0,
                usesPageIndex: true
            ),
            usesPageIndex: true
        )
    }

    @MainActor
    private func readerV2PageController(pageModel: ReaderPageModel) -> ReaderPageViewController {
        let controller = ReaderPageViewController()
        let text = "第 \(pageModel.pageIndex + 1) 页"
        controller.configure(
            page: ReaderDivisionPage(
                attributedText: NSAttributedString(string: text),
                displayRange: NSRange(location: 0, length: (text as NSString).length),
                usedHeight: 120
            ),
            pageModel: pageModel,
            layout: .phone,
            theme: .standard
        )
        return controller
    }

    private func readerV2ScrollSection(
        chapterIndex: Int,
        model: ReaderPageModel
    ) -> ReaderScrollSection {
        let text = "Chapter \(chapterIndex)"
        let attributed = NSAttributedString(string: text)
        return ReaderScrollSection(
            chapterIndex: chapterIndex,
            title: text,
            timestamp: Date(timeIntervalSince1970: Double(chapterIndex)),
            items: [attributed],
            heights: [120],
            pageModels: [model],
            fullProgresses: [0]
        )
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
