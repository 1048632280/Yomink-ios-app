import Foundation

struct ReaderSettings: Codable, Equatable, Sendable {
    enum PageMode: String, Codable, CaseIterable, Sendable {
        case paged
        case curl
        case scroll
    }

    enum Theme: String, Codable, CaseIterable, Sendable {
        case white
        case eyeCare
        case paper
        case dark
    }

    enum LayoutPreset: String, Codable, CaseIterable, Sendable {
        case compact
        case standard
        case relaxed
        case custom
    }

    struct LayoutValues: Codable, Equatable, Sendable {
        var bodyKern: Double
        var bodyLineSpacing: Double
        var bodyParagraphSpacing: Double
        var bodyTopMargin: Double
        var bodyBottomMargin: Double
        var bodyLeftMargin: Double
        var bodyRightMargin: Double
        var bodyFontWeightValue: Double
        var firstLineIndentEms: Double
        var titleKern: Double
        var titleLineSpacing: Double
        var titleParagraphSpacing: Double
        var titleFontWeightValue: Double
        var titleFontSizeDelta: Double
        var widgetHorizontalMargin: Double
        var widgetBottomMargin: Double
        var widgetTitleTopMargin: Double
        var widgetTitleLeftMargin: Double

        private enum CodingKeys: String, CodingKey {
            case bodyKern
            case bodyLineSpacing
            case bodyParagraphSpacing
            case bodyTopMargin
            case bodyBottomMargin
            case bodyLeftMargin
            case bodyRightMargin
            case bodyFontWeightValue
            case firstLineIndentEms
            case titleKern
            case titleLineSpacing
            case titleParagraphSpacing
            case titleFontWeightValue
            case titleFontSizeDelta
            case widgetHorizontalMargin
            case widgetBottomMargin
            case widgetTitleTopMargin
            case widgetTitleLeftMargin
        }

