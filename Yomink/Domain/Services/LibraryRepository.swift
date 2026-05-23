import Foundation

protocol LibraryRepository: Sendable {
    func fetchBooks(scope: LibraryScope, sortOrder: LibrarySettings.SortOrder) async throws -> [Book]
    func searchBooks(keyword: String, sortOrder: LibrarySettings.SortOrder) async throws -> [Book]
    func fetchSearchHistory() async throws -> [SearchHistoryItem]
    func saveSearchKeyword(_ keyword: String) async throws
    func clearSearchHistory() async throws
    func fetchGroups() async throws -> [BookGroup]
    func createGroup(name: String) async throws -> BookGroup
    func renameGroup(id: UUID, name: String) async throws
    func deleteGroup(id: UUID) async throws
    func moveBooks(ids: Set<UUID>, to groupID: UUID?) async throws
    func fetchChapters(bookID: UUID) async throws -> [Chapter]
    func fetchReadingProgress(bookID: UUID) async throws -> ReadingProgress?
    func saveReadingProgress(_ progress: ReadingProgress) async throws
    func fetchReadingHistory(limit: Int) async throws -> [ReadingHistoryItem]
    func clearReadingHistory() async throws
    func fetchLibrarySettings() async throws -> LibrarySettings
    func saveLibrarySettings(_ settings: LibrarySettings) async throws
    func fetchReaderSettings() async throws -> ReaderSettings
    func saveReaderSettings(_ settings: ReaderSettings) async throws
    func markBookOpened(id: UUID, at date: Date) async throws
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book

    /// Removes database rows only.
    /// Caller must invoke AppFileStore.removeBookFiles(id:) to drop on-disk artifacts.
    func deleteBook(id: UUID) async throws
    func deleteBooks(ids: Set<UUID>) async throws
}
