import CoreText
import UIKit

class TextReadViewBase: UIView {
    private struct TextLineInfo {
        let line: CTLine
        let stringRange: NSRange
        let drawingOrigin: CGPoint
        let viewRect: CGRect
    }

    private(set) var attributedText = NSAttributedString(string: "")
    private(set) var frameRef: CTFrame?
    private(set) var highlightedRanges: [NSRange] = []
    private(set) var displayRange: NSRange?
    private var frameBuildBounds = CGRect.null
    private var frameBuildContentRect = CGRect.null
    var layout = ReaderLayout.notchedPhone {
        didSet {
            resetFrame()
            setNeedsDisplay()
        }
    }
    var usesBoundsAsContentRect = false {
        didSet {
            resetFrame()
            setNeedsDisplay()
        }
    }
    var contentRectOverride: CGRect? {
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
        setNeedsDisplay()
    }

    func setAttributedText(
        _ attributedText: NSAttributedString,
        displayRange: NSRange? = nil
    ) {
        self.attributedText = attributedText
        self.displayRange = clampedFrameRange(displayRange)
        applyContentColor()
        normalizeDecorationRanges()
    }

    func setHighlightedRanges(_ ranges: [NSRange]) {
        highlightedRanges = ranges.compactMap(clampedRange)
        setNeedsDisplay()
    }

    var selectableTextRange: NSRange? {
        effectiveFrameRange()
    }

    var activeContentRect: CGRect {
        if usesBoundsAsContentRect {
            return bounds
        }
        contentRectOverride ?? layout.contentRect(in: bounds)
    }

    func characterIndex(at point: CGPoint) -> Int? {
        guard let insertionIndex = insertionIndex(at: point),
              let selectableRange = selectableTextRange else {
            return nil
        }

        let rangeEnd = selectableRange.location + selectableRange.length
        guard rangeEnd > selectableRange.location else {
            return nil
        }

        return min(max(insertionIndex, selectableRange.location), rangeEnd - 1)
    }

    func insertionIndex(at point: CGPoint) -> Int? {
        guard let selectableRange = selectableTextRange,
              activeContentRect.insetBy(dx: -8, dy: -8).contains(point) else {
            return nil
        }

        let selectableEnd = selectableRange.location + selectableRange.length
        for lineInfo in textLineInfos() {
            let hitRect = lineInfo.viewRect.insetBy(
                dx: -10,
                dy: -max(6, layout.lineSpacing / 2)
            )
            guard hitRect.contains(point) else {
                continue
            }

            let lineStart = max(lineInfo.stringRange.location, selectableRange.location)
            let lineEnd = min(
                lineInfo.stringRange.location + lineInfo.stringRange.length,
                selectableEnd
            )
            guard lineStart < lineEnd else {
                continue
            }

            let lineStartOffset = CTLineGetOffsetForStringIndex(lineInfo.line, lineStart, nil)
            let lineEndOffset = CTLineGetOffsetForStringIndex(lineInfo.line, lineEnd, nil)
            let minLineX = lineInfo.drawingOrigin.x + min(lineStartOffset, lineEndOffset)
            let maxLineX = lineInfo.drawingOrigin.x + max(lineStartOffset, lineEndOffset)
            guard point.x >= minLineX - 8,
                  point.x <= maxLineX + 8 else {
                continue
            }

            let linePosition = CGPoint(
                x: point.x - lineInfo.drawingOrigin.x,
                y: 0
            )
            let rawIndex = CTLineGetStringIndexForPosition(lineInfo.line, linePosition)
            guard rawIndex != kCFNotFound else {
                return nil
            }
            return min(max(rawIndex, lineStart), lineEnd)
        }

        return nil
    }

    func paragraphRange(containing index: Int) -> NSRange? {
        guard let selectableRange = selectableTextRange,
              selectableRange.length > 0 else {
            return nil
        }

        let selectableEnd = selectableRange.location + selectableRange.length
        let characterIndex = min(max(index, selectableRange.location), selectableEnd - 1)
        let paragraphRange = (attributedText.string as NSString).paragraphRange(
            for: NSRange(location: characterIndex, length: 0)
        )
        let start = max(paragraphRange.location, selectableRange.location)
        let end = min(paragraphRange.location + paragraphRange.length, selectableEnd)
        guard end > start else {
            return nil
        }
        return trimmedVisibleRange(NSRange(location: start, length: end - start))
    }

    func normalizedSelectionRange(
        start: Int,
        end: Int
    ) -> NSRange? {
        guard let selectableRange = selectableTextRange,
              selectableRange.length > 0 else {
            return nil
        }

        let selectableEnd = selectableRange.location + selectableRange.length
        var normalizedStart = min(max(start, selectableRange.location), selectableEnd)
        var normalizedEnd = min(max(end, selectableRange.location), selectableEnd)
        normalizedStart = composedBoundary(atOrBefore: normalizedStart)
        normalizedEnd = composedBoundary(atOrAfter: normalizedEnd)

        if normalizedStart >= normalizedEnd {
            if normalizedStart >= selectableEnd {
                normalizedStart = composedBoundary(before: selectableEnd)
                normalizedEnd = selectableEnd
            } else {
                normalizedEnd = composedBoundary(after: normalizedStart)
            }
        }

        normalizedStart = min(max(normalizedStart, selectableRange.location), selectableEnd)
        normalizedEnd = min(max(normalizedEnd, selectableRange.location), selectableEnd)
        guard normalizedEnd > normalizedStart else {
            return nil
        }

        return NSRange(
            location: normalizedStart,
            length: normalizedEnd - normalizedStart
        )
    }

