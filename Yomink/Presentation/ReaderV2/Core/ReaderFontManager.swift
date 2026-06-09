import UIKit

struct ReaderFontManager {
    static let defaultFontSize: CGFloat = 20
    static let minimumFontSize: CGFloat = 8
    static let minimumStrokeWidth: CGFloat = -10
    static let maximumStrokeWidth: CGFloat = 10

    var fontName: String?

    init(fontName: String? = nil) {
        let trimmedName = fontName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fontName = trimmedName?.isEmpty == false ? trimmedName : nil
    }

    func bodyFont(size: CGFloat) -> UIFont {
        font(size: size)
    }

    func titleFont(size: CGFloat) -> UIFont {
        font(size: size)
    }

    func font(size: CGFloat) -> UIFont {
        let normalizedSize = Self.normalizedFontSize(size)
        if let fontName,
           let customFont = UIFont(name: fontName, size: normalizedSize) {
            return customFont
        }
        return UIFont.systemFont(ofSize: normalizedSize)
    }

    static func normalizedFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return defaultFontSize
        }
        return max(minimumFontSize, value)
    }

    static func clampedStrokeWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, minimumStrokeWidth), maximumStrokeWidth)
    }
}
