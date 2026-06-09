import CoreText
import UIKit

struct ReaderDivisionPage {
    let attributedText: NSAttributedString
    let displayRange: NSRange
    let usedHeight: CGFloat
}

struct ReaderDivisionResult {
    let pages: [ReaderDivisionPage]

    var pageCount: Int {
        pages.count
    }
}

struct PaibanManager {
    var layout: ReaderLayout
    var theme: ReaderTheme

    init(
        layout: ReaderLayout = .notchedPhone,
        theme: ReaderTheme = .standard
    ) {
        self.layout = layout
        self.theme = theme
    }

    func divideText(
        _ text: String,
        chapterTitle: String,
        chapterIndex _: Int,
        pageSize: CGSize,
        doubleColumn _: Bool = false,
        returnsHeights: Bool = false
    ) -> ReaderDivisionResult {
        let attributedText = attributedText(
            text: normalizedBodyText(text),
            chapterTitle: chapterTitle
        )
        return paginate(
            attributedText,
            pageSize: pageSize,
            returnsHeights: returnsHeights
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
        let titleRange = title.isEmpty
            ? nil
            : NSRange(location: 0, length: (title as NSString).length)
        let bodyStart = titleRange.map { NSMaxRange($0) } ?? 0
        let bodyRange = NSRange(
            location: min(bodyStart, fullRange.length),
            length: max(fullRange.length - bodyStart, 0)
        )

        if let titleRange, titleRange.length > 0 {
            attributed.addAttributes(
                textAttributes(
                    fontSize: layout.fontSize + layout.titleFontSizeOffset,
                    lineSpacing: layout.titleLineSpacing,
                    paragraphSpacing: layout.titleParagraphSpacing,
                    wordSpacing: layout.titleWordSpacing,
                    firstLineIndent: 0,
                    strokeWidth: layout.titleFontWeight
                ),
                range: titleRange
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
            ? NSLocalizedString("reader.emptyChapter", comment: "")
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

        return [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: theme.contentColor,
            .paragraphStyle: paragraph,
            .kern: NSNumber(value: Double(wordSpacing)),
            .strokeWidth: NSNumber(value: Double(strokeWidth))
        ]
    }

    private func paginate(
        _ attributedText: NSAttributedString,
        pageSize: CGSize,
        returnsHeights: Bool
    ) -> ReaderDivisionResult {
        guard attributedText.length > 0 else {
            return ReaderDivisionResult(pages: [])
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: max(pageSize.width, 1),
            height: max(pageSize.height, 1)
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
            guard visible.length > 0 else {
                break
            }

            let range = NSRange(
                location: visible.location,
                length: min(visible.length, attributedText.length - visible.location)
            )
            guard range.length > 0 else {
                break
            }

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

        return ReaderDivisionResult(pages: pages)
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
        return max(1, ceil(top - bottom))
    }
}
