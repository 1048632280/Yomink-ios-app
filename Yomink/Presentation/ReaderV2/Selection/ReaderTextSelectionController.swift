import UIKit

@MainActor
final class ReaderTextSelectionController: NSObject, UIGestureRecognizerDelegate {
    typealias TargetProvider = (CGPoint) -> TextReadView?

    private weak var hostView: UIView?
    private weak var menuResponder: UIResponder?
    private let targetProvider: TargetProvider
    private let isSelectionEnabled: () -> Bool
    private let menuItems: [UIMenuItem]

    private var longPressGesture: UILongPressGestureRecognizer?
    private var externalDragGesture: ReaderImmediatePanGestureRecognizer?
    private weak var selectedTextView: TextReadView?
    private var overlayView: ReaderTextSelectionOverlayView?
    private var magnifierView: ReaderSelectionMagnifierView?
    private var selectedRange: NSRange?
    private var isDraggingHandle = false
    private var restoresMenuAfterBlankLongPress = false

    var hasSelection: Bool {
        selectedRange != nil
    }

    init(
        hostView: UIView,
        menuResponder: UIResponder,
        targetProvider: @escaping TargetProvider,
        isSelectionEnabled: @escaping () -> Bool,
        menuItems: [UIMenuItem]
    ) {
        self.hostView = hostView
        self.menuResponder = menuResponder
        self.targetProvider = targetProvider
        self.isSelectionEnabled = isSelectionEnabled
        self.menuItems = menuItems
        super.init()
        configureLongPressGesture(on: hostView)
        configureExternalDragGesture(on: hostView)
    }

    func clearSelection(hidesMenu: Bool = true) {
        selectedRange = nil
        selectedTextView = nil
        overlayView?.removeFromSuperview()
        overlayView = nil
        hideMagnifier()
        externalDragGesture?.isEnabled = false
        isDraggingHandle = false
        restoresMenuAfterBlankLongPress = false
        if hidesMenu {
            UIMenuController.shared.setMenuVisible(false, animated: false)
        }
    }

    func selectedTextForCopy() -> String {
        trimmedSelectedText()
    }

    func selectedTextForSearch() -> String {
        trimmedSelectedText()
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    func selectedTextForFilter() -> String {
        trimmedSelectedText()
    }

    func refreshSelectionDisplay() {
        guard let selectedTextView,
              let selectedRange else {
            clearSelection()
            return
        }
        updateOverlay(on: selectedTextView, range: selectedRange)
    }

    private func configureLongPressGesture(on hostView: UIView) {
        let gesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(longPressRecognized(_:))
        )
        gesture.minimumPressDuration = 0.42
        gesture.cancelsTouchesInView = false
        hostView.addGestureRecognizer(gesture)
        longPressGesture = gesture
    }

    private func configureExternalDragGesture(on hostView: UIView) {
        let gesture = ReaderImmediatePanGestureRecognizer(
            target: self,
            action: #selector(externalDragRecognized(_:))
        )
        gesture.delegate = self
        gesture.isEnabled = false
        hostView.addGestureRecognizer(gesture)
        externalDragGesture = gesture
    }

