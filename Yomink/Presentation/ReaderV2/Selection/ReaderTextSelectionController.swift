import UIKit

@MainActor
final class ReaderTextSelectionController: NSObject {
    typealias TargetProvider = (CGPoint) -> TextReadView?

    private weak var hostView: UIView?
    private weak var menuResponder: UIResponder?
    private let targetProvider: TargetProvider
    private let isSelectionEnabled: () -> Bool
    private let menuItems: [UIMenuItem]

    private var longPressGesture: UILongPressGestureRecognizer?
    private weak var selectedTextView: TextReadView?
    private var overlayView: ReaderTextSelectionOverlayView?
    private var magnifierView: ReaderSelectionMagnifierView?
    private var selectedRange: NSRange?
    private var isDraggingHandle = false

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
    }

    func clearSelection(hidesMenu: Bool = true) {
        selectedRange = nil
        selectedTextView = nil
        overlayView?.removeFromSuperview()
        overlayView = nil
        hideMagnifier()
        isDraggingHandle = false
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

    @objc private func longPressRecognized(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else {
            return
        }
        guard isSelectionEnabled() else {
            clearSelection()
            return
        }
        guard let hostView else {
            return
        }

        let location = recognizer.location(in: hostView)
        guard let textView = targetProvider(location) else {
            if hasSelection {
                hideMenu(animated: true)
            }
            return
        }
        let textLocation = textView.convert(location, from: hostView)
        guard let characterIndex = textView.characterIndex(at: textLocation) else {
            if hasSelection {
                hideMenu(animated: true)
            }
            return
        }
        guard let paragraphRange = textView.paragraphRange(containing: characterIndex) else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        select(range: paragraphRange, in: textView)
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
        overlay.onExternalPan = { [weak self] point, state in
            self?.handleExternalPan(point: point, state: state)
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
        state: UIGestureRecognizer.State
    ) {
        guard let selectedTextView,
              let hostView else {
            return
        }

        switch state {
        case .began:
            hideMenu(animated: true)
            showMagnifier(sourceView: selectedTextView, sourcePoint: point, hostView: hostView)
        case .changed:
            showMagnifier(sourceView: selectedTextView, sourcePoint: point, hostView: hostView)
        case .ended, .cancelled, .failed:
            hideMagnifier()
            if hasSelection {
                showMenu(animated: true)
            }
        default:
            break
        }
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
        hostView: UIView
    ) {
        let magnifier = magnifierView ?? ReaderSelectionMagnifierView()
        if magnifier.superview == nil {
            hostView.addSubview(magnifier)
        }
        magnifierView = magnifier
        magnifier.update(sourceView: sourceView, sourcePoint: sourcePoint)

        let hostPoint = hostView.convert(sourcePoint, from: sourceView)
        let x = min(
            max(hostPoint.x, magnifier.bounds.width / 2 + 12),
            max(magnifier.bounds.width / 2 + 12, hostView.bounds.width - magnifier.bounds.width / 2 - 12)
        )
        let y = max(magnifier.bounds.height / 2 + 12, hostPoint.y - 78)
        magnifier.center = CGPoint(x: x, y: y)
        magnifier.isHidden = false
    }

    private func hideMagnifier() {
        magnifierView?.removeFromSuperview()
        magnifierView = nil
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
    private weak var sourceView: UIView?
    private var sourcePoint = CGPoint.zero
    private let magnification: CGFloat = 1.85

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 118, height: 76))
        backgroundColor = .systemBackground
        isOpaque = false
        isUserInteractionEnabled = false
        layer.cornerRadius = 14
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 9
        layer.shadowOffset = CGSize(width: 0, height: 5)
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(sourceView: UIView, sourcePoint: CGPoint) {
        self.sourceView = sourceView
        self.sourcePoint = sourcePoint
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let sourceView,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let clipPath = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 13
        )
        UIColor.systemBackground.setFill()
        clipPath.fill()

        context.saveGState()
        clipPath.addClip()
        context.translateBy(
            x: bounds.midX - sourcePoint.x * magnification,
            y: bounds.midY - sourcePoint.y * magnification
        )
        context.scaleBy(x: magnification, y: magnification)
        sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
        context.restoreGState()
    }
}
