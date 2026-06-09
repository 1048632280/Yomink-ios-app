import Foundation

struct ReaderRecordBridge: Sendable {
    let chapters: [Chapter]

    func record(chapterIndex: Int, progress: Double = 0) -> ReaderRecord? {
        guard chapters.indices.contains(chapterIndex) else {
            return nil
        }
        let chapter = chapters[chapterIndex]
        return ReaderRecord(
            chapterIndex: chapterIndex,
            progress: progress,
            chapterTitle: chapter.title
        )
    }

    func record(chapterID: UUID, offset: Int) -> ReaderRecord? {
        guard let index = chapters.firstIndex(where: { $0.id == chapterID }) else {
            return nil
        }
        return record(
            chapterIndex: index,
            progress: Self.progress(
                offset: offset,
                byteLength: chapters[index].byteLength
            )
        )
    }

    func record(from target: ReaderContentTarget) -> ReaderRecord? {
        record(chapterID: target.chapterID, offset: target.offset)
    }

    func record(from bookmark: Bookmark) -> ReaderRecord? {
        guard let chapterID = bookmark.chapterID else {
            return nil
        }
        return record(chapterID: chapterID, offset: bookmark.offset)
    }

    private static func progress(offset: Int, byteLength: Int) -> Double {
        guard byteLength > 0 else {
            return 0
        }
        return min(max(Double(max(offset, 0)) / Double(byteLength), 0), 1)
    }
}