    @objc private func longPressRecognized(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            restoresMenuAfterBlankLongPress = false
            guard isSelectionEnabled() else {
                clearSelection()
                return
            }
            guard let hostView else {
                return
            }

            let location = recognizer.location(in: hostView)
            guard let textView = targetProvider(location) else {
                hideMenuForBlankLongPressIfNeeded()
                return
            }
            let textLocation = textView.convert(location, from: hostView)
            guard let characterIndex = textView.characterIndex(at: textLocation) else {
                hideMenuForBlankLongPressIfNeeded()
                return
            }
            guard let paragraphRange = textView.paragraphRange(containing: characterIndex) else {
                return
            }

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            select(range: paragraphRange, in: textView)
        case .ended, .cancelled, .failed:
            if restoresMenuAfterBlankLongPress {
                restoresMenuAfterBlankLongPress = false
                if hasSelection {
                    showMenu(animated: true)
                }
            }
        default:
            break
        }
    }

    private func select(range: NSRange, in textView: TextReadView) {
        guard let normalizedRange = textView.normalizedSelectionRange(
            start: range.location,
            end: range.location + range.length
        ) else {
            return
        }

        selectedTextView = textView
        selectedRange = normalizedRange
        externalDragGesture?.isEnabled = true
        installOverlayIfNeeded(on: textView)
        updateOverlay(on: textView, range: normalizedRange)
        showMenu(animated: true)
    }

    private func installOverlayIfNeeded(on textView: TextReadView) {
        if overlayView?.superview === textView {
            return
        }

        overlayView?.removeFromSuperview()
        let overlay = ReaderTextSelectionOverlayView(frame: textView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.onClearRequested = { [weak self] in
            self?.clearSelection()
        }
        overlay.onMenuRequested = { [weak self] in
            self?.showMenu(animated: true)
        }
        overlay.onHandlePan = { [weak self] handle, point, state in
            self?.handlePan(handle: handle, point: point, state: state)
        }
        overlay.onExternalPan = { [weak self, weak overlay] point, state in
            guard let overlay else {
                return
            }
            self?.handleExternalPan(
                point: point,
                state: state,
                coordinateView: overlay
            )
        }
        textView.addSubview(overlay)
        overlayView = overlay
    }

    private func updateOverlay(on textView: TextReadView, range: NSRange) {
        let rects = textView.textRects(for: range)
        guard rects.isEmpty == false else {
            clearSelection()
            return
        }

        let orderedRects = rects.sorted {
            if abs($0.minY - $1.minY) > 1 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }
        let startAnchor = CGPoint(
            x: orderedRects[0].minX,
            y: orderedRects[0].minY
        )
        let endAnchor = CGPoint(
            x: orderedRects[orderedRects.count - 1].maxX,
            y: orderedRects[orderedRects.count - 1].maxY
        )
        overlayView?.update(
            rects: orderedRects,
            startAnchor: startAnchor,
            endAnchor: endAnchor
        )
    }

    private func handlePan(
        handle: ReaderTextSelectionHandle,
        point: CGPoint,
        state: UIGestureRecognizer.State
    ) {
        guard let textView = selectedTextView,
              let selectedRange else {
            return
        }

        switch state {
        case .began:
            isDraggingHandle = true
            UIMenuController.shared.setMenuVisible(false, animated: true)
        case .changed:
            let proposedIndex = textView.insertionIndex(at: point)
                ?? fallbackInsertionIndex(for: point, handle: handle, in: textView)
            guard let insertionIndex = proposedIndex else {
                return
            }
            let currentStart = selectedRange.location
            let currentEnd = selectedRange.location + selectedRange.length
            let nextRange: NSRange?
            switch handle {
            case .start:
                nextRange = textView.normalizedSelectionRange(
                    start: insertionIndex,
                    end: currentEnd
                )
            case .end:
                nextRange = textView.normalizedSelectionRange(
                    start: currentStart,
                    end: insertionIndex
                )
            }
            guard let nextRange else {
                return
            }
            self.selectedRange = nextRange
            updateOverlay(on: textView, range: nextRange)
        case .ended, .cancelled, .failed:
            isDraggingHandle = false
            if hasSelection {
                showMenu(animated: true)
            }
        default:
            break
        }
    }

    private func handleExternalPan(
        point: CGPoint,
        state: UIGestureRecognizer.State,
        coordinateView: UIView
    ) {
        guard let selectedTextView,
              let hostView else {
            return
        }

        let hostPoint = hostView.convert(point, from: coordinateView)
        let sourceView = magnifierSourceView(for: selectedTextView)
        let sourcePoint = sourceView.convert(hostPoint, from: hostView)
        switch state {
        case .began:
            hideMenu(animated: true)
            showMagnifier(
                sourceView: sourceView,
                sourcePoint: sourcePoint,
                hostView: hostView,
                anchorPoint: hostPoint
            )
        case .changed:
            showMagnifier(
                sourceView: sourceView,
                sourcePoint: sourcePoint,
                hostView: hostView,
                anchorPoint: hostPoint
            )
        case .ended, .cancelled, .failed:
            hideMagnifier()
            if hasSelection {
                showMenu(animated: true)
            }
        default:
            break
        }
    }

    private func magnifierSourceView(for textView: TextReadView) -> UIView {
        textView.superview ?? textView
    }

    @objc private func externalDragRecognized(_ recognizer: ReaderImmediatePanGestureRecognizer) {
        guard let hostView else {
            return
        }
        handleExternalPan(
            point: recognizer.location(in: hostView),
            state: recognizer.state,
            coordinateView: hostView
        )
    }

    private func hideMenuForBlankLongPressIfNeeded() {
        guard hasSelection else {
            return
        }
        hideMenu(animated: true)
        restoresMenuAfterBlankLongPress = true
    }

    private func showMenu(animated: Bool) {
        guard !isDraggingHandle,
              let selectedTextView,
              let selectedRange,
              let menuResponder else {
            return
        }

        let rects = selectedTextView.textRects(for: selectedRange)
        guard rects.isEmpty == false else {
            return
        }

        let targetRect = rects.reduce(rects[0]) { partial, rect in
            partial.union(rect)
        }
        let menu = UIMenuController.shared
        menu.menuItems = menuItems
        menuResponder.becomeFirstResponder()
        menu.setTargetRect(targetRect, in: selectedTextView)
        menu.setMenuVisible(true, animated: animated)
    }

    private func hideMenu(animated: Bool) {
        UIMenuController.shared.setMenuVisible(false, animated: animated)
    }

    private func showMagnifier(
        sourceView: UIView,
        sourcePoint: CGPoint,
        hostView: UIView,
        anchorPoint: CGPoint
    ) {
        let magnifier = magnifierView ?? ReaderSelectionMagnifierView()
        if magnifier.superview == nil {
            hostView.addSubview(magnifier)
        }
        magnifierView = magnifier
        magnifier.update(
            sourceView: sourceView,
            sourcePoint: sourcePoint,
            hiddenView: overlayView
        )

        let x = min(
            max(anchorPoint.x, magnifier.bounds.width / 2 + 12),
            max(magnifier.bounds.width / 2 + 12, hostView.bounds.width - magnifier.bounds.width / 2 - 12)
        )
        let y = max(magnifier.bounds.height / 2 + 12, anchorPoint.y - 82)
        magnifier.center = CGPoint(x: x, y: y)
        magnifier.isHidden = false
    }

    private func hideMagnifier() {
        magnifierView?.removeFromSuperview()
        magnifierView = nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === externalDragGesture else {
            return true
        }
        guard hasSelection else {
            return false
        }

        var touchedView = touch.view
        while let currentView = touchedView {
            if currentView is UIControl
                || currentView is ReaderTextSelectionOverlayView {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    private func fallbackInsertionIndex(
        for point: CGPoint,
        handle: ReaderTextSelectionHandle,
        in textView: TextReadView
    ) -> Int? {
        guard let selectableRange = textView.selectableTextRange else {
            return nil
        }

        let selectableEnd = selectableRange.location + selectableRange.length
        let contentRect = textView.activeContentRect
        if point.y <= contentRect.minY {
            return selectableRange.location
        }
        if point.y >= contentRect.maxY {
            return selectableEnd
        }
        if point.x <= contentRect.minX {
            return handle == .start ? selectableRange.location : nil
        }
        if point.x >= contentRect.maxX {
            return handle == .end ? selectableEnd : nil
        }
        return nil
    }

    private func trimmedSelectedText() -> String {
        guard let selectedTextView,
              let selectedRange else {
            return ""
        }
        return selectedTextView.selectedString(in: selectedRange)
    }
}

@MainActor
private final class ReaderSelectionMagnifierView: UIView {
    private var snapshotImage: UIImage?
    private let magnification: CGFloat = 1.9
    private let lensInset: CGFloat = 4

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 112, height: 112))
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        layer.cornerRadius = 56
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        sourceView: UIView,
        sourcePoint: CGPoint,
        hiddenView: UIView?
    ) {
        let wasHidden = hiddenView?.isHidden
        hiddenView?.isHidden = true
        snapshotImage = renderSnapshot(sourceView: sourceView, sourcePoint: sourcePoint)
        if let wasHidden = wasHidden {
            hiddenView?.isHidden = wasHidden
        }
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        layer.shadowPath = UIBezierPath(ovalIn: bounds.insetBy(dx: lensInset, dy: lensInset)).cgPath
    }

    override func draw(_ rect: CGRect) {
        guard let snapshotImage else {
            return
        }

        let lensRect = bounds.insetBy(dx: lensInset, dy: lensInset)
        let clipPath = UIBezierPath(ovalIn: lensRect)

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        context.saveGState()
        clipPath.addClip()
        snapshotImage.draw(in: bounds)
        context.restoreGState()

        UIColor.systemBackground.withAlphaComponent(0.95).setStroke()
        clipPath.lineWidth = 3
        clipPath.stroke()
        UIColor.separator.withAlphaComponent(0.35).setStroke()
        clipPath.lineWidth = 1
        clipPath.stroke()
    }

    private func renderSnapshot(sourceView: UIView, sourcePoint: CGPoint) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        return renderer.image { rendererContext in
            let lensRect = bounds.insetBy(dx: lensInset, dy: lensInset)
            UIBezierPath(ovalIn: lensRect).addClip()

            let clampedPoint = clampedSourcePoint(
                sourcePoint,
                in: sourceView.bounds,
                lensRect: lensRect
            )
            let context = rendererContext.cgContext
            context.saveGState()
            context.translateBy(
                x: lensRect.midX - clampedPoint.x * magnification,
                y: lensRect.midY - clampedPoint.y * magnification
            )
            context.scaleBy(x: magnification, y: magnification)
            sourceView.layer.render(in: context)
            context.restoreGState()
        }
    }

    private func clampedSourcePoint(
        _ point: CGPoint,
        in bounds: CGRect,
        lensRect: CGRect
    ) -> CGPoint {
        let radiusX = lensRect.width / (2 * magnification)
        let radiusY = lensRect.height / (2 * magnification)
        let safeBounds = bounds.insetBy(dx: radiusX, dy: radiusY)

        let clampBounds = safeBounds.width > 0 && safeBounds.height > 0
            ? safeBounds
            : bounds
        return CGPoint(
            x: min(max(point.x, clampBounds.minX), clampBounds.maxX),
            y: min(max(point.y, clampBounds.minY), clampBounds.maxY)
        )
    }
}
