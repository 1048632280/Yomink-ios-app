import CoreText
import UIKit

struct ReaderDivisionPage {
    let attributedText: NSAttributedString
    let displayRange: NSRange
    let usedHeight: CGFloat
}

struct ReaderDivisionResult {
    let pages: [ReaderDivisionPage]
    let requestedDoubleColumn: Bool
    let usesDoubleColumn: Bool
    let pageSize: CGSize

    var pageCount: Int {
        pages.count
    }

    var pageHeights: [CGFloat] {
        pages.map(\.usedHeight)
    }

    init(
        pages: [ReaderDivisionPage],
        requestedDoubleColumn: Bool = false,
        usesDoubleColumn: Bool = false,
        pageSize: CGSize = .zero
    ) {
        self.pages = pages
        self.requestedDoubleColumn = requestedDoubleColumn
        self.usesDoubleColumn = usesDoubleColumn
        self.pageSize = pageSize
    }
}

struct PaibanManager {
    var layout: ReaderLayout
    var theme: ReaderTheme
    var fontManager: ReaderFontManager

    init(
        layout: ReaderLayout = .notchedPhone,
        theme: ReaderTheme = .standard,
        fontManager: ReaderFontManager = ReaderFontManager()
    ) {
        self.layout = layout
        self.theme = theme
        self.fontManager = fontManager
    }

    func divideText(
        _ text: String,
        chapterTitle: String,
        chapterIndex _: Int,
        pageSize: CGSize,
        doubleColumn: Bool = false,
        returnsHeights: Bool = false
    ) -> ReaderDivisionResult {
        let attributedText = attributedText(
            text: normalizedBodyText(text),
            chapterTitle: chapterTitle
        )
        return paginate(
            attributedText,
            pageSize: pageSize,
            requestedDoubleColumn: doubleColumn,
            returnsHeights: returnsHeights
        )
    }

    func pageIndex(
        pageCount: Int,
        pageIndex: Int,
        progress: Double,
        usesPageIndex: Bool
    ) -> Int {
        ReaderPageCalculator.pageIndex(
            pageCount: pageCount,
            pageIndex: pageIndex,
            progress: progress,
            usesPageIndex: usesPageIndex
        )
    }

    func pageProgress(
        pageCount: Int,
        pageIndex: Int,
        progress: Double,
        usesPageIndex: Bool
    ) -> Double {
        ReaderPageCalculator.pageProgress(
            pageCount: pageCount,
            pageIndex: pageIndex,
            progress: progress,
            usesPageIndex: usesPageIndex
        )
    }

    func attributedText(
        text: String,
        chapterTitle: String
    ) -> NSAttributedString {
        let title = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText: String
        if title.isEmpty {
            fullText = body
        } else {
            fullText = "\(title)\n\(body)"
        }

        let attributed = NSMutableAttributedString(string: fullText)
        guard attributed.length > 0 else {
            return attributed
        }

        let nsText = fullText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let titleTextRange = title.isEmpty
            ? nil
            : NSRange(location: 0, length: (title as NSString).length)
        let titleAttributeRange = titleTextRange.map {
            NSRange(
                location: $0.location,
                length: min(fullRange.length, $0.length + (body.isEmpty ? 0 : 1))
            )
        }
        let bodyStart = titleAttributeRange.map { NSMaxRange($0) } ?? 0
        let bodyRange = NSRange(
            location: min(bodyStart, fullRange.length),
            length: max(fullRange.length - bodyStart, 0)
        )

        if let titleAttributeRange, titleAttributeRange.length > 0 {
            attributed.addAttributes(
                textAttributes(
                    fontSize: layout.fontSize + layout.titleFontSizeOffset,
                    lineSpacing: layout.titleLineSpacing,
                    paragraphSpacing: layout.titleParagraphSpacing,
                    wordSpacing: layout.titleWordSpacing,
                    firstLineIndent: 0,
                    strokeWidth: layout.titleFontWeight
                ),
                range: titleAttributeRange
            )
        }
        if bodyRange.length > 0 {
            attributed.addAttributes(
                textAttributes(
                    fontSize: layout.fontSize,
                    lineSpacing: layout.lineSpacing,
                    paragraphSpacing: layout.paragraphSpacing,
                    wordSpacing: layout.wordSpacing,
                    firstLineIndent: layout.fontSize * layout.headIndent,
                    strokeWidth: layout.fontWeight
                ),
                range: bodyRange
            )
        }

        return attributed
    }

