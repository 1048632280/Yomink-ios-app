import CoreText
import UIKit

class TextReadViewBase: UIView {
    private(set) var attributedText = NSAttributedString(string: "")
    private(set) var frameRef: CTFrame?
    private(set) var highlightedRanges: [NSRange] = []
    private(set) var selectedRange: NSRange?
    var layout = ReaderLayout.notchedPhone {
        didSet {
            resetFrame()
            setNeedsDisplay()
        }
    }
    var contentColor = UIColor.label {
        didSet {
            applyContentColor()
        }
    }
    var highlightColor = UIColor.systemYellow.withAlphaComponent(0.28) {
        didSet {
            setNeedsDisplay()
        }
    }
    var selectionColor = UIColor.systemBlue.withAlphaComponent(0.24) {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resetFrame()
    }

    func setAttributedText(_ attributedText: NSAttributedString) {
        self.attributedText = attributedText
        applyContentColor()
        normalizeDecorationRanges()
    }

    func setHighlightedRanges(_ ranges: [NSRange]) {
        highlightedRanges = ranges.compactMap(clampedRange)
        setNeedsDisplay()
    }

    func setSelectedRange(_ range: NSRange?) {
        selectedRange = range.flatMap(clampedRange)
        setNeedsDisplay()
    }

    func textRects(for range: NSRange) -> [CGRect] {
        guard let frameRef,
              let range = clampedRange(range) else {
            return []
        }

        let lines = CTFrameGetLines(frameRef)
        let lineCount = CFArrayGetCount(lines)
        guard lineCount > 0 else {
            return []
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frameRef, CFRange(location: 0, length: 0), &origins)
        let frameBounds = CTFrameGetPath(frameRef).boundingBox
        let originsAreRelative = origins.allSatisfy {
            $0.x >= 0
                && $0.x <= frameBounds.width
                && $0.y >= 0
                && $0.y <= frameBounds.height
        }
        let selectionEnd = range.location + range.length

        return (0..<lineCount).compactMap { index in
            let line = unsafeBitCast(
                CFArrayGetValueAtIndex(lines, index),
                to: CTLine.self
            )
            let lineRange = CTLineGetStringRange(line)
            guard lineRange.location != kCFNotFound,
                  lineRange.length > 0 else {
                return nil
            }

            let lineStart = lineRange.location
            let lineEnd = lineRange.location + lineRange.length
            let start = max(range.location, lineStart)
            let end = min(selectionEnd, lineEnd)
            guard start < end else {
                return nil
            }

            let startOffset = CTLineGetOffsetForStringIndex(line, start, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line, end, nil)
            let minOffset = min(startOffset, endOffset)
            let width = max(2, abs(endOffset - startOffset))

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let origin = origins[index]
            let drawingOrigin = originsAreRelative
                ? CGPoint(x: frameBounds.minX + origin.x, y: frameBounds.minY + origin.y)
                : origin
            let coreTextRect = CGRect(
                x: drawingOrigin.x + minOffset,
                y: drawingOrigin.y - descent - 1,
                width: width,
                height: max(1, ascent + descent + 2)
            )
            return CGRect(
                x: coreTextRect.minX,
                y: bounds.height - coreTextRect.maxY,
                width: coreTextRect.width,
                height: coreTextRect.height
            ).integral
        }
    }

    func drawTextBackgrounds(in context: CGContext) {
        drawBackgroundRanges(
            highlightedRanges,
            color: highlightColor,
            cornerRadius: 2,
            context: context
        )
        if let selectedRange {
            drawBackgroundRanges(
                [selectedRange],
                color: selectionColor,
                cornerRadius: 2,
                context: context
            )
        }
    }

    private func applyContentColor() {
        let mutable = NSMutableAttributedString(attributedString: attributedText)
        if mutable.length > 0 {
            mutable.addAttribute(
                .foregroundColor,
                value: contentColor,
                range: NSRange(location: 0, length: mutable.length)
            )
        }
        attributedText = mutable
        resetFrame()
        setNeedsDisplay()
    }

    private func normalizeDecorationRanges() {
        highlightedRanges = highlightedRanges.compactMap(clampedRange)
        selectedRange = selectedRange.flatMap(clampedRange)
    }

    private func clampedRange(_ range: NSRange) -> NSRange? {
        guard attributedText.length > 0,
              range.length > 0 else {
            return nil
        }

        let start = min(max(range.location, 0), attributedText.length)
        let end = min(max(range.location + range.length, start), attributedText.length)
        guard end > start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private func drawBackgroundRanges(
        _ ranges: [NSRange],
        color: UIColor,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        guard ranges.isEmpty == false else {
            return
        }

        context.saveGState()
        color.setFill()
        for range in ranges {
            for rect in textRects(for: range) where rect.intersects(bounds) {
                UIBezierPath(
                    roundedRect: rect.intersection(bounds),
                    cornerRadius: cornerRadius
                ).fill()
            }
        }
        context.restoreGState()
    }

    private func resetFrame() {
        guard attributedText.length > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            frameRef = nil
            return
        }

        let contentRect = layout.contentRect(in: bounds)
        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        frameRef = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
    }
}
