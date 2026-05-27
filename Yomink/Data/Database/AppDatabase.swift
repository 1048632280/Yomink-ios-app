import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: DatabaseWriter

    init(fileStore: AppFileStore) throws {
        self.writer = try Self.makeWriter(path: fileStore.databaseURL.path)
        try migrate()
    }

    private init(writer: DatabaseWriter) throws {
        self.writer = writer
        try migrate()
    }

    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try AppDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    private static func makeWriter(path: String) throws -> DatabaseWriter {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        return try DatabasePool(
            path: path,
            configuration: configuration
        )
    }

    private func migrate() throws {
        let migrator = Self.makeMigrator()
        try migrator.migrate(writer)
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_core_tables") { db in
            try db.execute(sql: """
            CREATE TABLE book_groups (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                sortOrder INTEGER NOT NULL,
                createdAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE TABLE books (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                author TEXT,
                intro TEXT,
                fileName TEXT NOT NULL,
                fileSize INTEGER NOT NULL,
                encoding TEXT,
                wordCount INTEGER NOT NULL DEFAULT 0,
                importedAt TEXT NOT NULL,
                lastReadAt TEXT,
                groupId TEXT REFERENCES book_groups(id) ON DELETE SET NULL,
                importSourceDisplayPath TEXT,
                sourceBookmark BLOB,
                sourcePath TEXT NOT NULL,
                normalizedPath TEXT
            )
            """)

            try db.execute(sql: """
            CREATE INDEX books_importedAt_index
            ON books(importedAt)
            """)

            try db.execute(sql: """
            CREATE INDEX books_lastReadAt_index
            ON books(lastReadAt)
            """)

            try db.execute(sql: """
            CREATE TABLE reading_progress (
                bookId TEXT PRIMARY KEY NOT NULL
                    REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT REFERENCES chapters(id) ON DELETE SET NULL,
                chapterOffset INTEGER NOT NULL DEFAULT 0,
                globalProgress REAL NOT NULL DEFAULT 0,
                updatedAt TEXT NOT NULL
            )
            """)

            // Chapter offsets are UTF-8 byte offsets in normalized.txt:
            // startOffset is inclusive and endOffset is exclusive.
            try db.execute(sql: """
            CREATE TABLE chapters (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                startOffset INTEGER NOT NULL,
                endOffset INTEGER NOT NULL,
                sortOrder INTEGER NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE INDEX chapters_book_sort_index
            ON chapters(bookId, sortOrder)
            """)

            try db.execute(sql: """
            CREATE INDEX reading_progress_book_chapter_index
            ON reading_progress(bookId, chapterId)
            """)

            try db.execute(sql: """
            CREATE TABLE bookmarks (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT REFERENCES chapters(id) ON DELETE SET NULL,
                offset INTEGER NOT NULL,
                preview TEXT NOT NULL,
                createdAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE INDEX bookmarks_book_created_index
            ON bookmarks(bookId, createdAt)
            """)

            try db.execute(sql: """
            CREATE INDEX bookmarks_book_chapter_index
            ON bookmarks(bookId, chapterId)
            """)

            try db.execute(sql: """
            CREATE TABLE search_history (
                id TEXT PRIMARY KEY NOT NULL,
                keyword TEXT NOT NULL,
                createdAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE UNIQUE INDEX search_history_keyword_index
            ON search_history(keyword)
            """)

            try db.execute(sql: """
            CREATE TABLE filter_rules (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT REFERENCES books(id) ON DELETE CASCADE,
                source TEXT NOT NULL,
                replacement TEXT,
                createdAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE INDEX filter_rules_book_index
            ON filter_rules(bookId)
            """)

            try db.execute(sql: """
            CREATE TABLE reading_history (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT REFERENCES chapters(id) ON DELETE SET NULL,
                offset INTEGER NOT NULL,
                readAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE INDEX reading_history_book_readAt_index
            ON reading_history(bookId, readAt)
            """)

            try db.execute(sql: """
            CREATE INDEX reading_history_book_chapter_index
            ON reading_history(bookId, chapterId)
            """)

            try db.execute(sql: """
            CREATE TABLE app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)
        }

        migrator.registerMigration("v2_add_chapter_source") { db in
            try db.execute(sql: """
            ALTER TABLE chapters
            ADD COLUMN source TEXT NOT NULL DEFAULT 'pseudo'
            """)
        }

        migrator.registerMigration("v3_add_book_content_hash") { db in
            try db.execute(sql: """
            ALTER TABLE books
            ADD COLUMN contentHash TEXT
            """)

            try db.execute(sql: """
            CREATE INDEX books_contentHash_index
            ON books(contentHash)
            """)
        }

        return migrator
    }
}
