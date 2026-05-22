import Foundation
import GRDB

struct ReadingProgressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "reading_progress"

    let bookId: String
    let chapterId: String?
    let chapterOffset: Int64
    let globalProgress: Double
    let updatedAt: String
}
