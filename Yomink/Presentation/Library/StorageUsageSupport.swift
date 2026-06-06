import Foundation
import SwiftUI

enum StorageUsageScanner {
    static func snapshot(
        fileStore: AppFileStore,
        books: [Book],
        groups: [BookGroup]
    ) async -> StorageUsageSnapshot {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let bookUsages = books.map { book in
                StorageBookUsage(
                    book: book,
                    bytes: Self.contentSize(for: book, fileStore: fileStore, fileManager: fileManager)
                )
            }

            let txtBytes = bookUsages.reduce(Int64(0)) { $0 + $1.bytes }
            let booksDirectoryBytes = Self.directorySize(at: fileStore.booksURL, fileManager: fileManager)
            let applicationSupportBytes = Self.directorySize(
                at: fileStore.applicationSupportURL,
                fileManager: fileManager
            )
            let databaseBytes = Self.databaseSize(fileStore: fileStore, fileManager: fileManager)
            let temporaryExportBytes = Self.temporaryExportSize(fileManager: fileManager)
            let indexCacheBytes = max(0, booksDirectoryBytes - txtBytes)
            let otherBytes = max(0, applicationSupportBytes - booksDirectoryBytes - databaseBytes)

            let categories = [
                StorageUsageCategory(kind: .txt, bytes: txtBytes),
                StorageUsageCategory(kind: .database, bytes: databaseBytes),
                StorageUsageCategory(kind: .temporaryExport, bytes: temporaryExportBytes),
                StorageUsageCategory(kind: .indexCache, bytes: indexCacheBytes),
                StorageUsageCategory(kind: .other, bytes: otherBytes)
            ]

            return StorageUsageSnapshot(
                categories: categories,
                books: bookUsages,
                groups: groups
            )
        }.value
    }

    private static func contentSize(
        for book: Book,
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        guard let url = try? fileStore.url(forRelativePath: book.sourcePath) else {
            return 0
        }
        return fileSize(at: url, fileManager: fileManager)
    }

    private static func databaseSize(
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        [
            fileStore.databaseURL,
            URL(fileURLWithPath: fileStore.databaseURL.path + "-wal"),
            URL(fileURLWithPath: fileStore.databaseURL.path + "-shm")
        ].reduce(Int64(0)) { result, url in
            result + fileSize(at: url, fileManager: fileManager)
        }
    }

    private static func temporaryExportSize(fileManager: FileManager) -> Int64 {
        guard let exportURLs = try? fileManager.contentsOfDirectory(
            at: fileManager.temporaryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return 0
        }

        return exportURLs
            .filter { $0.lastPathComponent.hasPrefix("YominkExports") }
            .reduce(Int64(0)) { result, url in
                result + Self.directorySize(at: url, fileManager: fileManager)
            }
    }

    private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey
                ]
              )
        else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return total
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
              ])
        else {
            return 0
        }
        return Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
        )
    }
}

struct StorageUsageSnapshot: Sendable {
    let categories: [StorageUsageCategory]
    let books: [StorageBookUsage]
    let groups: [BookGroup]

    var totalBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var bookCount: Int {
        books.count
    }
}

struct StorageUsageCategory: Identifiable, Sendable {
    let kind: StorageUsageKind
    let bytes: Int64

    var id: String {
        kind.rawValue
    }
}

enum StorageUsageKind: String, Sendable {
    case txt
    case database
    case temporaryExport
    case indexCache
    case other

    var titleKey: LocalizedStringKey {
        switch self {
        case .txt:
            return "storage.category.txt"
        case .database:
            return "storage.category.database"
        case .temporaryExport:
            return "storage.category.temporaryExport"
        case .indexCache:
            return "storage.category.indexCache"
        case .other:
            return "storage.category.other"
        }
    }

    var color: Color {
        switch self {
        case .txt:
            return Color(red: 0.20, green: 0.45, blue: 0.78)
        case .database:
            return Color(red: 0.28, green: 0.58, blue: 0.34)
        case .temporaryExport:
            return Color(red: 0.84, green: 0.52, blue: 0.22)
        case .indexCache:
            return Color(red: 0.48, green: 0.38, blue: 0.70)
        case .other:
            return Color(.systemGray3)
        }
    }
}

struct StorageDonutSlice: Identifiable {
    let category: StorageUsageCategory
    let start: Double
    let end: Double

    var id: String {
        category.id
    }
}

struct StorageBookUsage: Identifiable, Sendable {
    let book: Book
    let bytes: Int64

    var id: UUID {
        book.id
    }

    var title: String {
        book.title
    }

    var groupID: UUID? {
        book.groupID
    }

    var importedAt: Date {
        book.importedAt
    }

    var lastReadAt: Date? {
        book.lastReadAt
    }

    var progressPercentage: Double {
        book.progressPercentage
    }

    var isUnread: Bool {
        progressPercentage <= 0.0001
    }
}

enum StorageBookSort: CaseIterable, Hashable {
    case size
    case lastReadAt
    case importedAt

    var titleKey: LocalizedStringKey {
        switch self {
        case .size:
            return "storage.sort.size"
        case .lastReadAt:
            return "storage.sort.lastReadAt"
        case .importedAt:
            return "storage.sort.importedAt"
        }
    }

    func areInIncreasingOrder(_ lhs: StorageBookUsage, _ rhs: StorageBookUsage) -> Bool {
        switch self {
        case .size:
            if lhs.bytes == rhs.bytes {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        case .lastReadAt:
            let leftDate = lhs.lastReadAt ?? .distantPast
            let rightDate = rhs.lastReadAt ?? .distantPast
            if leftDate == rightDate {
                return lhs.importedAt > rhs.importedAt
            }
            return leftDate > rightDate
        case .importedAt:
            return lhs.importedAt > rhs.importedAt
        }
    }
}

enum StorageBookFilter: Equatable {
    case all
    case ungrouped
    case group(UUID)
    case unread
    case longUnread

    private static let longUnreadInterval: TimeInterval = 30 * 24 * 60 * 60

    func title(groups: [BookGroup]) -> String {
        switch self {
        case .all:
            return NSLocalizedString("storage.filter.all", comment: "")
        case .ungrouped:
            return NSLocalizedString("sidebar.ungrouped", comment: "")
        case let .group(id):
            return groups.first { $0.id == id }?.name
                ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
        case .unread:
            return NSLocalizedString("storage.filter.unread", comment: "")
        case .longUnread:
            return NSLocalizedString("storage.filter.longUnread", comment: "")
        }
    }

    func includes(
        _ book: StorageBookUsage,
        groups: [BookGroup],
        now: Date
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .ungrouped:
            return book.groupID == nil
        case let .group(id):
            return book.groupID == id && groups.contains { $0.id == id }
        case .unread:
            return book.isUnread
        case .longUnread:
            guard let lastReadAt = book.lastReadAt else {
                return false
            }
            return lastReadAt < now.addingTimeInterval(-Self.longUnreadInterval)
        }
    }
}

enum StorageByteCountFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

enum StorageDateFormatter {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}


struct StorageExportPayload: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let directoryURL: URL
}
