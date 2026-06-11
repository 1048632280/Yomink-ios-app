import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: DatabaseWriter
    private let fileStore: AppFileStore?

    init(fileStore: AppFileStore) throws {
        self.fileStore = fileStore
        self.writer = try Self.makeWriter(path: fileStore.databaseURL.path)
        try migrate()
    }

    private init(writer: DatabaseWriter, fileStore: AppFileStore?) throws {
        self.fileStore = fileStore
        self.writer = writer
        try migrate()
    }

    static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return try AppDatabase(writer: DatabaseQueue(configuration: configuration), fileStore: nil)
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
        try recoverStagedBookDeletionsIfNeeded()
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
                fileSize INTEGER NOT NULL CHECK (fileSize >= 0),
                encoding TEXT,
                wordCount INTEGER NOT NULL DEFAULT 0 CHECK (wordCount >= 0),
                importedAt TEXT NOT NULL,
                lastReadAt TEXT,
                groupId TEXT REFERENCES book_groups(id) ON DELETE SET NULL,
                importSourceDisplayPath TEXT,
                sourceBookmark BLOB,
                sourcePath TEXT NOT NULL
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
                chapterOffset INTEGER NOT NULL DEFAULT 0 CHECK (chapterOffset >= 0),
                globalProgress REAL NOT NULL DEFAULT 0 CHECK (globalProgress >= 0 AND globalProgress <= 1),
                updatedAt TEXT NOT NULL
            )
            """)

            // Chapter offsets are UTF-8 byte offsets in the canonical content file:
            // startOffset is inclusive and endOffset is exclusive.
            try db.execute(sql: """
            CREATE TABLE chapters (
                id TEXT PRIMARY KEY NOT NULL,
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                startOffset INTEGER NOT NULL CHECK (startOffset >= 0),
                endOffset INTEGER NOT NULL CHECK (endOffset >= startOffset),
                sortOrder INTEGER NOT NULL CHECK (sortOrder >= 0)
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
                offset INTEGER NOT NULL CHECK (offset >= 0),
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
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                source TEXT NOT NULL CHECK (length(trim(source)) > 0),
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
                offset INTEGER NOT NULL CHECK (offset >= 0),
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
            // Older iOS SQLite builds reject ADD COLUMN with a CHECK constraint.
            // v4 installs triggers that enforce the same valid values after migration.
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

        migrator.registerMigration("v4_add_data_bounds_guards") { db in
            try db.execute(sql: """
            UPDATE books
            SET fileSize = 0
            WHERE fileSize < 0
            """)

            try db.execute(sql: """
            UPDATE books
            SET wordCount = 0
            WHERE wordCount < 0
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET chapterOffset = 0
            WHERE chapterOffset < 0
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET globalProgress = 0
            WHERE globalProgress < 0
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET globalProgress = 1
            WHERE globalProgress > 1
            """)

            try db.execute(sql: """
            UPDATE chapters
            SET startOffset = 0
            WHERE startOffset < 0
            """)

            try db.execute(sql: """
            UPDATE chapters
            SET endOffset = startOffset
            WHERE endOffset < startOffset
            """)

            try db.execute(sql: """
            UPDATE chapters
            SET sortOrder = 0
            WHERE sortOrder < 0
            """)

            try db.execute(sql: """
            UPDATE chapters
            SET source = 'pseudo'
            WHERE source NOT IN ('regex', 'pseudo')
            """)

            try db.execute(sql: """
            UPDATE bookmarks
            SET offset = 0
            WHERE offset < 0
            """)

            try db.execute(sql: """
            DELETE FROM filter_rules
            WHERE bookId IS NULL
                OR length(trim(source)) = 0
            """)

            try db.execute(sql: """
            UPDATE filter_rules
            SET source = trim(source)
            """)

            try db.execute(sql: """
            UPDATE reading_history
            SET offset = 0
            WHERE offset < 0
            """)

            try db.execute(sql: """
            CREATE TRIGGER books_bounds_insert
            BEFORE INSERT ON books
            WHEN NEW.fileSize < 0
                OR NEW.wordCount < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid book bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER books_bounds_update
            BEFORE UPDATE OF fileSize, wordCount ON books
            WHEN NEW.fileSize < 0
                OR NEW.wordCount < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid book bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_progress_bounds_insert
            BEFORE INSERT ON reading_progress
            WHEN NEW.chapterOffset < 0
                OR NEW.globalProgress < 0
                OR NEW.globalProgress > 1
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading progress bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_progress_bounds_update
            BEFORE UPDATE OF chapterOffset, globalProgress ON reading_progress
            WHEN NEW.chapterOffset < 0
                OR NEW.globalProgress < 0
                OR NEW.globalProgress > 1
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading progress bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER chapters_bounds_insert
            BEFORE INSERT ON chapters
            WHEN NEW.startOffset < 0
                OR NEW.endOffset < NEW.startOffset
                OR NEW.sortOrder < 0
                OR NEW.source NOT IN ('regex', 'pseudo')
            BEGIN
                SELECT RAISE(ABORT, 'invalid chapter bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER chapters_bounds_update
            BEFORE UPDATE OF startOffset, endOffset, sortOrder, source ON chapters
            WHEN NEW.startOffset < 0
                OR NEW.endOffset < NEW.startOffset
                OR NEW.sortOrder < 0
                OR NEW.source NOT IN ('regex', 'pseudo')
            BEGIN
                SELECT RAISE(ABORT, 'invalid chapter bounds');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER bookmarks_bounds_insert
            BEFORE INSERT ON bookmarks
            WHEN NEW.offset < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid bookmark offset');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER bookmarks_bounds_update
            BEFORE UPDATE OF offset ON bookmarks
            WHEN NEW.offset < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid bookmark offset');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER filter_rules_bounds_insert
            BEFORE INSERT ON filter_rules
            WHEN NEW.bookId IS NULL
                OR length(trim(NEW.source)) = 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid filter rule');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER filter_rules_bounds_update
            BEFORE UPDATE OF bookId, source ON filter_rules
            WHEN NEW.bookId IS NULL
                OR length(trim(NEW.source)) = 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid filter rule');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_history_bounds_insert
            BEFORE INSERT ON reading_history
            WHEN NEW.offset < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading history offset');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_history_bounds_update
            BEFORE UPDATE OF offset ON reading_history
            WHEN NEW.offset < 0
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading history offset');
            END
            """)
        }

        migrator.registerMigration("v5_unique_book_content_hash") { db in
            try db.execute(sql: """
            DROP INDEX IF EXISTS books_contentHash_index
            """)

            try db.execute(sql: """
            UPDATE books
            SET contentHash = NULL
            WHERE contentHash IS NOT NULL
                AND rowid NOT IN (
                    SELECT MIN(rowid)
                    FROM books
                    WHERE contentHash IS NOT NULL
                    GROUP BY contentHash
                )
            """)

            try db.execute(sql: """
            CREATE UNIQUE INDEX books_contentHash_unique_index
            ON books(contentHash)
            """)
        }

        migrator.registerMigration("v6_create_tags") { db in
            try db.execute(sql: """
            CREATE TABLE tags (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL CHECK (length(trim(name)) > 0),
                createdAt TEXT NOT NULL
            )
            """)

            try db.execute(sql: """
            CREATE UNIQUE INDEX tags_name_unique_index
            ON tags(name COLLATE NOCASE)
            """)

            try db.execute(sql: """
            CREATE TABLE book_tags (
                bookId TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
                tagId TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                createdAt TEXT NOT NULL,
                PRIMARY KEY (bookId, tagId)
            )
            """)

            try db.execute(sql: """
            CREATE INDEX book_tags_book_index
            ON book_tags(bookId)
            """)

            try db.execute(sql: """
            CREATE INDEX book_tags_tag_book_index
            ON book_tags(tagId, bookId)
            """)
        }

        migrator.registerMigration("v7_add_reading_progress_page_snapshot") { db in
            try db.execute(sql: """
            ALTER TABLE reading_progress
            ADD COLUMN pageIndex INTEGER
            """)

            try db.execute(sql: """
            ALTER TABLE reading_progress
            ADD COLUMN pageCount INTEGER
            """)

            try db.execute(sql: """
            ALTER TABLE reading_progress
            ADD COLUMN usesPageIndex INTEGER NOT NULL DEFAULT 0
            """)

            try db.execute(sql: """
            ALTER TABLE reading_progress
            ADD COLUMN paginationSignature TEXT
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET pageIndex = NULL
            WHERE pageIndex IS NOT NULL
                AND pageIndex < 0
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET pageCount = NULL
            WHERE pageCount IS NOT NULL
                AND pageCount <= 0
            """)

            try db.execute(sql: """
            UPDATE reading_progress
            SET usesPageIndex = 0
            WHERE usesPageIndex NOT IN (0, 1)
                OR pageIndex IS NULL
                OR pageCount IS NULL
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_progress_page_snapshot_insert
            BEFORE INSERT ON reading_progress
            WHEN (NEW.pageIndex IS NOT NULL AND NEW.pageIndex < 0)
                OR (NEW.pageCount IS NOT NULL AND NEW.pageCount <= 0)
                OR NEW.usesPageIndex NOT IN (0, 1)
                OR (NEW.usesPageIndex = 1 AND (NEW.pageIndex IS NULL OR NEW.pageCount IS NULL))
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading progress page snapshot');
            END
            """)

            try db.execute(sql: """
            CREATE TRIGGER reading_progress_page_snapshot_update
            BEFORE UPDATE OF pageIndex, pageCount, usesPageIndex ON reading_progress
            WHEN (NEW.pageIndex IS NOT NULL AND NEW.pageIndex < 0)
                OR (NEW.pageCount IS NOT NULL AND NEW.pageCount <= 0)
                OR NEW.usesPageIndex NOT IN (0, 1)
                OR (NEW.usesPageIndex = 1 AND (NEW.pageIndex IS NULL OR NEW.pageCount IS NULL))
            BEGIN
                SELECT RAISE(ABORT, 'invalid reading progress page snapshot');
            END
            """)
        }

        return migrator
    }

    private func recoverStagedBookDeletionsIfNeeded() throws {
        guard let fileStore else {
            return
        }

        let bookIDs = try writer.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM books")
                .compactMap(UUID.init(uuidString:))
        }
        try fileStore.recoverStagedBookDeletions(validBookIDs: Set(bookIDs))
    }
}
