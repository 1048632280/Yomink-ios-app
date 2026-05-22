import Foundation
import GRDB

struct GRDBLibraryRepository: LibraryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchBooks() async throws -> [Book] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    books.*,
                    COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
                FROM books
                LEFT JOIN reading_progress
                    ON reading_progress.bookId = books.id
                ORDER BY books.lastReadAt DESC, books.importedAt DESC
                """
            )
            return rows.compactMap(Book.init(row:))
        }
    }

    func fetchGroups() async throws -> [BookGroup] {
        try await database.writer.read { db in
            let records = try BookGroupRecord
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
            return records.compactMap(BookGroup.init(record:))
        }
    }

    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book {
        let record = BookRecord(
            id: draft.id.uuidString,
            title: draft.title,
            author: nil,
            intro: nil,
            fileName: draft.fileName,
            fileSize: draft.fileSize,
            encoding: draft.encoding,
            wordCount: draft.wordCount,
            importedAt: DatabaseDateFormatter.string(from: draft.importedAt),
            lastReadAt: nil,
            groupId: nil,
            importSourceDisplayPath: draft.importSourceDisplayPath,
            sourceBookmark: nil,
            sourcePath: draft.sourcePath,
            normalizedPath: draft.normalizedPath
        )
        let progress = ReadingProgressRecord(
            bookId: draft.id.uuidString,
            chapterId: nil,
            chapterOffset: 0,
            globalProgress: 0,
            updatedAt: DatabaseDateFormatter.string(from: draft.importedAt)
        )

        return try await database.writer.write { db in
            try record.insert(db)
            try progress.insert(db)

            return Book(
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
    }

    func deleteBook(id: UUID) async throws {
        _ = try await database.writer.write { db in
            try BookRecord.deleteOne(db, key: id.uuidString)
        }
    }
}

private extension Book {
    init?(row: Row) {
        let idString: String = row["id"]
        let importedAtString: String = row["importedAt"]
        let lastReadAtString: String? = row["lastReadAt"]
        let groupIDString: String? = row["groupId"]
        let progressPercentage: Double = row["progressPercentage"] ?? 0
        guard
            let id = UUID(uuidString: idString),
            let importedAt = DatabaseDateFormatter.date(from: importedAtString)
        else {
            return nil
        }

        self.init(
            id: id,
            title: row["title"],
            author: row["author"],
            intro: row["intro"],
            fileName: row["fileName"],
            fileSize: row["fileSize"],
            encoding: row["encoding"],
            wordCount: row["wordCount"],
            importedAt: importedAt,
            lastReadAt: lastReadAtString.flatMap(DatabaseDateFormatter.date(from:)),
            groupID: groupIDString.flatMap(UUID.init(uuidString:)),
            progressPercentage: progressPercentage,
            sourcePath: row["sourcePath"],
            normalizedPath: row["normalizedPath"]
        )
    }
}

private extension BookGroup {
    init?(record: BookGroupRecord) {
        guard let id = UUID(uuidString: record.id) else {
            return nil
        }

        self.init(
            id: id,
            name: record.name,
            sortOrder: record.sortOrder
        )
    }
}