    func trimmedVisibleRange(_ range: NSRange) -> NSRange? {
        guard let range = clampedRange(range) else {
            return nil
        }

        let text = attributedText.string
        guard let swiftRange = Range(range, in: text) else {
            return range
        }

        var start = swiftRange.lowerBound
        var end = swiftRange.upperBound
        while start < end,
              text[start].unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) {
            start = text.index(after: start)
        }
        while end > start {
            let previous = text.index(before: end)
            guard text[previous].unicodeScalars.allSatisfy({ $0.properties.isWhitespace }) else {
                break
            }
            end = previous
        }
        guard start < end else {
            return nil
        }
        return NSRange(start..<end, in: text)
    }

    func selectedString(in range: NSRange, trimsWhitespace: Bool = true) -> String {
        let targetRange = trimsWhitespace
            ? trimmedVisibleRange(range)
            : clampedRange(range)
        guard let targetRange,
              let swiftRange = Range(targetRange, in: attributedText.string) else {
            return ""
        }
        return String(attributedText.string[swiftRange])
    }

    func textRects(for range: NSRange) -> [CGRect] {
        ensureFrameForCurrentLayout()
        guard frameRef != nil,
              let range = clampedRange(range) else {
            return []
        }

        let rangeEnd = range.location + range.length

        return textLineInfos().compactMap { lineInfo in
            let lineStart = lineInfo.stringRange.location
            let lineEnd = lineInfo.stringRange.location + lineInfo.stringRange.length
            let start = max(range.location, lineStart)
            let end = min(rangeEnd, lineEnd)
            guard start < end else {
                return nil
            }

            let startOffset = CTLineGetOffsetForStringIndex(lineInfo.line, start, nil)
            let endOffset = CTLineGetOffsetForStringIndex(lineInfo.line, end, nil)
            let minOffset = min(startOffset, endOffset)
            let width = max(2, abs(endOffset - startOffset))

            let coreTextRect = CGRect(
                x: lineInfo.drawingOrigin.x + minOffset,
                y: bounds.height - lineInfo.viewRect.maxY,
                width: width,
                height: lineInfo.viewRect.height
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

    private func textLineInfos() -> [TextLineInfo] {
        guard let frameRef else {
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

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

            let origin = origins[index]
            let drawingOrigin = originsAreRelative
                ? CGPoint(x: frameBounds.minX + origin.x, y: frameBounds.minY + origin.y)
                : origin
            let coreTextRect = CGRect(
                x: drawingOrigin.x,
                y: drawingOrigin.y - descent - 1,
                width: activeContentRect.width,
                height: max(1, ascent + descent + 2)
            )
            let viewRect = CGRect(
                x: coreTextRect.minX,
                y: bounds.height - coreTextRect.maxY,
                width: coreTextRect.width,
                height: coreTextRect.height
            ).integral
            return TextLineInfo(
                line: line,
                stringRange: NSRange(location: lineRange.location, length: lineRange.length),
                drawingOrigin: drawingOrigin,
                viewRect: viewRect
            )
        }
    }

    private func resetFrame() {
        guard attributedText.length > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            frameRef = nil
            frameBuildBounds = .null
            frameBuildContentRect = .null
            return
        }

        guard let frameRange = effectiveFrameRange() else {
            frameRef = nil
            frameBuildBounds = .null
            frameBuildContentRect = .null
            return
        }

        let contentRect = activeContentRect
        guard contentRect.width > 0,
              contentRect.height > 0 else {
            frameRef = nil
            frameBuildBounds = .null
            frameBuildContentRect = .null
            return
        }
        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        frameRef = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: frameRange.location, length: frameRange.length),
            path,
            nil
        )
        frameBuildBounds = bounds
        frameBuildContentRect = contentRect
    }

    func ensureFrameForCurrentLayout() {
        let contentRect = activeContentRect
        guard frameRef == nil
            || frameBuildBounds != bounds
            || frameBuildContentRect != contentRect else {
            return
        }
        resetFrame()
    }

    private func effectiveFrameRange() -> NSRange? {
        if let displayRange = clampedFrameRange(displayRange) {
            return displayRange
        }
        return attributedText.length > 0
            ? NSRange(location: 0, length: attributedText.length)
            : nil
    }

    private func clampedFrameRange(_ range: NSRange?) -> NSRange? {
        guard attributedText.length > 0,
              let range,
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

    private func composedBoundary(atOrBefore index: Int) -> Int {
        guard attributedText.length > 0 else {
            return 0
        }

        let clamped = min(max(index, 0), attributedText.length)
        guard clamped < attributedText.length else {
            return attributedText.length
        }
        let composed = (attributedText.string as NSString).rangeOfComposedCharacterSequence(at: clamped)
        return composed.location
    }

    private func composedBoundary(atOrAfter index: Int) -> Int {
        guard attributedText.length > 0 else {
            return 0
        }

        let clamped = min(max(index, 0), attributedText.length)
        guard clamped < attributedText.length else {
            return attributedText.length
        }
        let composed = (attributedText.string as NSString).rangeOfComposedCharacterSequence(at: clamped)
        return composed.location == clamped
            ? clamped
            : composed.location + composed.length
    }

    private func composedBoundary(before index: Int) -> Int {
        let clamped = min(max(index, 0), attributedText.length)
        guard clamped > 0 else {
            return 0
        }
        let composed = (attributedText.string as NSString).rangeOfComposedCharacterSequence(at: clamped - 1)
        return composed.location
    }

    private func composedBoundary(after index: Int) -> Int {
        let clamped = min(max(index, 0), attributedText.length)
        guard clamped < attributedText.length else {
            return attributedText.length
        }
        let composed = (attributedText.string as NSString).rangeOfComposedCharacterSequence(at: clamped)
        return composed.location + composed.length
    }

}
