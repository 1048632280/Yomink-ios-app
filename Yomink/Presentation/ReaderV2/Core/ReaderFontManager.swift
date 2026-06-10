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

    func bodyFont(size: CGFloat, weightValue: CGFloat = 0) -> UIFont {
        font(size: size, weightValue: weightValue)
    }

    func titleFont(size: CGFloat, weightValue: CGFloat = 0) -> UIFont {
        font(size: size, weightValue: weightValue)
    }

    func font(size: CGFloat, weightValue: CGFloat = 0) -> UIFont {
        let normalizedSize = Self.normalizedFontSize(size)
        if let fontName,
           let customFont = UIFont(name: fontName, size: normalizedSize) {
            return Self.customFont(customFont, applyingWeightValue: weightValue)
        }
        return UIFont.systemFont(
            ofSize: normalizedSize,
            weight: Self.systemWeight(for: weightValue)
        )
    }

    static func normalizedFontSize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return defaultFontSize
        }
        return max(minimumFontSize, value)
    }

    static func normalizedFontWeightValue(_ value: CGFloat) -> Int {
        guard value.isFinite else {
            return 0
        }
        return Int(min(max(value.rounded(), 0), 5))
    }

    static func clampedStrokeWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, minimumStrokeWidth), maximumStrokeWidth)
    }

    private static func systemWeight(for value: CGFloat) -> UIFont.Weight {
        switch normalizedFontWeightValue(value) {
        case 0:
            return .regular
        case 1:
            return .medium
        case 2:
            return .semibold
        case 3:
            return .bold
        case 4:
            return .heavy
        default:
            return .black
        }
    }

    private static func customFont(
        _ font: UIFont,
        applyingWeightValue value: CGFloat
    ) -> UIFont {
        guard normalizedFontWeightValue(value) > 0,
              let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
}
