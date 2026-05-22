import Foundation

struct PreviewLibraryRepository: LibraryRepository {
    func fetchBooks() async throws -> [Book] {
        []
    }

    func fetchGroups() async throws -> [BookGroup] {
        []
    }
}

