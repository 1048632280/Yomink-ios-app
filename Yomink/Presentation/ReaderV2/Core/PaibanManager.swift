import CoreText
import UIKit

struct ReaderDivisionPage {
    let attributedText: NSAttributedString
    let displayRange: NSRange
    let usedHeight: CGFloat
    let sourceAttributedText: NSAttributedString

    init(
        attributedText: NSAttributedString,
        displayRange: NSRange,
        usedHeight: CGFloat,
        sourceAttributedText: NSAttributedString? = nil
    ) {
        self.attributedText = attributedText
        self.displayRange = displayRange
        self.usedHeight = usedHeight
        self.sourceAttributedText = sourceAttributedText ?? attributedText
    }
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
                ? Self.usedHeight(
                    for: frame,
                    displayRange: range,
                    attributedText: attributedText,
                    fallback: pageRect.height
                )
                : pageRect.height
            let pageAttributedText = attributedText.attributedSubstring(from: range)
            pages.append(
                ReaderDivisionPage(
                    attributedText: pageAttributedText,
                    displayRange: range,
                    usedHeight: height,
                    sourceAttributedText: attributedText
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
        displayRange: NSRange,
        attributedText: NSAttributedString,
        fallback: CGFloat
    ) -> CGFloat {
        let lines = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(lines)
        guard lineCount > 0,
              displayRange.length > 0 else {
            return max(1, fallback)
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let frameBounds = CTFrameGetPath(frame).boundingBox
        let originsAreRelative = origins.allSatisfy {
            $0.x >= 0
                && $0.x <= frameBounds.width
                && $0.y >= 0
                && $0.y <= frameBounds.height
        }

        var top = -CGFloat.greatestFiniteMagnitude
        var bottom = CGFloat.greatestFiniteMagnitude
        for index in 0..<lineCount {
            let line = unsafeBitCast(
                CFArrayGetValueAtIndex(lines, index),
                to: CTLine.self
            )
            let lineRange = CTLineGetStringRange(line)
            guard lineRange.location != kCFNotFound,
                  lineRange.length > 0,
                  rangesIntersect(lineRange, displayRange) else {
                continue
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let origin = origins[index]
            let drawingOrigin = originsAreRelative
                ? CGPoint(x: frameBounds.minX + origin.x, y: frameBounds.minY + origin.y)
                : origin
            top = max(top, drawingOrigin.y + ascent)
            bottom = min(bottom, drawingOrigin.y - descent)
        }

        guard top.isFinite,
              bottom.isFinite,
              top > bottom else {
            return max(1, fallback)
        }

        let trailingSpacing = trailingParagraphSpacing(
            in: attributedText,
            range: displayRange
        )
        let height = ceil(top - bottom + trailingSpacing + 2)
        return min(max(1, height), max(1, fallback))
    }

    private static func rangesIntersect(
        _ lineRange: CFRange,
        _ displayRange: NSRange
    ) -> Bool {
        let lineStart = lineRange.location
        let lineEnd = lineRange.location + lineRange.length
        let displayStart = displayRange.location
        let displayEnd = displayRange.location + displayRange.length
        return max(lineStart, displayStart) < min(lineEnd, displayEnd)
    }

    private static func trailingParagraphSpacing(
        in attributedText: NSAttributedString,
        range: NSRange
    ) -> CGFloat {
        guard attributedText.length > 0,
              range.length > 0 else {
            return 0
        }
        let endIndex = min(range.location + range.length - 1, attributedText.length - 1)
        let text = attributedText.string as NSString
        let character = text.character(at: endIndex)
        guard character == 10 || character == 13,
              let paragraph = attributedText.attribute(
                  .paragraphStyle,
                  at: endIndex,
                  effectiveRange: nil
              ) as? NSParagraphStyle else {
            return 0
        }
        return ceil(paragraph.paragraphSpacing)
    }
}
