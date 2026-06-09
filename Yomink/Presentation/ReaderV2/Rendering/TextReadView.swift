import CoreText
import UIKit

final class TextReadView: TextReadViewBase {
    override func draw(_ rect: CGRect) {
        guard let frameRef,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        CTFrameDraw(frameRef, context)
        context.restoreGState()
    }
}

