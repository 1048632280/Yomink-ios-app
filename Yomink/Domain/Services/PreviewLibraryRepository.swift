import Foundation

struct PreviewLibraryRepository: LibraryRepository {
    static let sampleBookID = UUID(uuidString: "4D52E7FE-A7ED-41F1-8C49-55C3E22B6B48") ?? UUID()
    static let sampleText = "这是一段阅读器预览文本。\n\nPhase 2 已接入按章节读取、分页、点击热区和阅读进度恢复。\n\nPhase 3 会继续加入平移翻页、滚动阅读、目录跳转和阅读设置。"

    func fetchBooks(
        scope: LibraryScope,
        sortOrder: LibrarySettings.SortOrder
    ) async throws -> [Book] {
        let books = [
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

        switch scope {
        case .all, .ungrouped:
            return books
        case .group:
            return []
        }
    }

    func searchBooks(
        keyword: String,
        sortOrder: LibrarySettings.SortOrder
    ) async throws -> [Book] {
        try await fetchBooks(scope: .all, sortOrder: sortOrder)
            .filter { $0.title.localizedCaseInsensitiveContains(keyword) }
    }

    func fetchSearchHistory() async throws -> [SearchHistoryItem] {
        []
    }

    func saveSearchKeyword(_ keyword: String) async throws {}

    func clearSearchHistory() async throws {}

    func fetchGroups() async throws -> [BookGroup] {
        []
    }

    func createGroup(name: String) async throws -> BookGroup {
        BookGroup(id: UUID(), name: name, sortOrder: 0)
    }

    func renameGroup(id: UUID, name: String) async throws {}

    func deleteGroup(id: UUID) async throws {}

    func reorderGroups(ids: [UUID]) async throws {}

    func moveBooks(ids: Set<UUID>, to groupID: UUID?) async throws {}

    func fetchChapters(bookID: UUID) async throws -> [Chapter] {
        [
            Chapter(
                id: UUID(),
                bookID: bookID,
                title: NSLocalizedString("reader.preview.chapter.title", comment: ""),
                startOffset: 0,
                endOffset: Self.sampleText.utf8.count,
                sortOrder: 0,
                source: .pseudo
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

    func fetchReadingHistory(limit: Int) async throws -> [ReadingHistoryItem] {
        let books = try await fetchBooks(scope: .all, sortOrder: .lastReadAt)
        return books.prefix(limit).map { book in
            ReadingHistoryItem(
                id: UUID(),
                book: book,
                chapterTitle: NSLocalizedString("reader.preview.chapter.title", comment: ""),
                offset: 0,
                readAt: Date()
            )
        }
    }

    func clearReadingHistory() async throws {}

    func fetchLibrarySettings() async throws -> LibrarySettings {
        .default
    }

    func saveLibrarySettings(_ settings: LibrarySettings) async throws {}

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

    func deleteBooks(ids: Set<UUID>) async throws {
    }
}
