import Foundation

protocol LibraryRepository: Sendable {
    func fetchBooks() async throws -> [Book]
    func fetchGroups() async throws -> [BookGroup]
    func fetchChapters(bookID: UUID) async throws -> [Chapter]
    func fetchReadingProgress(bookID: UUID) async throws -> ReadingProgress?
    func saveReadingProgress(_ progress: ReadingProgress) async throws
    func fetchReaderSettings() async throws -> ReaderSettings
    func saveReaderSettings(_ settings: ReaderSettings) async throws
    func markBookOpened(id: UUID, at date: Date) async throws
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book

    /// Removes database rows only.
    /// Caller must invoke AppFileStore.removeBookFiles(id:) to drop on-disk artifacts.
    func deleteBook(id: UUID) async throws
}
