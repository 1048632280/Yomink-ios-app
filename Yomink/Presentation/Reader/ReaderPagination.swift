import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

private final class ChapterPaginator: @unchecked Sendable {
    struct Page {
        let attributedText: NSAttributedString
        let startDisplayUTF16Index: Int
        let displayUTF16Length: Int
        let usedHeight: CGFloat
    }

    private let attributedText: NSAttributedString
    private(set) var pageCharacterRanges: [NSRange] = []
    private(set) var pageStartDisplayUTF16Indexes: [Int] = []
    private(set) var pageUsedHeights: [CGFloat] = []

    var pageCount: Int {
        pageCharacterRanges.count
    }

    init(
        text: String,
        typography: ReaderTypography,
        fittingSize: CGSize
    ) {
        attributedText = typography.attributedString(for: text)
        buildPages(fittingSize: fittingSize)
    }

    func page(at index: Int) -> Page {
        guard pageCharacterRanges.isEmpty == false else {
            return Page(
                attributedText: NSAttributedString(string: ""),
                startDisplayUTF16Index: 0,
                displayUTF16Length: 0,
                usedHeight: 1
            )
        }

        let safeIndex = min(max(index, 0), pageCharacterRanges.count - 1)
        let range = pageCharacterRanges[safeIndex]
        let pageText = attributedText.attributedSubstring(from: range)
        let usedHeight = pageUsedHeights.indices.contains(safeIndex)
            ? pageUsedHeights[safeIndex]
            : 1

        return Page(
            attributedText: pageText,
            startDisplayUTF16Index: range.location,
            displayUTF16Length: range.length,
            usedHeight: usedHeight
        )
    }

    func pageStartDisplayUTF16Index(at index: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let safeIndex = min(max(index, 0), pageStartDisplayUTF16Indexes.count - 1)
        return pageStartDisplayUTF16Indexes[safeIndex]
    }

    func pageIndex(containingDisplayUTF16Index displayIndex: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let clampedIndex = min(max(displayIndex, 0), attributedText.length)
        var lowerBound = 0
        var upperBound = pageStartDisplayUTF16Indexes.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if pageStartDisplayUTF16Indexes[middle] <= clampedIndex {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return max(0, lowerBound - 1)
    }

    private func buildPages(fittingSize: CGSize) {
        let textLength = attributedText.length
        guard textLength > 0 else {
            return
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: max(fittingSize.width, 1),
            height: max(fittingSize.height, 1)
        )
        let path = CGMutablePath()
        path.addRect(pageRect)
        var startIndex = 0

        while startIndex < textLength {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: startIndex, length: 0),
                path,
                nil
            )
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let visibleLength = max(visibleRange.length, 1)
            let characterRange = NSRange(
                location: startIndex,
                length: min(visibleLength, textLength - startIndex)
            )

            guard characterRange.length > 0 else {
                break
            }

            let pageString = attributedText.attributedSubstring(from: characterRange).string
            if pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                pageCharacterRanges.append(characterRange)
                pageStartDisplayUTF16Indexes.append(characterRange.location)
                pageUsedHeights.append(
                    Self.usedHeight(
                        for: frame,
                        fallback: 1
                    )
                )
            }

            startIndex = characterRange.location + characterRange.length
        }

        if pageCharacterRanges.isEmpty {
            pageCharacterRanges = [NSRange(location: 0, length: textLength)]
            pageStartDisplayUTF16Indexes = [0]
            pageUsedHeights = [max(1, fittingSize.height)]
        }
    }

    private static func usedHeight(for frame: CTFrame, fallback: CGFloat) -> CGFloat {
        let lines = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(lines)
        guard lineCount > 0 else {
            return max(1, fallback)
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let firstLine = unsafeBitCast(
            CFArrayGetValueAtIndex(lines, 0),
            to: CTLine.self
        )
        let lastLine = unsafeBitCast(
            CFArrayGetValueAtIndex(lines, lineCount - 1),
            to: CTLine.self
        )

        var firstAscent: CGFloat = 0
        var firstDescent: CGFloat = 0
        var firstLeading: CGFloat = 0
        CTLineGetTypographicBounds(
            firstLine,
            &firstAscent,
            &firstDescent,
            &firstLeading
        )

        var lastAscent: CGFloat = 0
        var lastDescent: CGFloat = 0
        var lastLeading: CGFloat = 0
        CTLineGetTypographicBounds(
            lastLine,
            &lastAscent,
            &lastDescent,
            &lastLeading
        )

        let top = origins[0].y + firstAscent
        let bottom = origins[lineCount - 1].y - lastDescent
        return max(1, ceil(top - bottom))
    }
}

struct CollectionReaderPage: Equatable, @unchecked Sendable {
    let id: String
    let bookID: UUID
    let chapterID: UUID
    let chapterTitle: String
    let chapterIndex: Int
    let pageIndex: Int
    let localPageIndex: Int
    let chapterPageCount: Int
    let chapterPageStartOffsets: [Int]
    let startAbsoluteOffset: Int
    let endAbsoluteOffset: Int
    let startChapterOffset: Int
    let globalProgress: Double
    let containsChapterTitle: Bool
    let verticalExtent: CGFloat
    let contentLayout: ReaderLayoutConfiguration
    let attributedText: NSAttributedString
    let text: String

