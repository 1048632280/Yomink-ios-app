import CoreText
import UIKit

struct ReaderDivisionPage: @unchecked Sendable {
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

struct ReaderDivisionResult: @unchecked Sendable {
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
        let title = chapterTitle.trimmingUnicodeWhitespace()
        let attributedText = attributedText(
            text: normalizedBodyText(text),
            chapterTitle: title
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
        let title = chapterTitle.trimmingUnicodeWhitespace()
        let body = Self.normalizedBodyForDisplay(text, chapterTitle: title)
        let fullText: String
        if title.isEmpty {
            fullText = body
        } else if body.isEmpty {
            fullText = title
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
                    fontWeight: layout.titleFontWeight
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
                    fontWeight: layout.fontWeight
                ),
                range: bodyRange
            )
        }

        return attributed
    }

    private func normalizedBodyText(_ text: String) -> String {
        let trimmed = text.trimmingUnicodeWhitespace()
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
        fontWeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.firstLineHeadIndent = firstLineIndent

        return [
            .font: fontManager.font(size: fontSize, weightValue: fontWeight),
            .foregroundColor: theme.contentColor,
            .paragraphStyle: paragraph,
            .kern: NSNumber(value: Double(wordSpacing))
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

            let pageAttributedText = Self.pageAttributedText(
                from: attributedText,
                range: range
            )
            let height = returnsHeights
                ? Self.suggestedHeight(
                    for: pageAttributedText,
                    fittingWidth: pageRect.width,
                    fallback: pageRect.height
                ) + Self.trailingSpacing(
                    after: range,
                    in: attributedText.string,
                    layout: layout
                )
                : pageRect.height
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

    private static func normalizedBodyForDisplay(
        _ text: String,
        chapterTitle: String
    ) -> String {
        let normalizedLines = text
            .trimmingUnicodeWhitespace()
            .components(separatedBy: "\n")
            .map { line in
                line.trimmingUnicodeWhitespace()
            }
        let body = normalizedLines.joined(separator: "\n")
        guard let firstLine = normalizedLines.first,
              normalizedTitleLine(firstLine) == normalizedTitleLine(chapterTitle) else {
            return body
        }
        return normalizedLines
            .dropFirst()
            .joined(separator: "\n")
            .trimmingUnicodeWhitespace()
    }

    private static func normalizedTitleLine(_ text: String) -> String {
        text.unicodeScalars
            .filter { !$0.properties.isWhitespace }
            .map(String.init)
            .joined()
    }

    private static func pageAttributedText(
        from attributedText: NSAttributedString,
        range: NSRange
    ) -> NSAttributedString {
        let pageAttributedText = NSMutableAttributedString(
            attributedString: attributedText.attributedSubstring(from: range)
        )
        guard range.location > 0,
              pageAttributedText.length > 0,
              !isNewParagraphStart(at: range.location, in: attributedText.string) else {
            return pageAttributedText
        }

        let paragraphRange = (pageAttributedText.string as NSString)
            .paragraphRange(for: NSRange(location: 0, length: 0))
        guard paragraphRange.length > 0,
              let paragraphStyle = pageAttributedText.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
              ) as? NSParagraphStyle else {
            return pageAttributedText
        }

        let adjustedStyle = paragraphStyle.mutableCopy() as? NSMutableParagraphStyle
        adjustedStyle?.firstLineHeadIndent = 0
        if let adjustedStyle {
            pageAttributedText.addAttribute(
                .paragraphStyle,
                value: adjustedStyle,
                range: paragraphRange
            )
        }
        return pageAttributedText
    }

    private static func isNewParagraphStart(
        at location: Int,
        in text: String
    ) -> Bool {
        guard location > 0 else {
            return true
        }
        let nsText = text as NSString
        guard location <= nsText.length else {
            return false
        }
        let previous = nsText.substring(with: NSRange(location: location - 1, length: 1))
        return previous.rangeOfCharacter(from: .newlines) != nil
    }

    private static func trailingSpacing(
        after range: NSRange,
        in text: String,
        layout: ReaderLayout
    ) -> CGFloat {
        let end = range.location + range.length
        let nsText = text as NSString
        guard end < nsText.length else {
            return chapterBreakSpacing(layout: layout)
        }
        return isNewParagraphStart(at: end, in: text)
            ? max(0, layout.paragraphSpacing)
            : max(0, layout.lineSpacing)
    }

    private static func chapterBreakSpacing(layout: ReaderLayout) -> CGFloat {
        let lineHeight = layout.fontSize + max(0, layout.lineSpacing)
        return max(lineHeight * 6, layout.paragraphSpacing)
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

    private static func suggestedHeight(
        for attributedText: NSAttributedString,
        range: NSRange? = nil,
        fittingWidth: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        guard attributedText.length > 0 else {
            return max(1, fallback)
        }
        let frameRange: CFRange
        if let range {
            let start = min(max(range.location, 0), attributedText.length)
            let end = min(max(range.location + range.length, start), attributedText.length)
            frameRange = CFRange(location: start, length: max(end - start, 0))
        } else {
            frameRange = CFRange(location: 0, length: attributedText.length)
        }
        guard frameRange.length > 0 else {
            return max(1, fallback)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let constraint = CGSize(
            width: max(1, fittingWidth),
            height: CGFloat.greatestFiniteMagnitude
        )
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            frameRange,
            nil,
            constraint,
            nil
        )
        let suggestedHeight = size.height.isFinite ? size.height : fallback
        let frameHeight = measuredLineHeight(
            framesetter: framesetter,
            frameRange: frameRange,
            fittingWidth: fittingWidth,
            fallback: fallback
        )
        let measuredHeight = max(suggestedHeight, frameHeight)
        let bufferedHeight = ceil(measuredHeight) + 8
        return max(
            1,
            Self.heightCoveringVisibleRange(
                framesetter: framesetter,
                frameRange: frameRange,
                fittingWidth: fittingWidth,
                initialHeight: bufferedHeight,
                fallback: fallback
            )
        )
    }

    private static func heightCoveringVisibleRange(
        framesetter: CTFramesetter,
        frameRange: CFRange,
        fittingWidth: CGFloat,
        initialHeight: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        let targetEnd = frameRange.location + frameRange.length
        let maxHeight = max(initialHeight, fallback)
        let step = max(8, fallback / 24)
        var height = max(1, initialHeight)

        while height <= maxHeight {
            let path = CGMutablePath()
            path.addRect(
                CGRect(
                    x: 0,
                    y: 0,
                    width: max(1, fittingWidth),
                    height: max(1, height)
                )
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                frameRange,
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.location <= frameRange.location,
               visible.location + visible.length >= targetEnd {
                return ceil(height) + 2
            }

            let nextHeight = min(maxHeight, height + step)
            guard nextHeight > height else {
                break
            }
            height = nextHeight
        }

        return ceil(maxHeight) + 2
    }

    private static func measuredLineHeight(
        framesetter: CTFramesetter,
        frameRange: CFRange,
        fittingWidth: CGFloat,
        fallback: CGFloat
    ) -> CGFloat {
        let pathHeight = max(fallback * 2, 1_000)
        let path = CGMutablePath()
        path.addRect(
            CGRect(
                x: 0,
                y: 0,
                width: max(1, fittingWidth),
                height: pathHeight
            )
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            frameRange,
            path,
            nil
        )
        let lines = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(lines)
        guard lineCount > 0 else {
            return fallback
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for index in 0..<lineCount {
            let line = unsafeBitCast(
                CFArrayGetValueAtIndex(lines, index),
                to: CTLine.self
            )
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let baselineY = origins[index].y
            minY = min(minY, baselineY - descent)
            maxY = max(maxY, baselineY + ascent + leading)
        }
        guard minY.isFinite,
              maxY.isFinite,
              maxY >= minY else {
            return fallback
        }
        return max(1, maxY - minY)
    }

}

private extension String {
    func trimmingUnicodeWhitespace() -> String {
        var start = startIndex
        var end = endIndex
        while start < end,
              self[start].unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) {
            start = index(after: start)
        }
        while end > start {
            let previous = index(before: end)
            guard self[previous].unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else {
                break
            }
            end = previous
        }
        return String(self[start..<end])
    }
}
