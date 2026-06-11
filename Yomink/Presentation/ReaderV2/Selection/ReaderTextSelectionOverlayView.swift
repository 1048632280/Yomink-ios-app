import UIKit

enum ReaderTextSelectionHandle {
    case start
    case end
}

@MainActor
final class ReaderTextSelectionOverlayView: UIView {
    private let startHandleView = ReaderSelectionHandleView(kind: .start)
    private let endHandleView = ReaderSelectionHandleView(kind: .end)
    private var selectionRects: [CGRect] = []

    var onClearRequested: (() -> Void)?
    var onHandlePan: ((ReaderTextSelectionHandle, CGPoint, UIGestureRecognizer.State) -> Void)?

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
        for selectionRect in selectionRects where selectionRect.intersects(rect) {
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
