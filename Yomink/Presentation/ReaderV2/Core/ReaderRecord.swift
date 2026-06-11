import Foundation

struct ReaderRecord: Equatable, Sendable {
    var chapterIndex: Int
    var progress: Double
    var chapterTitle: String
    var timestamp: Date
    var pageIndex: Int? {
        didSet {
            pageIndex = pageIndex.map { max($0, 0) }
            normalizePageSnapshotUsage()
        }
    }
    var pageCount: Int? {
        didSet {
            pageCount = pageCount.flatMap { $0 > 0 ? $0 : nil }
            normalizePageSnapshotUsage()
        }
    }
    var usesPageIndex: Bool {
        didSet {
            normalizePageSnapshotUsage()
        }
    }
    var paginationSignature: String?

    init(
        chapterIndex: Int,
        progress: Double,
        chapterTitle: String,
        timestamp: Date = Date(),
        pageIndex: Int? = nil,
        pageCount: Int? = nil,
        usesPageIndex: Bool = false,
        paginationSignature: String? = nil
    ) {
        self.chapterIndex = max(0, chapterIndex)
        self.progress = ReaderPageModel.clampedProgress(progress)
        self.chapterTitle = chapterTitle
        self.timestamp = timestamp
        self.pageIndex = pageIndex.map { max($0, 0) }
        self.pageCount = pageCount.flatMap { $0 > 0 ? $0 : nil }
        self.usesPageIndex = usesPageIndex
            && self.pageIndex != nil
            && self.pageCount != nil
        self.paginationSignature = paginationSignature
    }

    private mutating func normalizePageSnapshotUsage() {
        if usesPageIndex,
           (pageIndex == nil || pageCount == nil) {
            usesPageIndex = false
        }
    }
}
