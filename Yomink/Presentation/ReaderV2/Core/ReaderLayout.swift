import UIKit

struct ReaderLayout: Equatable, Sendable {
    var topMargin: CGFloat
    var bottomMargin: CGFloat
    var leftMargin: CGFloat
    var rightMargin: CGFloat
    var lineSpacing: CGFloat
    var paragraphSpacing: CGFloat
    var wordSpacing: CGFloat
    var headIndent: CGFloat
    var fontSize: CGFloat
    var fontWeight: CGFloat
    var titleFontWeight: CGFloat
    var titleFontSizeOffset: CGFloat
    var titleLineSpacing: CGFloat
    var titleParagraphSpacing: CGFloat
    var titleWordSpacing: CGFloat

    static let phone = ReaderLayout(
        topMargin: 50,
        bottomMargin: 30,
        leftMargin: 20,
        rightMargin: 20,
        lineSpacing: 10,
        paragraphSpacing: 14,
        wordSpacing: 0,
        headIndent: 2,
        fontSize: 20,
        fontWeight: 0,
        titleFontWeight: 3,
        titleFontSizeOffset: 1,
        titleLineSpacing: 10,
        titleParagraphSpacing: 14,
        titleWordSpacing: 0
    )

    static let notchedPhone = ReaderLayout(
        topMargin: 72,
        bottomMargin: 46,
        leftMargin: 20,
        rightMargin: 20,
        lineSpacing: 10,
        paragraphSpacing: 14,
        wordSpacing: 0,
        headIndent: 2,
        fontSize: 20,
        fontWeight: 0,
        titleFontWeight: 3,
        titleFontSizeOffset: 1,
        titleLineSpacing: 10,
        titleParagraphSpacing: 14,
        titleWordSpacing: 0
    )

    static let pad = ReaderLayout(
        topMargin: 87,
        bottomMargin: 60,
        leftMargin: 44,
        rightMargin: 44,
        lineSpacing: 10,
        paragraphSpacing: 14,
        wordSpacing: 0,
        headIndent: 2,
        fontSize: 20,
        fontWeight: 0,
        titleFontWeight: 3,
        titleFontSizeOffset: 1,
        titleLineSpacing: 10,
        titleParagraphSpacing: 14,
        titleWordSpacing: 0
    )

    func contentRect(in bounds: CGRect) -> CGRect {
        let minX = ceil(leftMargin)
        let minY = ceil(bottomMargin)
        let maxX = floor(bounds.width - rightMargin)
        let maxY = floor(bounds.height - topMargin)
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }
}
