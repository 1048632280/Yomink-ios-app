import Foundation

enum ReaderPageStatus: Int, Codable, Sendable {
    case normal = 0
    case loading = 1
    case error = 2
}

struct ReaderPageModel: Equatable, Sendable {
    var chapterCount: Int
    var chapterIndex: Int
    var pageCount: Int
    var pageIndex: Int
    var chapterProgress: Double
    var usesPageIndex: Bool
    var pageStatus: ReaderPageStatus

    init(
        chapterCount: Int,
        chapterIndex: Int,
        pageCount: Int,
        pageIndex: Int,
        chapterProgress: Double,
        usesPageIndex: Bool,
        pageStatus: ReaderPageStatus = .normal
    ) {
        self.chapterCount = max(0, chapterCount)
        self.chapterIndex = max(0, chapterIndex)
        self.pageCount = max(0, pageCount)
        self.pageIndex = max(0, pageIndex)
        self.chapterProgress = Self.clampedProgress(chapterProgress)
        self.usesPageIndex = usesPageIndex
        self.pageStatus = pageStatus
    }

    var isNormal: Bool {
        pageStatus == .normal
    }

    static func clampedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }
}
