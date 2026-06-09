import Foundation

enum ReaderPageCalculator {
    static func pageIndex(
        pageCount: Int,
        pageIndex: Int,
        progress: Double,
        usesPageIndex: Bool
    ) -> Int {
        guard pageCount > 0 else {
            return 0
        }
        let index = usesPageIndex
            ? pageIndex
            : Int(ReaderPageModel.clampedProgress(progress) * Double(pageCount))
        return min(max(index, 0), pageCount - 1)
    }

    static func pageProgress(
        pageCount: Int,
        pageIndex: Int,
        progress: Double,
        usesPageIndex: Bool
    ) -> Double {
        guard pageCount > 0, usesPageIndex else {
            return ReaderPageModel.clampedProgress(progress)
        }

        let last = pageCount - 1
        if pageIndex < 1 {
            return 0
        }
        if pageIndex >= last {
            return 1
        }
        return Double(pageIndex) / Double(last)
    }
}

