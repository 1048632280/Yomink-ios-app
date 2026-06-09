import CoreText
import UIKit

class TextReadViewBase: UIView {
    private(set) var attributedText = NSAttributedString(string: "")
    private(set) var frameRef: CTFrame?
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

