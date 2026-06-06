import Foundation

enum LibraryRoute: Hashable {
    case groups
    case history
    case randomPicker
    case tags
    case search
    case settings
    case importBook
}

struct ExportPayload: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]
    let directoryURL: URL
}

struct PendingBookDeletion: Identifiable {
    let id: String
    let ids: Set<UUID>

    init(ids: Set<UUID>) {
        self.ids = ids
        self.id = ids.map(\.uuidString).sorted().joined(separator: "-")
    }

    var message: String {
        if ids.count <= 1 {
            return NSLocalizedString("library.delete.confirm.single.message", comment: "")
        }
        return String(
            format: NSLocalizedString("library.delete.confirm.multiple.message", comment: ""),
            ids.count
        )
    }
}
