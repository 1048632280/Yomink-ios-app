import Foundation
import GRDB

struct BookGroupRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "book_groups"

    let id: String
    let name: String
    let sortOrder: Int
    let createdAt: String
}
