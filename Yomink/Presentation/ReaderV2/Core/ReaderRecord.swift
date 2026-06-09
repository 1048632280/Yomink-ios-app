import Foundation

struct ReaderRecord: Equatable, Sendable {
    var chapterIndex: Int
    var progress: Double
    var chapterTitle: String
    var timestamp: Date

    init(
        chapterIndex: Int,
        progress: Double,
        chapterTitle: String,
        timestamp: Date = Date()
    ) {
        self.chapterIndex = max(0, chapterIndex)
        self.progress = ReaderPageModel.clampedProgress(progress)
        self.chapterTitle = chapterTitle
        self.timestamp = timestamp
    }
}
