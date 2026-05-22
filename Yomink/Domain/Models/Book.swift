import Foundation

struct Book: Identifiable, Equatable {
    let id: UUID
    var title: String
    var author: String?
    var importedAt: Date
    var lastReadAt: Date?
    var progressPercentage: Double
}

