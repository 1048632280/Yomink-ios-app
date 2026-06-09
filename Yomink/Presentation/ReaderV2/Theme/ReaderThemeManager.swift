import UIKit

struct ReaderChromeTheme {
    var barBackgroundColor: UIColor
    var panelBackgroundColor: UIColor
    var separatorColor: UIColor
    var primaryTextColor: UIColor
    var secondaryTextColor: UIColor
    var controlTintColor: UIColor
    var dimmingColor: UIColor

    static let standard = ReaderChromeTheme(
        barBackgroundColor: UIColor(white: 1, alpha: 0.94),
        panelBackgroundColor: UIColor(white: 1, alpha: 0.98),
        separatorColor: UIColor(white: 0, alpha: 0.12),
        primaryTextColor: UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1),
        secondaryTextColor: UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1),
        controlTintColor: UIColor(red: 0.18, green: 0.45, blue: 0.92, alpha: 1),
        dimmingColor: UIColor(white: 0, alpha: 0.12)
    )

    static let dark = ReaderChromeTheme(
        barBackgroundColor: UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 0.96),
        panelBackgroundColor: UIColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 0.98),
        separatorColor: UIColor(white: 1, alpha: 0.12),
        primaryTextColor: UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1),
        secondaryTextColor: UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 1),
        controlTintColor: UIColor(red: 0.48, green: 0.64, blue: 0.96, alpha: 1),
        dimmingColor: UIColor(white: 0, alpha: 0.32)
    )
}

enum ReaderThemeManager {
    static func turnPageType(from settings: ReaderSettings) -> ReaderTurnPageType {
        switch settings.normalized.pageMode {
        case .paged:
            return .horizontalScroll
        case .curl:
            return .pageCurl
        case .scroll:
            return .verticalContinuous
        }
    }

    static func layout(from settings: ReaderSettings) -> ReaderLayout {
        let normalized = settings.normalized
        let values = layoutValues(from: normalized)

        return ReaderLayout(
            topMargin: CGFloat(values.bodyTopMargin),
            bottomMargin: CGFloat(values.bodyBottomMargin),
            leftMargin: CGFloat(values.bodyLeftMargin),
            rightMargin: CGFloat(values.bodyRightMargin),
            lineSpacing: CGFloat(values.bodyLineSpacing),
            paragraphSpacing: CGFloat(values.bodyParagraphSpacing),
            wordSpacing: CGFloat(values.bodyKern),
            headIndent: CGFloat(values.firstLineIndentEms),
            fontSize: CGFloat(normalized.fontSize),
            fontWeight: CGFloat(values.bodyFontWeightValue),
            titleFontWeight: CGFloat(values.titleFontWeightValue),
            titleFontSizeOffset: CGFloat(values.titleFontSizeDelta),
            titleLineSpacing: CGFloat(values.titleLineSpacing),
            titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
            titleWordSpacing: CGFloat(values.titleKern),
            widgetTitleTop: CGFloat(values.widgetTitleTopMargin),
            widgetTitleLeft: CGFloat(values.widgetTitleLeftMargin),
            widgetBottom: CGFloat(values.widgetBottomMargin),
            widgetLeft: CGFloat(values.widgetHorizontalMargin),
            widgetRight: CGFloat(values.widgetHorizontalMargin)
        )
    }

    static func theme(from settings: ReaderSettings) -> ReaderTheme {
        switch settings.normalized.theme {
        case .white:
            return .standard
        case .eyeCare:
            return ReaderTheme(
                contentColor: UIColor(red: 0.11, green: 0.18, blue: 0.12, alpha: 1),
                headerColor: .secondaryLabel,
                backgroundColor: UIColor(red: 0.92, green: 0.97, blue: 0.90, alpha: 1),
                backgroundImageName: nil,
                backgroundImageStyle: nil
            )
        case .paper:
            return ReaderTheme(
                contentColor: UIColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 1),
                headerColor: .secondaryLabel,
                backgroundColor: UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1),
                backgroundImageName: nil,
                backgroundImageStyle: nil
            )
        case .dark:
            return .dark
        }
    }

    static func chromeTheme(from settings: ReaderSettings) -> ReaderChromeTheme {
        settings.normalized.theme == .dark ? .dark : .standard
    }

    static func needsRepagination(
        from previous: ReaderSettings,
        to next: ReaderSettings
    ) -> Bool {
        let previous = previous.normalized
        let next = next.normalized
        return previous.pageMode != next.pageMode
            || previous.theme != next.theme
            || previous.layoutPreset != next.layoutPreset
            || previous.customLayoutValues != next.customLayoutValues
            || previous.fontSize != next.fontSize
    }

    static func needsChromeRefresh(
        from previous: ReaderSettings,
        to next: ReaderSettings
    ) -> Bool {
        let previous = previous.normalized
        let next = next.normalized
        return previous.theme != next.theme
            || previous.keepScreenAwake != next.keepScreenAwake
            || previous.autoHideHomeIndicator != next.autoHideHomeIndicator
            || previous.statusBarMode != next.statusBarMode
            || previous.widgetVisibility != next.widgetVisibility
    }

    static func layoutValues(from settings: ReaderSettings) -> ReaderSettings.LayoutValues {
        let normalized = settings.normalized
        if normalized.layoutPreset == .custom {
            return normalized.customLayoutValues?.normalized ?? .standard
        }

        switch normalized.layoutPreset {
        case .compact:
            return .compact
        case .standard:
            return .standard
        case .relaxed:
            return .relaxed
        case .custom:
            return .standard
        }
    }
}

extension ReaderTheme {
    var isDark: Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if backgroundColor.getWhite(&white, alpha: &alpha) {
            return white < 0.5
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return ((red * 0.299) + (green * 0.587) + (blue * 0.114)) < 0.5
        }
        return false
    }
}
