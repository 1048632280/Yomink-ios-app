import CoreText
import UIKit

enum ReaderTextSelectionAction {
    case copy
    case search
    case filter
}

final class TextReadView: TextReadViewBase {
    private let startHandle = ReaderV2TextSelectionHandleView(handleRole: .start)
    private let endHandle = ReaderV2TextSelectionHandleView(handleRole: .end)
    private var longPressGesture: UILongPressGestureRecognizer?

    var onSelectionAction: ((ReaderTextSelectionAction, String) -> Void)?

    var isSelectionActive: Bool {
        selectedRange != nil
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureSelectionInteraction()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateSelectionHandles()
    }

    override func setSelectedRange(_ range: NSRange?) {
        super.setSelectedRange(range)
        updateSelectionHandles()
    }

    override func draw(_ rect: CGRect) {
        guard let frameRef,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        drawTextBackgrounds(in: context)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frameRef, context)
        context.restoreGState()
    }

    func clearSelection() {
        setSelectedRange(nil)
        UIMenuController.shared.hideMenu()
        resignFirstResponder()
    }

    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool {
        guard selectedText.isEmpty == false else {
            return false
        }
        return action == #selector(copySelectedText(_:))
            || action == #selector(searchSelectedText(_:))
            || action == #selector(filterSelectedText(_:))
    }

    private func configureSelectionInteraction() {
        isUserInteractionEnabled = true
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(longPressChanged(_:))
        )
        longPress.minimumPressDuration = 0.38
        addGestureRecognizer(longPress)
        longPressGesture = longPress

        [startHandle, endHandle].forEach { handle in
            handle.isHidden = true
            handle.addTarget(self, action: #selector(handleDragged(_:for:)), for: .touchDragInside)
            handle.addTarget(self, action: #selector(handleDragged(_:for:)), for: .touchDragOutside)
            handle.addTarget(self, action: #selector(handleDragEnded(_:for:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
            addSubview(handle)
        }
    }

    @objc private func longPressChanged(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else {
            return
        }
        let location = gesture.location(in: self)
        guard let range = selectionRange(at: location) else {
            clearSelection()
            return
        }
        setSelectedRange(range)
        showSelectionMenu()
    }

    @objc private func handleDragged(
        _ sender: ReaderV2TextSelectionHandleView,
        for event: UIEvent
    ) {
        guard let touch = event.touches(for: sender)?.first else {
            return
        }
        updateSelection(
            for: sender.handleRole,
            at: touch.location(in: self),
            showsMenu: false
        )
    }

    @objc private func handleDragEnded(
        _ sender: ReaderV2TextSelectionHandleView,
        for event: UIEvent
    ) {
        guard let touch = event.touches(for: sender)?.first else {
            showSelectionMenu()
            return
        }
        updateSelection(
            for: sender.handleRole,
            at: touch.location(in: self),
            showsMenu: true
        )
    }

    private func updateSelection(
        for role: ReaderV2TextSelectionHandleRole,
        at point: CGPoint,
        showsMenu: Bool
    ) {
        guard let selectedRange,
              let index = closestCharacterIndex(to: point) else {
            return
        }
        let currentStart = selectedRange.location
        let currentEnd = selectedRange.location + selectedRange.length
        let nextRange: NSRange
        switch role {
        case .start:
            let nextStart = min(max(index, 0), max(currentEnd - 1, 0))
            nextRange = NSRange(location: nextStart, length: max(1, currentEnd - nextStart))
        case .end:
            let nextEnd = max(min(index + 1, attributedText.length), currentStart + 1)
            nextRange = NSRange(location: currentStart, length: max(1, nextEnd - currentStart))
        }
        setSelectedRange(nextRange)
        if showsMenu {
            showSelectionMenu()
        }
    }

    private func updateSelectionHandles() {
        guard let selectedRange,
              let points = selectionHandlePoints(for: selectedRange) else {
            startHandle.isHidden = true
            endHandle.isHidden = true
            return
        }
        position(startHandle, at: points.start)
        position(endHandle, at: points.end)
        startHandle.isHidden = false
        endHandle.isHidden = false
        bringSubviewToFront(startHandle)
        bringSubviewToFront(endHandle)
    }

    private func position(
        _ handle: ReaderV2TextSelectionHandleView,
        at point: CGPoint
    ) {
        let size = ReaderV2TextSelectionHandleView.preferredSize
        handle.frame = CGRect(
            x: point.x - size.width / 2,
            y: point.y - 2,
            width: size.width,
            height: size.height
        ).integral
    }

    private func showSelectionMenu() {
        guard selectedText.isEmpty == false else {
            return
        }
        becomeFirstResponder()
        let menu = UIMenuController.shared
        menu.menuItems = [
            UIMenuItem(title: "拷贝", action: #selector(copySelectedText(_:))),
            UIMenuItem(title: "搜索", action: #selector(searchSelectedText(_:))),
            UIMenuItem(title: "过滤", action: #selector(filterSelectedText(_:)))
        ]
        menu.showMenu(from: self, rect: selectionMenuRect())
    }

    private func selectionMenuRect() -> CGRect {
        guard let selectedRange else {
            return bounds
        }
        let rects = textRects(for: selectedRange)
        guard let first = rects.first else {
            return bounds
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }.intersection(bounds)
    }

    private var selectedText: String {
        guard let selectedRange,
              attributedText.length > 0 else {
            return ""
        }
        return (attributedText.string as NSString)
            .substring(with: selectedRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc private func copySelectedText(_ sender: Any?) {
        let text = selectedText
        guard text.isEmpty == false else {
            return
        }
        UIPasteboard.general.string = text
        onSelectionAction?(.copy, text)
        clearSelection()
    }

    @objc private func searchSelectedText(_ sender: Any?) {
        let text = selectedText
        guard text.isEmpty == false else {
            return
        }
        onSelectionAction?(.search, text)
        clearSelection()
    }

    @objc private func filterSelectedText(_ sender: Any?) {
        let text = selectedText
        guard text.isEmpty == false else {
            return
        }
        onSelectionAction?(.filter, text)
        clearSelection()
    }
}

private enum ReaderV2TextSelectionHandleRole {
    case start
    case end
}

private final class ReaderV2TextSelectionHandleView: UIControl {
    static let preferredSize = CGSize(width: 24, height: 28)

    let handleRole: ReaderV2TextSelectionHandleRole

    init(handleRole: ReaderV2TextSelectionHandleRole) {
        self.handleRole = handleRole
        super.init(frame: CGRect(origin: .zero, size: Self.preferredSize))
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let color = tintColor ?? UIColor.systemBlue
        color.setFill()
        let stemX = rect.midX - 1
        UIBezierPath(
            roundedRect: CGRect(x: stemX, y: 0, width: 2, height: rect.height - 8),
            cornerRadius: 1
        ).fill()
        UIBezierPath(
            ovalIn: CGRect(x: rect.midX - 5, y: rect.height - 10, width: 10, height: 10)
        ).fill()
    }
}
