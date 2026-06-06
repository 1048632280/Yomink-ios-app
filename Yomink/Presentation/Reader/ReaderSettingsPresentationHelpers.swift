import UIKit

extension ReaderSettings.LayoutPreset {
    var layoutConfiguration: ReaderLayoutConfiguration {
        layoutConfiguration(customValues: nil)
    }

    fileprivate func layoutConfiguration(customValues: ReaderSettings.LayoutValues?) -> ReaderLayoutConfiguration {
        let values = customValues?.normalized ?? layoutValues
        switch self {
        case .compact:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        case .standard, .custom:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        case .relaxed:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        }
    }

    fileprivate var layoutValues: ReaderSettings.LayoutValues {
        switch self {
        case .compact:
            return .compact
        case .standard, .custom:
            return .standard
        case .relaxed:
            return .relaxed
        }
    }
}

extension ReaderSettings {
    var effectiveLayoutValues: LayoutValues {
        normalized.layoutPreset == .custom
            ? (normalized.customLayoutValues?.normalized ?? .standard)
            : normalized.layoutPreset.layoutValues
    }

    var effectiveLayoutConfiguration: ReaderLayoutConfiguration {
        normalized.layoutPreset.layoutConfiguration(
            customValues: normalized.layoutPreset == .custom
                ? normalized.customLayoutValues
                : nil
        )
    }
}

extension ReaderSettings.Theme {
    var backgroundColor: UIColor {
        switch self {
        case .white:
            return .systemBackground
        case .eyeCare:
            return UIColor(red: 0.92, green: 0.97, blue: 0.90, alpha: 1)
        case .paper:
            return UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1)
        case .dark:
            return UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .white:
            return .label
        case .eyeCare:
            return UIColor(red: 0.11, green: 0.18, blue: 0.12, alpha: 1)
        case .paper:
            return UIColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return UIColor(red: 0.88, green: 0.88, blue: 0.86, alpha: 1)
        }
    }

    var secondaryTextColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.70, green: 0.70, blue: 0.68, alpha: 1)
        default:
            return .secondaryLabel
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}
