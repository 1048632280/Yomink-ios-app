import Foundation

protocol LibraryRepository: Sendable {
    func fetchBooks(scope: LibraryScope, sortOrder: LibrarySettings.SortOrder) async throws -> [Book]
    func findBook(contentHash: String) async throws -> Book?
    func searchBooks(keyword: String, sortOrder: LibrarySettings.SortOrder) async throws -> [Book]
    func fetchSearchHistory() async throws -> [SearchHistoryItem]
    func saveSearchKeyword(_ keyword: String) async throws
    func clearSearchHistory() async throws
    func fetchGroups() async throws -> [BookGroup]
    func createGroup(name: String) async throws -> BookGroup
    func renameGroup(id: UUID, name: String) async throws
    func deleteGroup(id: UUID) async throws
    func reorderGroups(ids: [UUID]) async throws
    func moveBooks(ids: Set<UUID>, to groupID: UUID?) async throws
    func updateBookDetails(
        id: UUID,
        title: String,
        author: String?,
        intro: String?
    ) async throws -> Book
    func fetchChapters(bookID: UUID) async throws -> [Chapter]
    func fetchBookmarks(bookID: UUID) async throws -> [Bookmark]
    func createBookmark(
        bookID: UUID,
        chapterID: UUID?,
        offset: Int,
        preview: String
    ) async throws -> Bookmark
    func deleteBookmark(id: UUID) async throws
    func fetchFilterRules(bookID: UUID) async throws -> [TextFilterRule]
    func createFilterRule(
        bookID: UUID,
        source: String,
        replacement: String?
    ) async throws -> TextFilterRule
    func updateFilterRule(
        id: UUID,
        source: String,
        replacement: String?
    ) async throws -> TextFilterRule
    func deleteFilterRule(id: UUID) async throws
    func fetchReadingProgress(bookID: UUID) async throws -> ReadingProgress?
    func saveReadingProgress(_ progress: ReadingProgress) async throws
    func fetchReadingHistory(limit: Int) async throws -> [ReadingHistoryItem]
    func deleteReadingHistory(bookID: UUID) async throws
    func clearReadingHistory() async throws
    func fetchLibrarySettings() async throws -> LibrarySettings
    func saveLibrarySettings(_ settings: LibrarySettings) async throws
    func fetchRandomPickerState() async throws -> RandomPickerState
    func saveRandomPickerState(_ state: RandomPickerState) async throws
    func fetchReaderSettings() async throws -> ReaderSettings
    func saveReaderSettings(_ settings: ReaderSettings) async throws
    func markBookOpened(id: UUID, at date: Date) async throws
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book

    /// Removes database rows only.
    /// Caller should drop on-disk artifacts before deleting rows so failures remain retryable.
    func deleteBook(id: UUID) async throws
    func deleteBooks(ids: Set<UUID>) async throws
}
