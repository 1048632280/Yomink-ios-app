import Foundation

enum ReaderChapterProviderError: LocalizedError, Equatable {
    case missingChapter
    case invalidUTF8Content

    var errorDescription: String? {
        switch self {
        case .missingChapter:
            return NSLocalizedString("reader.error.bookNotFound", comment: "")
        case .invalidUTF8Content:
            return NSLocalizedString("reader.error.invalidUTF8Content", comment: "")
        }
    }
}

struct ReaderChapterProvider: Sendable {
    let book: Book
    let chapters: [Chapter]
    let fileStore: AppFileStore

    var chapterCount: Int {
        chapters.count
    }

    func chapter(at index: Int) -> Chapter? {
        guard chapters.indices.contains(index) else {
            return nil
        }
        return chapters[index]
    }

    func text(forChapterAt index: Int) throws -> String {
        guard let chapter = chapter(at: index) else {
            throw ReaderChapterProviderError.missingChapter
        }
        let url = try fileStore.url(forRelativePath: book.sourcePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(chapter.startOffset))
        let data = handle.readData(ofLength: chapter.byteLength)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReaderChapterProviderError.invalidUTF8Content
        }
        return text
    }

    func textAsync(forChapterAt index: Int) async throws -> String {
        let provider = self
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let text = try provider.text(forChapterAt: index)
            try Task.checkCancellation()
            return text
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