    static func == (lhs: CollectionReaderPage, rhs: CollectionReaderPage) -> Bool {
        lhs.id == rhs.id
    }
}

private enum CollectionReaderError: LocalizedError {
    case bookNotFound
    case emptyPage

    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return NSLocalizedString("library.error.bookNotFound", comment: "")
        case .emptyPage:
            return NSLocalizedString("reader.emptyChapter", comment: "")
        }
    }
}

enum CollectionReaderPaginator {
    static func makePage(
        book: Book,
        chapters: [Chapter],
        absoluteOffset: Int,
        forcedPageIndex: Int? = nil,
        settings: ReaderSettings,
        filterRules: [TextFilterRule],
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        widgetInsets: UIEdgeInsets,
        isVerticalViewport: Bool,
        targetLocalPageIndex: Int? = nil,
        fileStore: AppFileStore
    ) async throws -> CollectionReaderPage {
        try await Task.detached(priority: .userInitiated) {
            guard !chapters.isEmpty else {
                throw CollectionReaderError.bookNotFound
            }

            let chapterIndex = Self.chapterIndex(
                containing: absoluteOffset,
                in: chapters
            ) ?? 0
            let chapter = chapters[chapterIndex]
            let chapterOffset = min(
                max(absoluteOffset - chapter.startOffset, 0),
                max(chapter.byteLength - 1, 0)
            )
            let text = try ReaderChapterTextReader.readText(
                book: book,
                chapter: chapter,
                fileStore: fileStore
            )
            try Task.checkCancellation()

            let filtered = ReaderTextFilter.readingFilteredText(
                rules: filterRules,
                to: text
            )
            let isPlaceholderPage = filtered.displayText.isEmpty
            let displayText = isPlaceholderPage
                ? NSLocalizedString("reader.emptyChapter", comment: "")
                : filtered.displayText
            let normalizedSettings = settings.normalized
            let effectiveWidgetInsets = isVerticalViewport ? .zero : widgetInsets
            let layout = Self.effectiveLayout(
                settings: normalizedSettings,
                viewportSize: viewportSize,
                safeAreaInsets: safeAreaInsets,
                widgetInsets: effectiveWidgetInsets
            )
            let fittingSize = layout.contentRect(in: CGRect(origin: .zero, size: viewportSize)).size
            let typography = ReaderTypography(
                settings: normalizedSettings,
                chapterTitle: chapter.title
            )
            let paginator = ChapterPaginator(
                text: displayText,
                typography: typography,
                fittingSize: fittingSize
            )
            try Task.checkCancellation()

            let displayIndex = isPlaceholderPage
                ? 0
                : filtered.displayUTF16Index(containingOriginalByteOffset: chapterOffset)
            let localPageIndex = targetLocalPageIndex
                .map { min(max($0, 0), max(paginator.pageCount - 1, 0)) }
                ?? paginator.pageIndex(
                    containingDisplayUTF16Index: displayIndex
                )
            let page = paginator.page(at: localPageIndex)
            let chapterPageStartOffsets: [Int] = isPlaceholderPage
                ? [0]
                : (0..<paginator.pageCount).map { index in
                    filtered.originalByteOffset(
                        atDisplayUTF16Index: paginator.pageStartDisplayUTF16Index(at: index)
                    )
                }
            let pageEndDisplayIndex = page.startDisplayUTF16Index + page.displayUTF16Length
            let pageStartOffset: Int
            let pageEndOffset: Int
            if isPlaceholderPage {
                pageStartOffset = min(chapterOffset, max(chapter.byteLength - 1, 0))
                pageEndOffset = max(pageStartOffset + 1, chapter.byteLength)
            } else {
                pageStartOffset = filtered.originalByteOffset(
                    atDisplayUTF16Index: page.startDisplayUTF16Index
                )
                pageEndOffset = max(
                    filtered.originalByteOffset(atDisplayUTF16Index: pageEndDisplayIndex),
                    pageStartOffset + 1
                )
            }
            let startAbsoluteOffset = chapter.startOffset + pageStartOffset
            let endAbsoluteOffset = isPlaceholderPage
                ? max(chapter.startOffset + pageEndOffset, startAbsoluteOffset + 1)
                : min(
                    chapter.startOffset + pageEndOffset,
                    chapter.endOffset
                )
            let pageIndex = forcedPageIndex ?? localPageIndex
            let pageText = page.attributedText.string
            let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
            let globalProgress = min(max(Double(startAbsoluteOffset) / Double(totalByteLength), 0), 1)
            let containsChapterTitle = localPageIndex == 0
                && Self.pageContainsChapterTitle(pageText, chapterTitle: chapter.title)
            let pageGap = Self.pageGap(
                displayText: displayText,
                pageEndDisplayIndex: pageEndDisplayIndex,
                isChapterEnd: endAbsoluteOffset >= chapter.endOffset,
                fontSize: CGFloat(normalizedSettings.fontSize),
                layout: layout
            )
            let verticalExtent = ceil(page.usedHeight + pageGap)

            guard endAbsoluteOffset > startAbsoluteOffset else {
                throw CollectionReaderError.emptyPage
            }

            return CollectionReaderPage(
                id: "\(chapter.id.uuidString)-\(pageIndex)-\(startAbsoluteOffset)",
                bookID: book.id,
                chapterID: chapter.id,
                chapterTitle: chapter.title,
                chapterIndex: chapterIndex,
                pageIndex: pageIndex,
                localPageIndex: localPageIndex,
                chapterPageCount: paginator.pageCount,
                chapterPageStartOffsets: chapterPageStartOffsets,
                startAbsoluteOffset: startAbsoluteOffset,
                endAbsoluteOffset: endAbsoluteOffset,
                startChapterOffset: pageStartOffset,
                globalProgress: globalProgress,
                containsChapterTitle: containsChapterTitle,
                verticalExtent: verticalExtent,
                contentLayout: layout,
                attributedText: page.attributedText,
                text: pageText
            )
        }.value
    }

