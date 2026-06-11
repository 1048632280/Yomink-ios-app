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
    var pageIndex: Int? {
        didSet {
            pageIndex = Self.normalizedOptionalNonNegative(pageIndex)
            normalizePageSnapshotUsage()
        }
    }
    var pageCount: Int? {
        didSet {
            pageCount = Self.normalizedOptionalPositive(pageCount)
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
        bookID: UUID,
        chapterID: UUID?,
        chapterOffset: Int64,
        globalProgress: Double,
        pageIndex: Int? = nil,
        pageCount: Int? = nil,
        usesPageIndex: Bool = false,
        paginationSignature: String? = nil
    ) {
        self.bookID = bookID
        self.chapterID = chapterID
        self.chapterOffset = max(chapterOffset, 0)
        self.globalProgress = Self.normalizedProgress(globalProgress)
        self.pageIndex = Self.normalizedOptionalNonNegative(pageIndex)
        self.pageCount = Self.normalizedOptionalPositive(pageCount)
        self.usesPageIndex = usesPageIndex
            && self.pageIndex != nil
            && self.pageCount != nil
        self.paginationSignature = paginationSignature
    }

    private static func normalizedProgress(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    private static func normalizedOptionalNonNegative(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return max(value, 0)
    }

    private static func normalizedOptionalPositive(_ value: Int?) -> Int? {
        guard let value,
              value > 0 else {
            return nil
        }
        return value
    }

    private mutating func normalizePageSnapshotUsage() {
        if usesPageIndex,
           (pageIndex == nil || pageCount == nil) {
            usesPageIndex = false
        }
    }
}
