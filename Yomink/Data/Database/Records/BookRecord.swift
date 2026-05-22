import Foundation
import GRDB

struct BookRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "books"

    let id: String
    let title: String
    let author: String?
    let intro: String?
    let fileName: String
    let fileSize: Int64
    let encoding: String?
    let wordCount: Int
    let importedAt: String
    let lastReadAt: String?
    let groupId: String?
    let importSourceDisplayPath: String?
    let sourceBookmark: Data?
    let sourcePath: String
    let normalizedPath: String?
}
