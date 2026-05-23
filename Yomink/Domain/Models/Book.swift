import Foundation

struct Book: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String?
    var intro: String?
    var fileName: String
    var fileSize: Int64
    var encoding: String?
    var wordCount: Int
    var importedAt: Date
    var lastReadAt: Date?
    var groupID: UUID?
    var progressPercentage: Double
    var sourcePath: String
    var normalizedPath: String?
}

enum LibraryScope: Equatable, Sendable {
    case all
    case ungrouped
    case group(UUID)

    var settingsKey: String {
        switch self {
        case .all:
            return "all"
        case .ungrouped:
            return "ungrouped"
        case let .group(id):
            return "group-\(id.uuidString)"
        }
    }
}

struct LibrarySettings: Codable, Equatable, Sendable {
    enum ViewMode: String, Codable, CaseIterable, Sendable {
        case list
        case grid
    }

    enum SortOrder: String, Codable, CaseIterable, Sendable {
        case importedAt
        case lastReadAt
    }

    var viewMode: ViewMode
    var sortOrder: SortOrder

    static let storageKey = "library.settings"

    private enum CodingKeys: String, CodingKey {
        case viewMode
        case sortOrder
    }

    static var `default`: LibrarySettings {
        LibrarySettings(
            viewMode: .list,
            sortOrder: .lastReadAt
        )
    }

    init(
        viewMode: ViewMode = .list,
        sortOrder: SortOrder = .lastReadAt
    ) {
        self.viewMode = viewMode
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewMode = (try? container.decodeIfPresent(ViewMode.self, forKey: .viewMode)) ?? .list
        sortOrder = (try? container.decodeIfPresent(SortOrder.self, forKey: .sortOrder)) ?? .lastReadAt
    }
}

struct SearchHistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var keyword: String
    var createdAt: Date
}

struct ReadingHistoryItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var book: Book
    var chapterTitle: String?
    var offset: Int
    var readAt: Date
}
