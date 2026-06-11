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
            return
        }
        let textLocation = textView.convert(location, from: hostView)
        guard let characterIndex = textView.characterIndex(at: textLocation),
              let paragraphRange = textView.paragraphRange(containing: characterIndex) else {
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
        overlay.onHandlePan = { [weak self] handle, point, state in
            self?.handlePan(handle: handle, point: point, state: state)
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
