import Foundation

struct ReadingProgress: Equatable, Sendable {
    var bookID: UUID
    var chapterID: UUID?
    var chapterOffset: Int64 {
        didSet {
            chapterOffset = max(chapterOffset, 0)
        }
    }
    var globalProgress: Double {
        didSet {
            globalProgress = Self.normalizedProgress(globalProgress)
        }
    }

    init(
        bookID: UUID,
        chapterID: UUID?,
        chapterOffset: Int64,
        globalProgress: Double
    ) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.chapterOffset = max(chapterOffset, 0)
        self.globalProgress = Self.normalizedProgress(globalProgress)
    }

    private static func normalizedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
}
