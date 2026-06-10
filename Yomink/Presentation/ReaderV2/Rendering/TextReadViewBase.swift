import CoreText
import UIKit

class TextReadViewBase: UIView {
    private(set) var attributedText = NSAttributedString(string: "")
    private(set) var frameRef: CTFrame?
    private(set) var highlightedRanges: [NSRange] = []
    private(set) var selectedRange: NSRange?
    private(set) var displayRange: NSRange?
    var layout = ReaderLayout.notchedPhone {
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

    func setSelectedRange(_ range: NSRange?) {
        selectedRange = range.flatMap(clampedRange)
        setNeedsDisplay()
    }

    func characterIndex(at point: CGPoint) -> Int? {
        lineInfo(at: point)?.stringIndex
    }

    func closestCharacterIndex(to point: CGPoint) -> Int? {
        if let index = characterIndex(at: point) {
            return index
        }
        guard attributedText.length > 0,
              let nearest = lineInfos().min(by: {
                  abs($0.uiRect.midY - point.y) < abs($1.uiRect.midY - point.y)
              }) else {
            return nil
        }
        let linePoint = CGPoint(
            x: min(max(point.x, nearest.uiRect.minX), nearest.uiRect.maxX) - nearest.drawingOrigin.x,
            y: 0
        )
        return clampedStringIndex(CTLineGetStringIndexForPosition(nearest.line, linePoint))
    }

    func selectionRange(at point: CGPoint) -> NSRange? {
        guard let index = characterIndex(at: point)
            ?? closestCharacterIndex(to: point),
            attributedText.length > 0 else {
            return nil
        }
        return expandedSelectionRange(around: min(index, attributedText.length - 1))
    }

    func selectionHandlePoints(for range: NSRange) -> (start: CGPoint, end: CGPoint)? {
        let rects = textRects(for: range)
        guard let first = rects.first,
              let last = rects.last else {
            return nil
        }
        return (
            start: CGPoint(x: first.minX, y: first.maxY),
            end: CGPoint(x: last.maxX, y: last.maxY)
        )
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

        guard let frameRange = effectiveFrameRange() else {
            frameRef = nil
            return
        }

        let contentRect = contentRectOverride ?? layout.contentRect(in: bounds)
        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        frameRef = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: frameRange.location, length: frameRange.length),
            path,
            nil
        )
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

    private struct LineInfo {
        let line: CTLine
        let uiRect: CGRect
        let drawingOrigin: CGPoint
        let stringIndex: Int
    }

    private func lineInfo(at point: CGPoint) -> LineInfo? {
        guard let info = lineInfos().first(where: {
            $0.uiRect.insetBy(dx: -18, dy: -4).contains(point)
        }) else {
            return nil
        }
        let linePoint = CGPoint(
            x: min(max(point.x, info.uiRect.minX), info.uiRect.maxX) - info.drawingOrigin.x,
            y: 0
        )
        return LineInfo(
            line: info.line,
            uiRect: info.uiRect,
            drawingOrigin: info.drawingOrigin,
            stringIndex: clampedStringIndex(CTLineGetStringIndexForPosition(info.line, linePoint))
                ?? info.stringIndex
        )
    }

    private func lineInfos() -> [LineInfo] {
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
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let origin = origins[index]
            let drawingOrigin = originsAreRelative
                ? CGPoint(x: frameBounds.minX + origin.x, y: frameBounds.minY + origin.y)
                : origin
            let coreTextRect = CGRect(
                x: drawingOrigin.x,
                y: drawingOrigin.y - descent - 1,
                width: max(2, width),
                height: max(1, ascent + descent + 2)
            )
            let uiRect = CGRect(
                x: coreTextRect.minX,
                y: bounds.height - coreTextRect.maxY,
                width: coreTextRect.width,
                height: coreTextRect.height
            ).integral
            return LineInfo(
                line: line,
                uiRect: uiRect,
                drawingOrigin: drawingOrigin,
                stringIndex: lineRange.location
            )
        }
    }

    private func clampedStringIndex(_ index: CFIndex) -> Int? {
        guard attributedText.length > 0,
              index != kCFNotFound else {
            return nil
        }
        return min(max(index, 0), attributedText.length - 1)
    }

    private func expandedSelectionRange(around index: Int) -> NSRange? {
        guard attributedText.length > 0 else {
            return nil
        }
        let text = attributedText.string as NSString
        let seed = text.rangeOfComposedCharacterSequence(at: min(max(index, 0), attributedText.length - 1))
        guard seed.location != NSNotFound,
              seed.length > 0 else {
            return nil
        }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let seedIsWord = Self.characterSet(
            at: seed.location,
            in: text
        ).map { allowed.contains($0) } ?? false
        guard seedIsWord else {
            return seed
        }

        var start = seed.location
        var end = seed.location + seed.length
        while start > 0,
              let scalar = Self.characterSet(at: start - 1, in: text),
              allowed.contains(scalar) {
            start -= 1
        }
        while end < text.length,
              let scalar = Self.characterSet(at: end, in: text),
              allowed.contains(scalar) {
            end += 1
        }
        return NSRange(location: start, length: max(1, end - start))
    }

    private static func characterSet(
        at index: Int,
        in text: NSString
    ) -> UnicodeScalar? {
        guard index >= 0,
              index < text.length else {
            return nil
        }
        return UnicodeScalar(UInt32(text.character(at: index)))
    }
}
