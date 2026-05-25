import Foundation

struct ReadingProgress: Equatable, Sendable {
    var bookID: UUID
    var chapterID: UUID?
    var chapterOffset: Int64
    var globalProgress: Double
}

enum ChapterSource: String, Codable, Equatable, Sendable {
    case regex
    case pseudo
}

struct Chapter: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var title: String
    var startOffset: Int
    var endOffset: Int
    var sortOrder: Int
    var source: ChapterSource

    var byteLength: Int {
        max(0, endOffset - startOffset)
    }
}

struct Bookmark: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var chapterID: UUID?
    var offset: Int
    var preview: String
    var createdAt: Date
}

struct TextFilterRule: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var source: String
    var replacement: String?
    var createdAt: Date
}

struct ReaderSettings: Codable, Equatable, Sendable {
    enum PageMode: String, Codable, CaseIterable, Sendable {
        case paged
        case scroll
    }

    enum Theme: String, Codable, CaseIterable, Sendable {
        case white
        case eyeCare
        case paper
        case dark
    }

    enum TouchAreaAction: String, Codable, CaseIterable, Sendable {
        case previousPage
        case menu
        case nextPage
        case none
    }

    var pageMode: PageMode
    var theme: Theme
    var fontSize: Double
    var autoReadSpeed: Double
    var touchAreaMap: [TouchAreaAction]
    var keepScreenAwake: Bool
    var autoHideHomeIndicator: Bool
    var autoHideStatusBar: Bool
    var edgeSwipeBackEnabled: Bool

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
        case fontSize
        case autoReadSpeed
        case touchAreaMap
        case keepScreenAwake
        case autoHideHomeIndicator
        case autoHideStatusBar
        case edgeSwipeBackEnabled
    }

    static var `default`: ReaderSettings {
        ReaderSettings(
            pageMode: .paged,
            theme: .white,
            fontSize: 18,
            autoReadSpeed: 80,
            touchAreaMap: Self.defaultTouchAreaMap,
            keepScreenAwake: false,
            autoHideHomeIndicator: true,
            autoHideStatusBar: true,
            edgeSwipeBackEnabled: true
        )
    }

    init(
        pageMode: PageMode = .paged,
        theme: Theme = .white,
        fontSize: Double = 18,
        autoReadSpeed: Double = 80,
        touchAreaMap: [TouchAreaAction] = Self.defaultTouchAreaMap,
        keepScreenAwake: Bool = false,
        autoHideHomeIndicator: Bool = true,
        autoHideStatusBar: Bool = true,
        edgeSwipeBackEnabled: Bool = true
    ) {
        self.pageMode = pageMode
        self.theme = theme
        self.fontSize = fontSize
        self.autoReadSpeed = autoReadSpeed
        self.touchAreaMap = touchAreaMap
        self.keepScreenAwake = keepScreenAwake
        self.autoHideHomeIndicator = autoHideHomeIndicator
        self.autoHideStatusBar = autoHideStatusBar
        self.edgeSwipeBackEnabled = edgeSwipeBackEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageMode = (try? container.decodeIfPresent(PageMode.self, forKey: .pageMode)) ?? .paged
        theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? .white
        fontSize = (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? 18
        autoReadSpeed = (try? container.decodeIfPresent(Double.self, forKey: .autoReadSpeed)) ?? 80
        touchAreaMap = (try? container.decodeIfPresent([TouchAreaAction].self, forKey: .touchAreaMap))
            ?? Self.defaultTouchAreaMap
        keepScreenAwake = (try? container.decodeIfPresent(Bool.self, forKey: .keepScreenAwake)) ?? false
        autoHideHomeIndicator = (try? container.decodeIfPresent(Bool.self, forKey: .autoHideHomeIndicator)) ?? true
        autoHideStatusBar = (try? container.decodeIfPresent(Bool.self, forKey: .autoHideStatusBar)) ?? true
        edgeSwipeBackEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .edgeSwipeBackEnabled)) ?? true
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
        if settings.touchAreaMap.count != Self.touchAreaCount {
            settings.touchAreaMap = Self.defaultTouchAreaMap
        }
        if settings.touchAreaMap.contains(.menu) == false {
            settings.touchAreaMap[Self.touchAreaCount / 2] = .menu
        }
        return settings
    }
}
