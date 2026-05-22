import Foundation
import GRDB

struct BookRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "books"

    var id: String
    var title: String
    var author: String?
    var intro: String?
    var fileName: String
    var fileSize: Int64
    var encoding: String?
    var wordCount: Int
    var importedAt: String
    var lastReadAt: String?
    var groupId: String?
    var sourcePath: String
    var normalizedPath: String?
}

