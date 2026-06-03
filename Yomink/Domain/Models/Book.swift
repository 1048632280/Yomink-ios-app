import Foundation

struct Book: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String?
    var intro: String?
    var fileName: String
    var fileSize: Int64 {
        didSet {
            fileSize = max(fileSize, 0)
        }
    }
    var encoding: String?
    var wordCount: Int {
        didSet {
            wordCount = max(wordCount, 0)
        }
    }
    var importedAt: Date
    var lastReadAt: Date?
    var groupID: UUID?
    var progressPercentage: Double {
        didSet {
            progressPercentage = Self.normalizedProgress(progressPercentage)
        }
    }
    var contentHash: String?
    var sourcePath: String

    init(
        id: UUID,
        title: String,
        author: String?,
        intro: String?,
        fileName: String,
        fileSize: Int64,
        encoding: String?,
        wordCount: Int,
        importedAt: Date,
        lastReadAt: Date?,
        groupID: UUID?,
        progressPercentage: Double,
        contentHash: String?,
        sourcePath: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.intro = intro
        self.fileName = fileName
        self.fileSize = max(fileSize, 0)
        self.encoding = encoding
        self.wordCount = max(wordCount, 0)
        self.importedAt = importedAt
        self.lastReadAt = lastReadAt
        self.groupID = groupID
        self.progressPercentage = Self.normalizedProgress(progressPercentage)
        self.contentHash = contentHash
        self.sourcePath = sourcePath
    }

    private static func normalizedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
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
    var drawCounts: [UUID: Int]

    static let storageKey = "randomPicker.state"
    static let cooldownLimit = 10

    private enum CodingKeys: String, CodingKey {
        case selectedScopes
        case recentBookIDs
        case drawCounts
    }

    static var `default`: RandomPickerState {
        RandomPickerState(
            selectedScopes: nil,
            recentBookIDs: [],
            drawCounts: [:]
        )
    }

    init(
        selectedScopes: [RandomPickerScope]? = nil,
        recentBookIDs: [UUID] = [],
        drawCounts: [UUID: Int] = [:]
    ) {
        self.selectedScopes = selectedScopes
        self.recentBookIDs = recentBookIDs
        self.drawCounts = drawCounts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedScopes = try container.decodeIfPresent([RandomPickerScope].self, forKey: .selectedScopes)
        recentBookIDs = (try? container.decodeIfPresent([UUID].self, forKey: .recentBookIDs)) ?? []
        drawCounts = (try? container.decodeIfPresent([UUID: Int].self, forKey: .drawCounts)) ?? [:]
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
        state.drawCounts = state.drawCounts.filter { entry in
            entry.value > 0
        }
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
