import Foundation
import GRDB

struct GRDBLibraryRepository: LibraryRepository {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func fetchBooks() async throws -> [Book] {
        try database.writer.read { db in
            let records = try BookRecord
                .order(Column("lastReadAt").desc, Column("importedAt").desc)
                .fetchAll(db)
            return records.compactMap(Book.init(record:))
        }
    }

    func fetchGroups() async throws -> [BookGroup] {
        try database.writer.read { db in
            let records = try BookGroupRecord
                .order(Column("sortOrder"), Column("createdAt"))
                .fetchAll(db)
            return records.compactMap(BookGroup.init(record:))
        }
    }
}

private extension Book {
    init?(record: BookRecord) {
        guard
            let id = UUID(uuidString: record.id),
            let importedAt = DatabaseDateFormatter.date(from: record.importedAt)
        else {
            return nil
        }

        self.init(
            id: id,
            title: record.title,
            author: record.author,
            intro: record.intro,
            fileName: record.fileName,
            fileSize: record.fileSize,
            encoding: record.encoding,
            wordCount: record.wordCount,
            importedAt: importedAt,
            lastReadAt: record.lastReadAt.flatMap(DatabaseDateFormatter.date(from:)),
            groupID: record.groupId.flatMap(UUID.init(uuidString:)),
            progressPercentage: 0,
            sourcePath: record.sourcePath,
            normalizedPath: record.normalizedPath
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