    private func normalizedBodyText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty
            ? NSLocalizedString(
                "reader.emptyChapter",
                tableName: nil,
                bundle: .main,
                value: "当前章节没有可显示的内容。",
                comment: ""
            )
            : trimmed
        return body.replacingOccurrences(
            of: #"\s*[\r\n]+\s*"#,
            with: "\n",
            options: .regularExpression
        )
    }

    private func textAttributes(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        wordSpacing: CGFloat,
        firstLineIndent: CGFloat,
        strokeWidth: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.firstLineHeadIndent = firstLineIndent
        let normalizedStrokeWidth = ReaderFontManager.clampedStrokeWidth(strokeWidth)

        return [
            .font: fontManager.font(size: fontSize),
            .foregroundColor: theme.contentColor,
            .paragraphStyle: paragraph,
            .kern: NSNumber(value: Double(wordSpacing)),
            .strokeWidth: NSNumber(value: Double(normalizedStrokeWidth))
        ]
    }

    private func paginate(
        _ attributedText: NSAttributedString,
        pageSize: CGSize,
        requestedDoubleColumn: Bool,
        returnsHeights: Bool
    ) -> ReaderDivisionResult {
        let pageSize = Self.normalizedPageSize(pageSize)
        guard attributedText.length > 0 else {
            return ReaderDivisionResult(
                pages: [],
                requestedDoubleColumn: requestedDoubleColumn,
                usesDoubleColumn: false,
                pageSize: pageSize
            )
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: pageSize.width,
            height: pageSize.height
        )
        let path = CGMutablePath()
        path.addRect(pageRect)

        var pages: [ReaderDivisionPage] = []
        var location = 0
        while location < attributedText.length {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: attributedText.length - location),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            let range = Self.visibleRange(
                visible,
                fallbackLocation: location,
                textLength: attributedText.length,
                fullText: attributedText.string
            )

            let height = returnsHeights
                ? Self.usedHeight(for: frame, fallback: pageRect.height)
                : pageRect.height
            pages.append(
                ReaderDivisionPage(
                    attributedText: attributedText.attributedSubstring(from: range),
                    displayRange: range,
                    usedHeight: height
                )
            )
            location = range.location + range.length
        }

        return ReaderDivisionResult(
            pages: pages,
            requestedDoubleColumn: requestedDoubleColumn,
            usesDoubleColumn: false,
            pageSize: pageSize
        )
    }

    private static func normalizedPageSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width.isFinite ? size.width : 0, 1),
            height: max(size.height.isFinite ? size.height : 0, 1)
        )
    }

    private static func visibleRange(
        _ visible: CFRange,
        fallbackLocation: Int,
        textLength: Int,
        fullText: String
    ) -> NSRange {
        let location = min(max(visible.location, fallbackLocation), textLength)
        let visibleEnd = min(max(visible.location + visible.length, location), textLength)
        let visibleLength = max(visibleEnd - location, 0)
        if visibleLength > 0 {
            return NSRange(location: location, length: visibleLength)
        }

        guard fallbackLocation < textLength else {
            return NSRange(location: textLength, length: 0)
        }
        let nsText = fullText as NSString
        let composed = nsText.rangeOfComposedCharacterSequence(at: fallbackLocation)
        return NSRange(
            location: fallbackLocation,
            length: min(max(composed.length, 1), textLength - fallbackLocation)
        )
    }

    private static func usedHeight(
        for frame: CTFrame,
        fallback: CGFloat
    ) -> CGFloat {
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
        CTLineGetTypographicBounds(firstLine, &firstAscent, &firstDescent, &firstLeading)

        var lastAscent: CGFloat = 0
        var lastDescent: CGFloat = 0
        var lastLeading: CGFloat = 0
        CTLineGetTypographicBounds(lastLine, &lastAscent, &lastDescent, &lastLeading)

        let top = origins[0].y + firstAscent
        let bottom = origins[lineCount - 1].y - lastDescent
        return min(max(1, ceil(top - bottom)), max(1, fallback))
    }
}
