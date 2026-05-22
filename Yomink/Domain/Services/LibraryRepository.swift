import Foundation

protocol LibraryRepository {
    func fetchBooks() async throws -> [Book]
    func fetchGroups() async throws -> [BookGroup]
    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book
    func deleteBook(id: UUID) async throws
}
