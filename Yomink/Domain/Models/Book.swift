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
    var contentHash: String?
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

enum RandomPickerScope: Hashable, Codable, Sendable {
    case ungrouped
    case group(UUID)

    private static let ungroupedStorageValue = "ungrouped"
    private static let groupPrefix = "group:"

    var storageKey: String {
        switch self {
        case .ungrouped:
            return Self.ungroupedStorageValue
        case let .group(id):
            return "\(Self.groupPrefix)\(id.uuidString)"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == Self.ungroupedStorageValue {
            self = .ungrouped
            return
        }
        if rawValue.hasPrefix(Self.groupPrefix) {
            let idString = String(rawValue.dropFirst(Self.groupPrefix.count))
            if let id = UUID(uuidString: idString) {
                self = .group(id)
                return
            }
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid random picker scope: \(rawValue)"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}

struct RandomPickerState: Codable, Equatable, Sendable {
    var selectedScopes: [RandomPickerScope]?
    var recentBookIDs: [UUID]

    static let storageKey = "randomPicker.state"
    static let cooldownLimit = 5

    static var `default`: RandomPickerState {
        RandomPickerState(
            selectedScopes: nil,
            recentBookIDs: []
        )
    }

    var normalized: RandomPickerState {
        var state = self
        state.selectedScopes = state.selectedScopes.map { scopes in
            var seenKeys: Set<String> = []
            return scopes.filter { scope in
                seenKeys.insert(scope.storageKey).inserted
            }
        }
        state.recentBookIDs = Array(state.recentBookIDs.uniqued().prefix(Self.cooldownLimit))
        return state
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

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
