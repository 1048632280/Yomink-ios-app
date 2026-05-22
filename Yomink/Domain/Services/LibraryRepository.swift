import Foundation

protocol LibraryRepository: Sendable {
    func fetchBooks() async throws -> [Book]
    func fetchGroups() async throws -> [BookGroup]
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book

    /// Deletes database rows only. Book files remain the caller/FileStore responsibility.
    func deleteBook(id: UUID) async throws
}
