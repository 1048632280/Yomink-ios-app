import Foundation

struct PreviewLibraryRepository: LibraryRepository {
    static let sampleBookID = UUID(uuidString: "4D52E7FE-A7ED-41F1-8C49-55C3E22B6B48") ?? UUID()
    static let sampleText = "这是一段阅读器预览文本。\n\nPhase 2 已接入按章节读取、分页、点击热区和阅读进度恢复。\n\nPhase 3 会继续加入平移翻页、滚动阅读、目录跳转和阅读设置。"

    func fetchBooks() async throws -> [Book] {
        [
            Book(
                id: Self.sampleBookID,
                title: "示例小说",
                author: nil,
                intro: nil,
                fileName: "sample.txt",
                fileSize: 1_024,
                encoding: "utf-8",
                wordCount: 480,
                importedAt: Date(),
                lastReadAt: nil,
                groupID: nil,
                progressPercentage: 0,
                sourcePath: "Books/\(Self.sampleBookID.uuidString.lowercased())/source.txt",
                normalizedPath: "Books/\(Self.sampleBookID.uuidString.lowercased())/normalized.txt"
            )
        ]
    }

    func fetchGroups() async throws -> [BookGroup] {
        []
    }

    func fetchChapters(bookID: UUID) async throws -> [Chapter] {
        [
            Chapter(
                id: UUID(),
                bookID: bookID,
                title: NSLocalizedString("reader.preview.chapter.title", comment: ""),
                startOffset: 0,
                endOffset: Self.sampleText.utf8.count,
                sortOrder: 0
            )
        ]
    }

    func fetchReadingProgress(bookID: UUID) async throws -> ReadingProgress? {
        ReadingProgress(
            bookID: bookID,
            chapterID: nil,
            chapterOffset: 0,
            globalProgress: 0
        )
    }

    func saveReadingProgress(_ progress: ReadingProgress) async throws {}

    func fetchReaderSettings() async throws -> ReaderSettings {
        .default
    }

    func saveReaderSettings(_ settings: ReaderSettings) async throws {}

    func markBookOpened(id: UUID, at date: Date) async throws {}

    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book {
        Book(
            id: draft.id,
            title: draft.title,
            author: nil,
            intro: nil,
            fileName: draft.fileName,
            fileSize: draft.fileSize,
            encoding: draft.encoding,
            wordCount: draft.wordCount,
            importedAt: draft.importedAt,
            lastReadAt: nil,
            groupID: nil,
            progressPercentage: 0,
            sourcePath: draft.sourcePath,
            normalizedPath: draft.normalizedPath
        )
    }

    func deleteBook(id: UUID) async throws {
    }
}