        init(
            bodyKern: Double,
            bodyLineSpacing: Double,
            bodyParagraphSpacing: Double,
            bodyTopMargin: Double,
            bodyBottomMargin: Double,
            bodyLeftMargin: Double,
            bodyRightMargin: Double,
            bodyFontWeightValue: Double,
            firstLineIndentEms: Double,
            titleKern: Double,
            titleLineSpacing: Double,
            titleParagraphSpacing: Double,
            titleFontWeightValue: Double,
            titleFontSizeDelta: Double,
            widgetHorizontalMargin: Double,
            widgetBottomMargin: Double,
            widgetTitleTopMargin: Double,
            widgetTitleLeftMargin: Double
        ) {
            self.bodyKern = bodyKern
            self.bodyLineSpacing = bodyLineSpacing
            self.bodyParagraphSpacing = bodyParagraphSpacing
            self.bodyTopMargin = bodyTopMargin
            self.bodyBottomMargin = bodyBottomMargin
            self.bodyLeftMargin = bodyLeftMargin
            self.bodyRightMargin = bodyRightMargin
            self.bodyFontWeightValue = bodyFontWeightValue
            self.firstLineIndentEms = firstLineIndentEms
            self.titleKern = titleKern
            self.titleLineSpacing = titleLineSpacing
            self.titleParagraphSpacing = titleParagraphSpacing
            self.titleFontWeightValue = titleFontWeightValue
            self.titleFontSizeDelta = titleFontSizeDelta
            self.widgetHorizontalMargin = widgetHorizontalMargin
            self.widgetBottomMargin = widgetBottomMargin
            self.widgetTitleTopMargin = widgetTitleTopMargin
            self.widgetTitleLeftMargin = widgetTitleLeftMargin
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Self.standard
            bodyKern = (try? container.decodeIfPresent(Double.self, forKey: .bodyKern)) ?? defaults.bodyKern
            bodyLineSpacing = (try? container.decodeIfPresent(Double.self, forKey: .bodyLineSpacing)) ?? defaults.bodyLineSpacing
            bodyParagraphSpacing = (try? container.decodeIfPresent(Double.self, forKey: .bodyParagraphSpacing)) ?? defaults.bodyParagraphSpacing
            bodyTopMargin = (try? container.decodeIfPresent(Double.self, forKey: .bodyTopMargin)) ?? defaults.bodyTopMargin
            bodyBottomMargin = (try? container.decodeIfPresent(Double.self, forKey: .bodyBottomMargin)) ?? defaults.bodyBottomMargin
            bodyLeftMargin = (try? container.decodeIfPresent(Double.self, forKey: .bodyLeftMargin)) ?? defaults.bodyLeftMargin
            bodyRightMargin = (try? container.decodeIfPresent(Double.self, forKey: .bodyRightMargin)) ?? defaults.bodyRightMargin
            bodyFontWeightValue = (try? container.decodeIfPresent(Double.self, forKey: .bodyFontWeightValue)) ?? defaults.bodyFontWeightValue
            firstLineIndentEms = (try? container.decodeIfPresent(Double.self, forKey: .firstLineIndentEms)) ?? defaults.firstLineIndentEms
            titleKern = (try? container.decodeIfPresent(Double.self, forKey: .titleKern)) ?? defaults.titleKern
            titleLineSpacing = (try? container.decodeIfPresent(Double.self, forKey: .titleLineSpacing)) ?? defaults.titleLineSpacing
            titleParagraphSpacing = (try? container.decodeIfPresent(Double.self, forKey: .titleParagraphSpacing)) ?? defaults.titleParagraphSpacing
            titleFontWeightValue = (try? container.decodeIfPresent(Double.self, forKey: .titleFontWeightValue)) ?? defaults.titleFontWeightValue
            titleFontSizeDelta = (try? container.decodeIfPresent(Double.self, forKey: .titleFontSizeDelta)) ?? defaults.titleFontSizeDelta
            widgetHorizontalMargin = (try? container.decodeIfPresent(Double.self, forKey: .widgetHorizontalMargin)) ?? defaults.widgetHorizontalMargin
            widgetBottomMargin = (try? container.decodeIfPresent(Double.self, forKey: .widgetBottomMargin)) ?? defaults.widgetBottomMargin
            widgetTitleTopMargin = (try? container.decodeIfPresent(Double.self, forKey: .widgetTitleTopMargin)) ?? defaults.widgetTitleTopMargin
            widgetTitleLeftMargin = (try? container.decodeIfPresent(Double.self, forKey: .widgetTitleLeftMargin)) ?? defaults.widgetTitleLeftMargin
        }

        static let compact = LayoutValues(
            bodyKern: 0,
            bodyLineSpacing: 6,
            bodyParagraphSpacing: 8,
            bodyTopMargin: 56,
            bodyBottomMargin: 36,
            bodyLeftMargin: 16,
            bodyRightMargin: 16,
            bodyFontWeightValue: 0,
            firstLineIndentEms: 2,
            titleKern: 0,
            titleLineSpacing: 6,
            titleParagraphSpacing: 10,
            titleFontWeightValue: 3,
            titleFontSizeDelta: 1,
            widgetHorizontalMargin: 16,
            widgetBottomMargin: 24,
            widgetTitleTopMargin: 39,
            widgetTitleLeftMargin: 16
        )

        static let standard = LayoutValues(
            bodyKern: 0,
            bodyLineSpacing: 10,
            bodyParagraphSpacing: 14,
            bodyTopMargin: 72,
            bodyBottomMargin: 46,
            bodyLeftMargin: 20,
            bodyRightMargin: 20,
            bodyFontWeightValue: 0,
            firstLineIndentEms: 2,
            titleKern: 0,
            titleLineSpacing: 10,
            titleParagraphSpacing: 14,
            titleFontWeightValue: 3,
            titleFontSizeDelta: 1,
            widgetHorizontalMargin: 20,
            widgetBottomMargin: 27,
            widgetTitleTopMargin: 43,
            widgetTitleLeftMargin: 20
        )

