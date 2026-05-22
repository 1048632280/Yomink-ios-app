import Foundation
import GRDB

struct BookGroupRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "book_groups"

    var id: String
    var name: String
    var sortOrder: Int
    var createdAt: String
}

