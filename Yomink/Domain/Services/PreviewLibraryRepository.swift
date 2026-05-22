import Foundation

struct PreviewLibraryRepository: LibraryRepository {
    func fetchBooks() async throws -> [Book] {
        [
            Book(
                id: UUID(uuidString: "4D52E7FE-A7ED-41F1-8C49-55C3E22B6B48") ?? UUID(),
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
                sourcePath: "Books/sample/source.txt",
                normalizedPath: "Books/sample/normalized.txt"
            )
        ]
    }

    func fetchGroups() async throws -> [BookGroup] {
        []
    }

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