        static let relaxed = LayoutValues(
            bodyKern: 0,
            bodyLineSpacing: 14,
            bodyParagraphSpacing: 20,
            bodyTopMargin: 88,
            bodyBottomMargin: 58,
            bodyLeftMargin: 24,
            bodyRightMargin: 24,
            bodyFontWeightValue: 0,
            firstLineIndentEms: 2,
            titleKern: 0,
            titleLineSpacing: 14,
            titleParagraphSpacing: 20,
            titleFontWeightValue: 3,
            titleFontSizeDelta: 1,
            widgetHorizontalMargin: 24,
            widgetBottomMargin: 31,
            widgetTitleTopMargin: 47,
            widgetTitleLeftMargin: 24
        )

        var normalized: LayoutValues {
            var values = self
            values.bodyKern = min(max(values.bodyKern, -1), 3)
            values.bodyLineSpacing = min(max(values.bodyLineSpacing, 0), 28)
            values.bodyParagraphSpacing = min(max(values.bodyParagraphSpacing, 0), 36)
            values.bodyTopMargin = min(max(values.bodyTopMargin, 0), 160)
            values.bodyBottomMargin = min(max(values.bodyBottomMargin, 0), 140)
            values.bodyLeftMargin = min(max(values.bodyLeftMargin, 0), 80)
            values.bodyRightMargin = min(max(values.bodyRightMargin, 0), 80)
            values.bodyFontWeightValue = min(max(values.bodyFontWeightValue.rounded(), 0), 5)
            values.firstLineIndentEms = min(max(values.firstLineIndentEms, 0), 4)
            values.titleKern = min(max(values.titleKern, -1), 3)
            values.titleLineSpacing = min(max(values.titleLineSpacing, 0), 28)
            values.titleParagraphSpacing = min(max(values.titleParagraphSpacing, 0), 40)
            values.titleFontWeightValue = min(max(values.titleFontWeightValue.rounded(), 0), 5)
            values.titleFontSizeDelta = min(max(values.titleFontSizeDelta, 0), 8)
            values.widgetHorizontalMargin = min(max(values.widgetHorizontalMargin, 0), 80)
            values.widgetBottomMargin = min(max(values.widgetBottomMargin, 0), 90)
            values.widgetTitleTopMargin = min(max(values.widgetTitleTopMargin, 0), 120)
            values.widgetTitleLeftMargin = min(max(values.widgetTitleLeftMargin, 0), 80)
            return values
        }
    }

    struct WidgetVisibility: Codable, Equatable, Sendable {
        var chapterTitle: Bool
        var batteryPercentage: Bool
        var batteryIcon: Bool
        var time: Bool
        var chapterPageProgress: Bool
        var globalProgress: Bool

        static var `default`: WidgetVisibility {
            WidgetVisibility(
                chapterTitle: true,
                batteryPercentage: true,
                batteryIcon: true,
                time: true,
                chapterPageProgress: true,
                globalProgress: false
            )
        }

        static var hidden: WidgetVisibility {
            WidgetVisibility(
                chapterTitle: false,
                batteryPercentage: false,
                batteryIcon: false,
                time: false,
                chapterPageProgress: false,
                globalProgress: false
            )
        }
    }

    enum TouchAreaAction: String, Codable, CaseIterable, Sendable {
        case previousPage
        case menu
        case nextPage
        case none
    }

    var pageMode: PageMode
    var theme: Theme
    var layoutPreset: LayoutPreset
    var customLayoutValues: LayoutValues?
    var fontSize: Double
    var autoReadSpeed: Double
    var touchAreaMap: [TouchAreaAction]
    var keepScreenAwake: Bool
    var autoHideHomeIndicator: Bool
    var autoHideStatusBar: Bool
    var edgeSwipeBackEnabled: Bool
    var widgetVisibility: WidgetVisibility

    static let storageKey = "reader.settings"
    static let minimumFontSize = 14.0
    static let maximumFontSize = 28.0
    static let minimumAutoReadSpeed = 20.0
    static let maximumAutoReadSpeed = 180.0
    static let touchAreaCount = 9
    static let defaultTouchAreaMap: [TouchAreaAction] = [
        .previousPage, .menu, .nextPage,
        .previousPage, .menu, .nextPage,
        .previousPage, .menu, .nextPage
    ]