    private static func chapterIndex(
        containing absoluteOffset: Int,
        in chapters: [Chapter]
    ) -> Int? {
        if let index = chapters.firstIndex(where: { absoluteOffset >= $0.startOffset && absoluteOffset < $0.endOffset }) {
            return index
        }
        if absoluteOffset >= (chapters.last?.endOffset ?? 0) {
            return chapters.indices.last
        }
        return chapters.indices.first
    }

    private static func effectiveLayout(
        settings: ReaderSettings,
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        widgetInsets: UIEdgeInsets
    ) -> ReaderLayoutConfiguration {
        var layout = settings.effectiveLayoutConfiguration
        if safeAreaInsets.top > 0 {
            layout.topMargin = max(layout.topMargin, safeAreaInsets.top + 12)
        }
        if safeAreaInsets.bottom > 0 {
            layout.bottomMargin = max(layout.bottomMargin, safeAreaInsets.bottom + 2)
        }
        if safeAreaInsets.left > 0 {
            layout.leftMargin = max(layout.leftMargin, safeAreaInsets.left + 12)
        }
        if safeAreaInsets.right > 0 {
            layout.rightMargin = max(layout.rightMargin, safeAreaInsets.right + 12)
        }
        layout.topMargin = max(layout.topMargin, widgetInsets.top)
        layout.bottomMargin = max(layout.bottomMargin, widgetInsets.bottom)
        return layout
    }

    static func withDisabledWidgets(_ settings: ReaderSettings) -> ReaderSettings {
        var settings = settings
        settings.widgetVisibility = .hidden
        return settings
    }

    private static func pageGap(
        displayText: String,
        pageEndDisplayIndex: Int,
        isChapterEnd: Bool,
        fontSize: CGFloat,
        layout: ReaderLayoutConfiguration
    ) -> CGFloat {
        if isChapterEnd {
            return chapterEndGap(fontSize: fontSize, layout: layout)
        }
        guard pageEndDisplayIndex < displayText.utf16.count else {
            return 0
        }
        return isParagraphBoundary(in: displayText, atUTF16Index: pageEndDisplayIndex)
            ? layout.bodyParagraphSpacing
            : layout.bodyLineSpacing
    }

    private static func chapterEndGap(
        fontSize: CGFloat,
        layout: ReaderLayoutConfiguration
    ) -> CGFloat {
        let lineHeight = fontSize + layout.bodyLineSpacing
        return max(lineHeight * 3, layout.bodyParagraphSpacing)
    }

    private static func isParagraphBoundary(
        in text: String,
        atUTF16Index index: Int
    ) -> Bool {
        let clampedIndex = min(max(index, 0), text.utf16.count)
        let currentIndex = stringIndex(in: text, atUTF16Offset: clampedIndex)
        let previousIndex = previousCharacterIndex(in: text, before: currentIndex)

        let previousIsNewline = previousIndex.map { isNewline(text[$0]) } ?? false
        let currentIsNewline = currentIndex < text.endIndex && isNewline(text[currentIndex])
        return previousIsNewline || currentIsNewline
    }

    private static func isNewline(_ character: Character) -> Bool {
        character == "\n" || character == "\r"
    }

    private static func stringIndex(
        in text: String,
        atUTF16Offset offset: Int
    ) -> String.Index {
        var candidate = min(max(offset, 0), text.utf16.count)
        while candidate <= text.utf16.count {
            let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: candidate)
            if let index = String.Index(utf16Index, within: text) {
                return index
            }
            candidate += 1
        }
        return text.endIndex
    }

    private static func previousCharacterIndex(
        in text: String,
        before index: String.Index
    ) -> String.Index? {
        guard index > text.startIndex else {
            return nil
        }
        return text.index(before: index)
    }

    private static func pageContainsChapterTitle(_ text: String, chapterTitle: String) -> Bool {
        let expectedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedTitle.isEmpty else {
            return false
        }

        let lines = text.components(separatedBy: .newlines)
        guard let firstContentLine = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        return firstContentLine.trimmingCharacters(in: .whitespacesAndNewlines) == expectedTitle
    }
}

