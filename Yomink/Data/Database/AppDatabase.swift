import Foundation
import GRDB

final class AppDatabase {
    let writer: DatabaseWriter

    init(fileStore: AppFileStore) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        writer = try DatabaseQueue(
            path: fileStore.databaseURL.path,
            configuration: configuration
        )

        var migrator = Self.makeMigrator()
        try migrator.migrate(writer)
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_core_tables") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS book_groups (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                sortOrder INTEGER NOT NULL,
                createdAt TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS books (
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
                sourcePath TEXT NOT NULL,
                normalizedPath TEXT
            );

            CREATE INDEX IF NOT EXISTS books_importedAt_index
            ON books(importedAt);

            CREATE INDEX IF NOT EXISTS books_lastReadAt_index
            ON books(lastReadAt);

            CREATE TABLE IF NOT EXISTS reading_progress (
                bookId TEXT PRIMARY KEY NOT NULL
                    REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT,
                chapterOffset INTEGER NOT NULL DEFAULT 0,
                globalProgress REAL NOT NULL DEFAULT 0,
                updatedAt TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS chapters (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                startOffset INTEGER NOT NULL,
                endOffset INTEGER NOT NULL,
                sortOrder INTEGER NOT NULL
            );

            CREATE INDEX IF NOT EXISTS chapters_book_sort_index
            ON chapters(bookId, sortOrder);

            CREATE TABLE IF NOT EXISTS bookmarks (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT,
                offset INTEGER NOT NULL,
                preview TEXT NOT NULL,
                createdAt TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS bookmarks_book_created_index
            ON bookmarks(bookId, createdAt);

            CREATE TABLE IF NOT EXISTS search_history (
                id TEXT PRIMARY KEY NOT NULL,
                keyword TEXT NOT NULL,
                createdAt TEXT NOT NULL
            );

            CREATE UNIQUE INDEX IF NOT EXISTS search_history_keyword_index
            ON search_history(keyword);

            CREATE TABLE IF NOT EXISTS filter_rules (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT REFERENCES books(id) ON DELETE CASCADE,
                source TEXT NOT NULL,
                replacement TEXT,
                createdAt TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS filter_rules_book_index
            ON filter_rules(bookId);

            CREATE TABLE IF NOT EXISTS reading_history (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                chapterId TEXT,
                offset INTEGER NOT NULL,
                readAt TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS reading_history_book_readAt_index
            ON reading_history(bookId, readAt);

            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            );
            """)
        }

        return migrator
    }
}

