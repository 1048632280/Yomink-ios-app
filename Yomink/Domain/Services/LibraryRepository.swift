import Foundation

protocol LibraryRepository: Sendable {
    func fetchBooks() async throws -> [Book]
    func fetchGroups() async throws -> [BookGroup]
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book

    /// Removes database rows only.
    /// Caller must invoke AppFileStore.removeBookFiles(id:) to drop on-disk artifacts.
    func deleteBook(id: UUID) async throws
}
