import Foundation
import GRDB

struct ReadingProgressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reading_progress"

    var bookId: String
    var chapterId: String?
    var chapterOffset: Int64
    var globalProgress: Double
    var updatedAt: String
}

