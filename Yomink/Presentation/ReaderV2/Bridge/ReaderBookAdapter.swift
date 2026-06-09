import Foundation

struct ReaderBookAdapter: Sendable {
    let book: Book
    let chapters: [Chapter]
    let fileStore: AppFileStore

    var chapterProvider: ReaderChapterProvider {
        ReaderChapterProvider(
            book: book,
            chapters: chapters,
            fileStore: fileStore
        )
    }

    var progressBridge: ReaderProgressBridge {
        ReaderProgressBridge(
            book: book,
            chapters: chapters
        )
    }
}
