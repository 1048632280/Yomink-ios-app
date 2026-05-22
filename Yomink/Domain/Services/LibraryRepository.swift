import Foundation

protocol LibraryRepository {
    func fetchBooks() async throws -> [Book]
    func fetchGroups() async throws -> [BookGroup]
}

