import Foundation

struct ReaderProgressBridge: Sendable {
    let book: Book
    let chapters: [Chapter]

    func record(from progress: ReadingProgress?) -> ReaderRecord {
        guard let progress else {
            let title = chapters.first?.title ?? ""
            return ReaderRecord(chapterIndex: 0, progress: 0, chapterTitle: title)
        }

        guard let chapterID = progress.chapterID,
              let index = chapters.firstIndex(where: { $0.id == chapterID })
        else {
            return recordFromGlobalProgress(progress.globalProgress)
        }

        let chapter = chapters[index]
        let chapterProgress = Self.progress(
            offset: Int(progress.chapterOffset),
            byteLength: chapter.byteLength
        )
        return ReaderRecord(
            chapterIndex: index,
            progress: chapterProgress,
            chapterTitle: chapter.title
        )
    }

    private func recordFromGlobalProgress(_ globalProgress: Double) -> ReaderRecord {
        guard chapters.isEmpty == false else {
            return ReaderRecord(chapterIndex: 0, progress: 0, chapterTitle: "")
        }

        let totalByteLength = max(chapters.last?.endOffset ?? 1, 1)
        let absoluteOffset = min(
            max(Int((Double(totalByteLength) * ReaderPageModel.clampedProgress(globalProgress)).rounded(.down)), 0),
            max(totalByteLength - 1, 0)
        )
        let index = chapters.lastIndex { chapter in
            absoluteOffset >= chapter.startOffset
        } ?? 0
        let chapter = chapters[index]
        let chapterOffset = max(absoluteOffset - chapter.startOffset, 0)
        return ReaderRecord(
            chapterIndex: index,
            progress: Self.progress(
                offset: chapterOffset,
                byteLength: chapter.byteLength
            ),
            chapterTitle: chapter.title
        )
    }

    func readingProgress(from pageModel: ReaderPageModel) -> ReadingProgress? {
        guard chapters.indices.contains(pageModel.chapterIndex) else {
            return nil
        }
        let chapter = chapters[pageModel.chapterIndex]
        let normalizedProgress = ReaderPageCalculator.pageProgress(
            pageCount: pageModel.pageCount,
            pageIndex: pageModel.pageIndex,
            progress: pageModel.chapterProgress,
            usesPageIndex: pageModel.usesPageIndex
        )
        let offset = Self.offset(
            progress: normalizedProgress,
            byteLength: chapter.byteLength
        )
        let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let absoluteOffset = chapter.startOffset + offset
        let globalProgress = min(max(Double(absoluteOffset) / Double(totalByteLength), 0), 1)
        return ReadingProgress(
            bookID: book.id,
            chapterID: chapter.id,
            chapterOffset: Int64(offset),
            globalProgress: globalProgress
        )
    }

    private static func progress(offset: Int, byteLength: Int) -> Double {
        guard byteLength > 0 else {
            return 0
        }
        return min(max(Double(offset) / Double(byteLength), 0), 1)
    }

    private static func offset(progress: Double, byteLength: Int) -> Int {
        guard byteLength > 0 else {
            return 0
        }
        let clamped = ReaderPageModel.clampedProgress(progress)
        return min(max(Int((Double(byteLength) * clamped).rounded(.down)), 0), max(byteLength - 1, 0))
    }
}
