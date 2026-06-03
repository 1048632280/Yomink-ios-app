import Foundation

struct TextFilterRule: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var source: String
    var replacement: String?
    var createdAt: Date
}
