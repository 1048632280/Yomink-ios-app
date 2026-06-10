import CoreText
import UIKit

struct ReaderTextSelectionPageContext {
    enum CaretAffinity {
        case upstream
        case downstream
    }

    let text: String
    let attributedText: NSAttributedString
    let layout: ReaderLayoutConfiguration
    let pageBounds: CGRect
    let contentRect: CGRect

    private let frame: CTFrame
    private let lines: [ReaderTextSelectionLine]
    private let characterBoundaries: [Int]

    init(
        text: String,
        attributedText: NSAttributedString,
        layout: ReaderLayoutConfiguration,
        pageBounds: CGRect
    ) {
        self.text = text
        self.attributedText = attributedText
        self.layout = layout
        self.pageBounds = pageBounds
        let drawingRect = layout.contentRect(in: pageBounds)
        let framePathRect = CGRect(
            origin: .zero,
            size: drawingRect.size
        )
        self.contentRect = CGRect(
            x: drawingRect.minX,
            y: pageBounds.height - drawingRect.maxY,
            width: drawingRect.width,
            height: drawingRect.height
        )

        let path = CGMutablePath()
        path.addRect(framePathRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        self.frame = frame
        self.lines = Self.makeLines(from: frame)
        self.characterBoundaries = Self.makeCharacterBoundaries(in: text)
    }

    var textLength: Int {
        attributedText.length
    }

    func paragraphRange(containingUTF16Index index: Int) -> NSRange? {
        guard textLength > 0 else {
            return nil
        }

        let nsText = text as NSString
        let safeLocation = min(max(index, 0), max(textLength - 1, 0))
        var paragraphStart = 0
        var paragraphContentsEnd = 0
        nsText.getParagraphStart(
            &paragraphStart,
            end: nil,
            contentsEnd: &paragraphContentsEnd,
            for: NSRange(location: safeLocation, length: 0)
        )

        let contentLength = max(0, paragraphContentsEnd - paragraphStart)
        if let range = trimmedRange(NSRange(location: paragraphStart, length: contentLength)) {
            return range
        }
        return characterRange(containingUTF16Index: safeLocation)
    }

    func selectedText(in range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else {
            return ""
        }
        return String(text[swiftRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rangeByMovingStart(of range: NSRange, to index: Int) -> NSRange {
        let end = range.location + range.length
        let minimumStart = 0
        let maximumStart = previousBoundary(before: end) ?? range.location
        let proposed = nearestBoundary(to: index)
        let start = min(max(proposed, minimumStart), maximumStart)
        return NSRange(location: start, length: end - start)
    }

    func rangeByMovingEnd(of range: NSRange, to index: Int) -> NSRange {
        let start = range.location
        let minimumEnd = nextBoundary(after: start) ?? (start + range.length)
        let proposed = nearestBoundary(to: index)
        let end = min(max(proposed, minimumEnd), textLength)
        return NSRange(location: start, length: end - start)
    }

    func characterBoundary(at point: CGPoint) -> Int? {
        guard textLength > 0 else {
            return nil
        }

        if point.y < contentRect.minY {
            return 0
        }
        if point.y > contentRect.maxY {
            return textLength
        }

        let clampedPoint = CGPoint(
            x: min(max(point.x, contentRect.minX), contentRect.maxX),
            y: min(max(point.y, contentRect.minY), contentRect.maxY)
        )
        guard contentRect.insetBy(dx: 0, dy: -10).contains(clampedPoint),
              let line = line(at: clampedPoint) else {
            return nil
        }

        let relativePoint = CGPoint(
            x: clampedPoint.x - contentRect.minX - line.origin.x,
            y: 0
        )
        let rawIndex = CTLineGetStringIndexForPosition(line.line, relativePoint)
        guard rawIndex != kCFNotFound else {
            return nil
        }
        return nearestBoundary(to: rawIndex)
    }

    func selectionRects(for range: NSRange) -> [CGRect] {
        let selectionEnd = range.location + range.length
        guard range.length > 0,
              selectionEnd <= textLength else {
            return []
        }

        return lines.compactMap { line in
            let lineStart = line.range.location
            let lineEnd = line.range.location + line.range.length
            let start = max(range.location, lineStart)
            let end = min(selectionEnd, lineEnd)
            guard start < end else {
                return nil
            }

            let startOffset = CTLineGetOffsetForStringIndex(line.line, start, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line.line, end, nil)
            let minOffset = min(startOffset, endOffset)
            let width = max(2, abs(endOffset - startOffset))
            let lineRect = visualRect(for: line)
            return CGRect(
                x: lineRect.minX + minOffset,
                y: lineRect.minY - 1,
                width: width,
                height: lineRect.height + 2
            ).integral
        }
    }

    func caretPoint(at index: Int, affinity: CaretAffinity) -> CGPoint? {
        guard textLength > 0 else {
            return nil
        }

        let boundary = min(max(nearestBoundary(to: index), 0), textLength)
        let candidate: ReaderTextSelectionLine?
        switch affinity {
        case .upstream:
            candidate = lines.first { line in
                boundary >= line.range.location
                    && boundary <= line.range.location + line.range.length
            } ?? lines.first
        case .downstream:
            candidate = lines.reversed().first { line in
                boundary >= line.range.location
                    && boundary <= line.range.location + line.range.length
            } ?? lines.last
        }

        guard let line = candidate else {
            return nil
        }

        let clamped = min(
            max(boundary, line.range.location),
            line.range.location + line.range.length
        )
        let offset = CTLineGetOffsetForStringIndex(line.line, clamped, nil)
        let lineRect = visualRect(for: line)
        let y = affinity == .upstream ? lineRect.minY : lineRect.maxY
        return CGPoint(x: lineRect.minX + offset, y: y)
    }

    private func line(at point: CGPoint) -> ReaderTextSelectionLine? {
        var fallback: (line: ReaderTextSelectionLine, distance: CGFloat)?
        for line in lines {
            let rect = visualRect(for: line).insetBy(dx: -4, dy: -6)
            if rect.contains(point) {
                return line
            }

            let distance = min(abs(point.y - rect.minY), abs(point.y - rect.maxY))
            if point.x >= contentRect.minX,
               point.x <= contentRect.maxX {
                if let currentFallback = fallback {
                    if distance < currentFallback.distance {
                        fallback = (line, distance)
                    }
                } else {
                    fallback = (line, distance)
                }
            }
        }

        guard let fallback,
              fallback.distance <= 14 else {
            return nil
        }
        return fallback.line
    }

    private func visualRect(for line: ReaderTextSelectionLine) -> CGRect {
        let baselineY = line.origin.y
        let y = contentRect.minY + contentRect.height - baselineY - line.ascent
        return CGRect(
            x: contentRect.minX + line.origin.x,
            y: y,
            width: max(1, line.width),
            height: max(1, line.ascent + line.descent)
        )
    }

    private func trimmedRange(_ range: NSRange) -> NSRange? {
        guard range.length > 0,
              let swiftRange = Range(range, in: text) else {
            return nil
        }

        var start = swiftRange.lowerBound
        var end = swiftRange.upperBound
        while start < end, text[start].isWhitespace {
            start = text.index(after: start)
        }
        while end > start {
            let previous = text.index(before: end)
            if text[previous].isWhitespace {
                end = previous
            } else {
                break
            }
        }

        guard start < end else {
            return nil
        }
        return NSRange(start..<end, in: text)
    }

    private func characterRange(containingUTF16Index index: Int) -> NSRange? {
        guard characterBoundaries.count > 1 else {
            return nil
        }

        var start = nearestBoundary(to: index)
        if start >= textLength {
            start = previousBoundary(before: textLength) ?? 0
        }
        let end = nextBoundary(after: start) ?? textLength
        guard end > start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private func nearestBoundary(to index: Int) -> Int {
        guard characterBoundaries.isEmpty == false else {
            return min(max(index, 0), textLength)
        }

        let clamped = min(max(index, 0), textLength)
        var lowerBound = 0
        var upperBound = characterBoundaries.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if characterBoundaries[middle] < clamped {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        if lowerBound == 0 {
            return characterBoundaries[0]
        }
        if lowerBound >= characterBoundaries.count {
            return characterBoundaries[characterBoundaries.count - 1]
        }

        let previous = characterBoundaries[lowerBound - 1]
        let next = characterBoundaries[lowerBound]
        return clamped - previous <= next - clamped ? previous : next
    }

    private func nextBoundary(after index: Int) -> Int? {
        characterBoundaries.first { $0 > index }
    }

    private func previousBoundary(before index: Int) -> Int? {
        characterBoundaries.reversed().first { $0 < index }
    }

    private static func makeLines(from frame: CTFrame) -> [ReaderTextSelectionLine] {
        let rawLines = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(rawLines)
        guard lineCount > 0 else {
            return []
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        return (0..<lineCount).compactMap { index in
            let line = unsafeBitCast(
                CFArrayGetValueAtIndex(rawLines, index),
                to: CTLine.self
            )
            let cfRange = CTLineGetStringRange(line)
            guard cfRange.location != kCFNotFound,
                  cfRange.length > 0 else {
                return nil
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(
                CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            )
            return ReaderTextSelectionLine(
                line: line,
                range: NSRange(location: cfRange.location, length: cfRange.length),
                origin: origins[index],
                ascent: ascent,
                descent: descent,
                width: width
            )
        }
    }

    private static func makeCharacterBoundaries(in text: String) -> [Int] {
        var result = [0]
        result.reserveCapacity(text.count + 1)
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            result.append(offset)
        }
        return result
    }
}

private struct ReaderTextSelectionLine {
    let line: CTLine
    let range: NSRange
    let origin: CGPoint
    let ascent: CGFloat
    let descent: CGFloat
    let width: CGFloat
}

final class ReaderTextSelectionOverlayView: UIView {
    enum DraggingHandle {
        case start
        case end
    }

    var onCopy: (() -> Void)?
    var onSearch: (() -> Void)?
    var onFilter: (() -> Void)?

    private let startHandle = ReaderTextSelectionHandleView(kind: .start)
    private let endHandle = ReaderTextSelectionHandleView(kind: .end)
    private let menuTargetView = ReaderTextSelectionMenuTargetView()
    private var context: ReaderTextSelectionPageContext?
    private var pageFrame: CGRect = .zero
    private var selectedRange: NSRange?
    private var selectionRects: [CGRect] = []
    private var draggingHandle: DraggingHandle?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        configureHandles()
        configureMenuTarget()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasSelection: Bool {
        selectedRange != nil
    }

    var selectedText: String {
        guard let context,
              let selectedRange else {
            return ""
        }
        return context.selectedText(in: selectedRange)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        menuTargetView.frame = bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard hasSelection else {
            return false
        }
        return startHandle.frame.insetBy(dx: -24, dy: -24).contains(point)
            || endHandle.frame.insetBy(dx: -24, dy: -24).contains(point)
    }

    override func draw(_ rect: CGRect) {
        guard selectionRects.isEmpty == false,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.setFillColor(UIColor.systemBlue.withAlphaComponent(0.28).cgColor)
        for rect in selectionRects {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }

    func showSelection(
        pageFrame: CGRect,
        context: ReaderTextSelectionPageContext,
        range: NSRange
    ) {
        self.pageFrame = pageFrame
        self.context = context
        selectedRange = range
        isHidden = false
        updateSelectionGeometry()
        showMenu(animated: true)
    }

    func clearSelection() {
        UIMenuController.shared.setMenuVisible(false, animated: false)
        selectedRange = nil
        context = nil
        selectionRects = []
        draggingHandle = nil
        startHandle.isHidden = true
        endHandle.isHidden = true
        isHidden = true
        setNeedsDisplay()
    }

    func selectionContains(_ point: CGPoint) -> Bool {
        selectionRects.contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
    }

    func showMenu(animated _: Bool) {
        guard hasSelection,
              let anchorRect = menuAnchorRect() else {
            return
        }

        menuTargetView.becomeFirstResponder()
        let menuController = UIMenuController.shared
        menuController.menuItems = [
            UIMenuItem(
                title: NSLocalizedString("reader.selection.copy", comment: ""),
                action: #selector(ReaderTextSelectionMenuTargetView.copySelection(_:))
            ),
            UIMenuItem(
                title: NSLocalizedString("reader.selection.search", comment: ""),
                action: #selector(ReaderTextSelectionMenuTargetView.searchSelection(_:))
            ),
            UIMenuItem(
                title: NSLocalizedString("reader.selection.filter", comment: ""),
                action: #selector(ReaderTextSelectionMenuTargetView.filterSelection(_:))
            )
        ]
        menuController.showMenu(from: menuTargetView, rect: anchorRect)
    }

    private func configureHandles() {
        [startHandle, endHandle].forEach { handle in
            handle.isHidden = true
            addSubview(handle)
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            handle.addGestureRecognizer(panGesture)
        }
    }

    private func configureMenuTarget() {
        menuTargetView.backgroundColor = .clear
        menuTargetView.isUserInteractionEnabled = false
        menuTargetView.onCopy = { [weak self] in self?.onCopy?() }
        menuTargetView.onSearch = { [weak self] in self?.onSearch?() }
        menuTargetView.onFilter = { [weak self] in self?.onFilter?() }
        addSubview(menuTargetView)
    }

    private func updateSelectionGeometry() {
        guard let context,
              let selectedRange else {
            selectionRects = []
            startHandle.isHidden = true
            endHandle.isHidden = true
            setNeedsDisplay()
            return
        }

        selectionRects = context.selectionRects(for: selectedRange)
            .map { $0.offsetBy(dx: pageFrame.minX, dy: pageFrame.minY) }
        updateHandles()
        setNeedsDisplay()
    }

    private func updateHandles() {
        guard let context,
              let selectedRange,
              let startPoint = context.caretPoint(
                at: selectedRange.location,
                affinity: .upstream
              ),
              let endPoint = context.caretPoint(
                at: selectedRange.location + selectedRange.length,
                affinity: .downstream
              ) else {
            startHandle.isHidden = true
            endHandle.isHidden = true
            return
        }

        let startAnchor = CGPoint(
            x: pageFrame.minX + startPoint.x,
            y: pageFrame.minY + startPoint.y
        )
        let endAnchor = CGPoint(
            x: pageFrame.minX + endPoint.x,
            y: pageFrame.minY + endPoint.y
        )
        position(startHandle, at: startAnchor, kind: .start)
        position(endHandle, at: endAnchor, kind: .end)
        startHandle.isHidden = !bounds.insetBy(dx: -30, dy: -30).intersects(startHandle.frame)
        endHandle.isHidden = !bounds.insetBy(dx: -30, dy: -30).intersects(endHandle.frame)
    }

    private func position(
        _ handle: ReaderTextSelectionHandleView,
        at point: CGPoint,
        kind: ReaderTextSelectionHandleView.Kind
    ) {
        let size = ReaderTextSelectionHandleView.preferredSize
        let originY: CGFloat
        switch kind {
        case .start:
            originY = point.y - size.height + 6
        case .end:
            originY = point.y - 6
        }
        handle.frame = CGRect(
            x: point.x - size.width / 2,
            y: originY,
            width: size.width,
            height: size.height
        )
    }

    private func menuAnchorRect() -> CGRect? {
        let visibleRects = selectionRects
            .map { $0.intersection(bounds) }
            .filter { !$0.isNull && !$0.isEmpty }
        let sourceRects = visibleRects.isEmpty ? selectionRects : visibleRects
        guard var anchor = sourceRects.first else {
            return nil
        }
        for rect in sourceRects.dropFirst() {
            anchor = anchor.union(rect)
        }
        let maxWidth = max(bounds.width - 32, 1)
        anchor.origin.x = max(16, min(anchor.origin.x, bounds.width - 16))
        anchor.size.width = min(anchor.width, maxWidth)
        return anchor
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let context,
              var selectedRange else {
            return
        }

        if gesture.state == .began {
            UIMenuController.shared.setMenuVisible(false, animated: false)
            draggingHandle = gesture.view === startHandle ? .start : .end
        }

        let location = gesture.location(in: self)
        let pagePoint = CGPoint(
            x: location.x - pageFrame.minX,
            y: location.y - pageFrame.minY
        )
        if let boundary = context.characterBoundary(at: pagePoint) {
            switch draggingHandle {
            case .start:
                selectedRange = context.rangeByMovingStart(of: selectedRange, to: boundary)
            case .end:
                selectedRange = context.rangeByMovingEnd(of: selectedRange, to: boundary)
            case .none:
                break
            }
            self.selectedRange = selectedRange
            updateSelectionGeometry()
        }

        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            draggingHandle = nil
            showMenu(animated: true)
        }
    }
}

private final class ReaderTextSelectionHandleView: UIView {
    enum Kind {
        case start
        case end
    }

    static let preferredSize = CGSize(width: 30, height: 38)

    private let kind: Kind

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize))
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let color = UIColor.systemBlue
        context.setFillColor(color.cgColor)
        let stemWidth: CGFloat = 2.5
        let stemX = bounds.midX - stemWidth / 2
        let knobDiameter: CGFloat = 12
        let knobRect: CGRect
        let stemRect: CGRect

        switch kind {
        case .start:
            knobRect = CGRect(
                x: bounds.midX - knobDiameter / 2,
                y: 1,
                width: knobDiameter,
                height: knobDiameter
            )
            stemRect = CGRect(
                x: stemX,
                y: knobRect.maxY - 1,
                width: stemWidth,
                height: bounds.height - knobRect.maxY - 5
            )
        case .end:
            knobRect = CGRect(
                x: bounds.midX - knobDiameter / 2,
                y: bounds.height - knobDiameter - 1,
                width: knobDiameter,
                height: knobDiameter
            )
            stemRect = CGRect(
                x: stemX,
                y: 5,
                width: stemWidth,
                height: knobRect.minY - 4
            )
        }

        context.fill(stemRect)
        context.fillEllipse(in: knobRect)
    }
}

private final class ReaderTextSelectionMenuTargetView: UIView {
    var onCopy: (() -> Void)?
    var onSearch: (() -> Void)?
    var onFilter: (() -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        action == #selector(copySelection(_:))
            || action == #selector(searchSelection(_:))
            || action == #selector(filterSelection(_:))
    }

    @objc func copySelection(_ sender: Any?) {
        onCopy?()
    }

    @objc func searchSelection(_ sender: Any?) {
        onSearch?()
    }

    @objc func filterSelection(_ sender: Any?) {
        onFilter?()
    }
}
