import Foundation

struct ReadingProgress: Equatable {
    var bookID: UUID
    var chapterID: UUID?
    var chapterOffset: Int64
    var globalProgress: Double
}

