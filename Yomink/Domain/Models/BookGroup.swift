import Foundation

struct BookGroup: Identifiable, Equatable {
    let id: UUID
    var name: String
    var sortOrder: Int
}

