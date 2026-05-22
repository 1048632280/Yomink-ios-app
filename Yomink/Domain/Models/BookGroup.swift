import Foundation

struct BookGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
}