    private enum CodingKeys: String, CodingKey {
        case pageMode
        case theme
        case layoutPreset
        case customLayoutValues
        case fontSize
        case autoReadSpeed
        case touchAreaMap
        case keepScreenAwake
        case autoHideHomeIndicator
        case autoHideStatusBar
        case edgeSwipeBackEnabled
        case widgetVisibility
    }

    static var `default`: ReaderSettings {
        ReaderSettings(
            pageMode: .paged,
            theme: .white,
            layoutPreset: .standard,
            customLayoutValues: nil,
            fontSize: 18,
            autoReadSpeed: 80,
            touchAreaMap: Self.defaultTouchAreaMap,
            keepScreenAwake: false,
            autoHideHomeIndicator: true,
            autoHideStatusBar: true,
            edgeSwipeBackEnabled: true,
            widgetVisibility: .default
        )
    }

    init(
        pageMode: PageMode = .paged,
        theme: Theme = .white,
        layoutPreset: LayoutPreset = .standard,
        customLayoutValues: LayoutValues? = nil,
        fontSize: Double = 18,
        autoReadSpeed: Double = 80,
        touchAreaMap: [TouchAreaAction] = Self.defaultTouchAreaMap,
        keepScreenAwake: Bool = false,
        autoHideHomeIndicator: Bool = true,
        autoHideStatusBar: Bool = true,
        edgeSwipeBackEnabled: Bool = true,
        widgetVisibility: WidgetVisibility = .default
    ) {
        self.pageMode = pageMode
        self.theme = theme
        self.layoutPreset = layoutPreset
        self.customLayoutValues = customLayoutValues
        self.fontSize = fontSize
        self.autoReadSpeed = autoReadSpeed
        self.touchAreaMap = touchAreaMap
        self.keepScreenAwake = keepScreenAwake
        self.autoHideHomeIndicator = autoHideHomeIndicator
        self.autoHideStatusBar = autoHideStatusBar
        self.edgeSwipeBackEnabled = edgeSwipeBackEnabled
        self.widgetVisibility = widgetVisibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageMode = (try? container.decodeIfPresent(PageMode.self, forKey: .pageMode)) ?? .paged
        theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? .white
        layoutPreset = (try? container.decodeIfPresent(LayoutPreset.self, forKey: .layoutPreset)) ?? .standard
        customLayoutValues = (try? container.decodeIfPresent(LayoutValues.self, forKey: .customLayoutValues))?
            .normalized
        fontSize = (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? 18
        autoReadSpeed = (try? container.decodeIfPresent(Double.self, forKey: .autoReadSpeed)) ?? 80
        touchAreaMap = (try? container.decodeIfPresent([TouchAreaAction].self, forKey: .touchAreaMap))
            ?? Self.defaultTouchAreaMap
        keepScreenAwake = (try? container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake)) ?? false
        autoHideHomeIndicator = (try? container.decodeIfPresent(Bool.self, forKey: .autoHideHomeIndicator)) ?? true
        autoHideStatusBar = (try? container.decodeIfPresent(Bool.self, forKey: .autoHideStatusBar)) ?? true
        edgeSwipeBackEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .edgeSwipeBackEnabled)) ?? true
        widgetVisibility = (try? container.decodeIfPresent(WidgetVisibility.self, forKey: .widgetVisibility)) ?? .default
    }

    var normalized: ReaderSettings {
        var settings = self
        settings.fontSize = min(
            max(settings.fontSize, Self.minimumFontSize),
            Self.maximumFontSize
        )
        settings.autoReadSpeed = min(
            max(settings.autoReadSpeed, Self.minimumAutoReadSpeed),
            Self.maximumAutoReadSpeed
        )
        settings.customLayoutValues = settings.customLayoutValues?.normalized
        if settings.layoutPreset == .custom,
           settings.customLayoutValues == nil {
            settings.customLayoutValues = LayoutValues.standard
        }
        if settings.touchAreaMap.count != Self.touchAreaCount {
            settings.touchAreaMap = Self.defaultTouchAreaMap
        }
        if settings.touchAreaMap.contains(.menu) == false {
            settings.touchAreaMap[Self.touchAreaCount / 2] = .menu
        }
        return settings
    }
}
