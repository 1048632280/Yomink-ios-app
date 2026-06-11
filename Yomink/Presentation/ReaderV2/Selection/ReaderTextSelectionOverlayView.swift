import UIKit

enum ReaderTextSelectionHandle {
    case start
    case end
}

@MainActor
final class ReaderTextSelectionOverlayView: UIView, UIGestureRecognizerDelegate {
    private let startHandleView = ReaderSelectionHandleView(kind: .start)
    private let endHandleView = ReaderSelectionHandleView(kind: .end)
    private var selectionRects: [CGRect] = []

    var onClearRequested: (() -> Void)?
    var onMenuRequested: (() -> Void)?
    var onHandlePan: ((ReaderTextSelectionHandle, CGPoint, UIGestureRecognizer.State) -> Void)?
    var onExternalPan: ((CGPoint, UIGestureRecognizer.State) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        addSubview(startHandleView)
        addSubview(endHandleView)
        configureGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        rects: [CGRect],
        startAnchor: CGPoint?,
        endAnchor: CGPoint?
    ) {
        selectionRects = rects
        startHandleView.isHidden = startAnchor == nil
        endHandleView.isHidden = endAnchor == nil
        if let startAnchor {
            startHandleView.place(anchor: startAnchor)
        }
        if let endAnchor {
            endHandleView.place(anchor: endAnchor)
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              selectionRects.isEmpty == false else {
            return
        }

        context.saveGState()
        UIColor.systemBlue.withAlphaComponent(0.26).setFill()
        for selectionRect in drawingSelectionRects() where selectionRect.intersects(rect) {
            UIBezierPath(
                roundedRect: selectionRect.integral,
                cornerRadius: 2
            ).fill()
        }
        context.restoreGState()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        true
    }

    private func configureGestures() {
        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(selectionOverlayTapped(_:))
        )
        addGestureRecognizer(tapGesture)

        let externalPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(externalAreaPanned(_:))
        )
        externalPan.delegate = self
        addGestureRecognizer(externalPan)
        tapGesture.require(toFail: externalPan)

        let startPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(startHandlePanned(_:))
        )
        startHandleView.addGestureRecognizer(startPan)

        let endPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(endHandlePanned(_:))
        )
        endHandleView.addGestureRecognizer(endPan)
    }

    @objc private func selectionOverlayTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        let location = recognizer.location(in: self)
        if startHandleView.frame.insetBy(dx: -8, dy: -8).contains(location)
            || endHandleView.frame.insetBy(dx: -8, dy: -8).contains(location) {
            return
        }
        if containsSelection(at: location) {
            DispatchQueue.main.async { [weak self] in
                self?.onMenuRequested?()
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onClearRequested?()
        }
    }

    @objc private func startHandlePanned(_ recognizer: UIPanGestureRecognizer) {
        onHandlePan?(.start, recognizer.location(in: self), recognizer.state)
    }

    @objc private func endHandlePanned(_ recognizer: UIPanGestureRecognizer) {
        onHandlePan?(.end, recognizer.location(in: self), recognizer.state)
    }

    @objc private func externalAreaPanned(_ recognizer: UIPanGestureRecognizer) {
        onExternalPan?(recognizer.location(in: self), recognizer.state)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        let location = touch.location(in: self)
        return !containsHandle(at: location)
            && !containsSelection(at: location)
    }

    private func containsHandle(at point: CGPoint) -> Bool {
        startHandleView.frame.insetBy(dx: -8, dy: -8).contains(point)
            || endHandleView.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    private func containsSelection(at point: CGPoint) -> Bool {
        drawingSelectionRects().contains { rect in
            rect.insetBy(dx: -6, dy: -6).contains(point)
        }
    }

    private func drawingSelectionRects() -> [CGRect] {
        guard selectionRects.count > 1 else {
            return selectionRects
        }

        var rects = selectionRects.sorted {
            if abs($0.minY - $1.minY) > 1 {
                return $0.minY < $1.minY
            }
            return $0.minX < $1.minX
        }

        for index in rects.indices.dropFirst() {
            let previousIndex = rects.index(before: index)
            let previousMaxY = rects[previousIndex].maxY
            guard rects[index].minY > previousMaxY else {
                continue
            }

            let midpoint = (previousMaxY + rects[index].minY) / 2
            rects[previousIndex].size.height = midpoint - rects[previousIndex].minY
            let currentMaxY = rects[index].maxY
            rects[index].origin.y = midpoint
            rects[index].size.height = currentMaxY - midpoint
        }

        return rects
    }
}

@MainActor
private final class ReaderSelectionHandleView: UIView {
    private enum Layout {
        static let width: CGFloat = 28
        static let height: CGFloat = 36
        static let knobDiameter: CGFloat = 12
        static let stemWidth: CGFloat = 2
    }

    private let kind: ReaderTextSelectionHandle

    init(kind: ReaderTextSelectionHandle) {
        self.kind = kind
        super.init(frame: CGRect(
            x: 0,
            y: 0,
            width: Layout.width,
            height: Layout.height
        ))
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func place(anchor: CGPoint) {
        switch kind {
        case .start:
            frame = CGRect(
                x: anchor.x - Layout.width / 2,
                y: anchor.y - Layout.knobDiameter / 2,
                width: Layout.width,
                height: Layout.height
            ).integral
        case .end:
            frame = CGRect(
                x: anchor.x - Layout.width / 2,
                y: anchor.y - Layout.height + Layout.knobDiameter / 2,
                width: Layout.width,
                height: Layout.height
            ).integral
        }
    }

    override func draw(_ rect: CGRect) {
        UIColor.systemBlue.setFill()

        let stemX = (bounds.width - Layout.stemWidth) / 2
        let stemRect: CGRect
        let knobRect: CGRect
        switch kind {
        case .start:
            knobRect = CGRect(
                x: (bounds.width - Layout.knobDiameter) / 2,
                y: 0,
                width: Layout.knobDiameter,
                height: Layout.knobDiameter
            )
            stemRect = CGRect(
                x: stemX,
                y: Layout.knobDiameter / 2,
                width: Layout.stemWidth,
                height: bounds.height - Layout.knobDiameter / 2
            )
        case .end:
            knobRect = CGRect(
                x: (bounds.width - Layout.knobDiameter) / 2,
                y: bounds.height - Layout.knobDiameter,
                width: Layout.knobDiameter,
                height: Layout.knobDiameter
            )
            stemRect = CGRect(
                x: stemX,
                y: 0,
                width: Layout.stemWidth,
                height: bounds.height - Layout.knobDiameter / 2
            )
        }

        UIBezierPath(roundedRect: stemRect, cornerRadius: Layout.stemWidth / 2).fill()
        UIBezierPath(ovalIn: knobRect).fill()
    }
}
