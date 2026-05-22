import Foundation
import GRDB
import OSLog

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

    func fetchChapters(bookID: UUID) async throws -> [Chapter] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, bookId, title, startOffset, endOffset, sortOrder
                FROM chapters
                WHERE bookId = ?
                ORDER BY sortOrder
                """,
                arguments: [bookID.uuidString]
            )
            return rows.compactMap(Chapter.init(row:))
        }
    }

    func fetchReadingProgress(bookID: UUID) async throws -> ReadingProgress? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT bookId, chapterId, chapterOffset, globalProgress
                FROM reading_progress
                WHERE bookId = ?
                """,
                arguments: [bookID.uuidString]
            ) else {
                return nil
            }
            return ReadingProgress(row: row)
        }
    }

    func saveReadingProgress(_ progress: ReadingProgress) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO reading_progress (
                    bookId, chapterId, chapterOffset, globalProgress, updatedAt
                )
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(bookId) DO UPDATE SET
                    chapterId = excluded.chapterId,
                    chapterOffset = excluded.chapterOffset,
                    globalProgress = excluded.globalProgress,
                    updatedAt = excluded.updatedAt
                """,
                arguments: [
                    progress.bookID.uuidString,
                    progress.chapterID?.uuidString,
                    progress.chapterOffset,
                    min(max(progress.globalProgress, 0), 1),
                    DatabaseDateFormatter.string(from: Date())
                ]
            )
        }
    }

    func markBookOpened(id: UUID, at date: Date) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE books
                SET lastReadAt = ?
                WHERE id = ?
                """,
                arguments: [
                    DatabaseDateFormatter.string(from: date),
                    id.uuidString
                ]
            )
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
            chapterId: draft.chapters.first?.id.uuidString,
            chapterOffset: 0,
            globalProgress: 0,
            updatedAt: DatabaseDateFormatter.string(from: draft.importedAt)
        )

        return try await database.writer.write { db in
            try record.insert(db)
            for chapter in draft.chapters {
                try db.execute(
                    sql: """
                    INSERT INTO chapters (
                        id, bookId, title, startOffset, endOffset, sortOrder
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chapter.id.uuidString,
                        draft.id.uuidString,
                        chapter.title,
                        chapter.startOffset,
                        chapter.endOffset,
                        chapter.sortOrder
                    ]
                )
            }
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
    static let rowLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
        category: "BookRow"
    )

    init?(row: Row) {
        let idString: String = row["id"]
        let importedAtString: String = row["importedAt"]
        let lastReadAtString: String? = row["lastReadAt"]
        let groupIDString: String? = row["groupId"]
        let progressPercentage: Double = row["progressPercentage"] ?? 0
        let lastReadAt = lastReadAtString.flatMap(DatabaseDateFormatter.date(from:))
        let groupID = groupIDString.flatMap(UUID.init(uuidString:))
        guard
            let id = UUID(uuidString: idString),
            let importedAt = DatabaseDateFormatter.date(from: importedAtString)
        else {
            Self.rowLogger.warning("Dropped invalid book row: id=\(idString, privacy: .public)")
            return nil
        }
        if lastReadAtString != nil, lastReadAt == nil {
            Self.rowLogger.warning("Dropped invalid lastReadAt for book row: id=\(idString, privacy: .public)")
        }
        if groupIDString != nil, groupID == nil {
            Self.rowLogger.warning("Dropped invalid groupId for book row: id=\(idString, privacy: .public)")
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
            lastReadAt: lastReadAt,
            groupID: groupID,
            progressPercentage: min(max(progressPercentage, 0), 1),
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

private extension Chapter {
    init?(row: Row) {
        let idString: String = row["id"]
        let bookIDString: String = row["bookId"]

        guard
            let id = UUID(uuidString: idString),
            let bookID = UUID(uuidString: bookIDString)
        else {
            return nil
        }

        self.init(
            id: id,
            bookID: bookID,
            title: row["title"],
            startOffset: row["startOffset"],
            endOffset: row["endOffset"],
            sortOrder: row["sortOrder"]
        )
    }
}

private extension ReadingProgress {
    init?(row: Row) {
        let bookIDString: String = row["bookId"]
        let chapterIDString: String? = row["chapterId"]

        guard let bookID = UUID(uuidString: bookIDString) else {
            return nil
        }

        self.init(
            bookID: bookID,
            chapterID: chapterIDString.flatMap(UUID.init(uuidString:)),
            chapterOffset: row["chapterOffset"],
            globalProgress: row["globalProgress"]
        )
    }
}
