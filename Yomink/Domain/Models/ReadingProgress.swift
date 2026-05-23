import Foundation

struct ReadingProgress: Equatable, Sendable {
    var bookID: UUID
    var chapterID: UUID?
    var chapterOffset: Int64
    var globalProgress: Double
}

struct Chapter: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var title: String
    var startOffset: Int
    var endOffset: Int
    var sortOrder: Int

    var byteLength: Int {
        max(0, endOffset - startOffset)
    }
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

    var pageMode: PageMode
    var theme: Theme
    var fontSize: Double

    static let storageKey = "reader.settings"
    static let minimumFontSize = 14.0
    static let maximumFontSize = 28.0

    private enum CodingKeys: String, CodingKey {
        case pageMode
        case theme
        case fontSize
    }

    static var `default`: ReaderSettings {
        ReaderSettings(
            pageMode: .paged,
            theme: .white,
            fontSize: 18
        )
    }

    init(
        pageMode: PageMode = .paged,
        theme: Theme = .white,
        fontSize: Double = 18
    ) {
        self.pageMode = pageMode
        self.theme = theme
        self.fontSize = fontSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageMode = (try? container.decodeIfPresent(PageMode.self, forKey: .pageMode)) ?? .paged
        theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? .white
        fontSize = (try? container.decodeIfPresent(Double.self, forKey: .fontSize)) ?? 18
    }

    var normalized: ReaderSettings {
        var settings = self
        settings.fontSize = min(
            max(settings.fontSize, Self.minimumFontSize),
            Self.maximumFontSize
        )
        return settings
    }
}
