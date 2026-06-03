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
        try repairLegacyOversizedChaptersIfNeeded()
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
            try db.execute(sql: """
            ALTER TABLE chapters
            ADD COLUMN source TEXT NOT NULL DEFAULT 'pseudo'
                CHECK (source IN ('regex', 'pseudo'))
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

    func repairLegacyOversizedChaptersIfNeeded() throws {
        guard let fileStore else {
            return
        }

        try writer.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    books.id AS bookId,
                    books.sourcePath AS sourcePath,
                    chapters.id AS chapterId,
                    chapters.title,
                    chapters.startOffset,
                    chapters.endOffset,
                    chapters.sortOrder,
                    chapters.source
                FROM chapters
                INNER JOIN books
                    ON books.id = chapters.bookId
                ORDER BY books.id, chapters.sortOrder, chapters.id
                """
            )
            let chapterRows = rows.compactMap(LegacyChapterRow.init(row:))
            guard chapterRows.isEmpty == false else {
                return
            }

            let groupedRows = Dictionary(grouping: chapterRows, by: { $0.bookID })
            for chapters in groupedRows.values {
                guard chapters.contains(where: { $0.byteLength > ChapterIndexer.oversizedChapterByteLength }),
                      let sourcePath = chapters.first?.sourcePath,
                      let plan = Self.makeRepairPlan(
                        sourcePath: sourcePath,
                        chapters: chapters,
                        fileStore: fileStore
                      )
                else {
                    continue
                }

                try Self.applyRepairPlan(plan, in: db)
            }
        }
    }

    private static func makeRepairPlan(
        sourcePath: String,
        chapters: [LegacyChapterRow],
        fileStore: AppFileStore
    ) -> BookChapterRepairPlan? {
        guard let sourceURL = try? fileStore.url(forRelativePath: sourcePath) else {
            return nil
        }

        let sortedChapters = chapters.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.chapterID.uuidString < rhs.chapterID.uuidString
            }
            return lhs.sortOrder < rhs.sortOrder
        }

        var splitSegmentsByChapterID: [UUID: [ChapterRepairSegment]] = [:]
        for chapter in sortedChapters where chapter.byteLength > ChapterIndexer.oversizedChapterByteLength {
            guard let text = try? Self.readChapterText(
                from: sourceURL,
                chapter: chapter
            ) else {
                return nil
            }

            let drafts = ChapterIndexer.splitOversizedChapters(
                [
                    ImportedChapterDraft(
                        id: UUID(),
                        title: chapter.title,
                        startOffset: 0,
                        endOffset: text.utf8.count,
                        sortOrder: 0,
                        source: chapter.source
                    )
                ],
                in: text
            )

            guard drafts.count > 1 else {
                return nil
            }

            let segments = drafts.enumerated().map { index, draft in
                ChapterRepairSegment(
                    id: index == 0 ? chapter.chapterID : draft.id,
                    title: draft.title,
                    startOffset: chapter.startOffset + draft.startOffset,
                    endOffset: chapter.startOffset + draft.endOffset,
                    source: draft.source
                )
            }
            splitSegmentsByChapterID[chapter.chapterID] = segments
        }

        guard splitSegmentsByChapterID.isEmpty == false else {
            return nil
        }

        return BookChapterRepairPlan(
            bookID: sortedChapters[0].bookID,
            chapters: sortedChapters,
            splitSegmentsByChapterID: splitSegmentsByChapterID
        )
    }

    private static func applyRepairPlan(
        _ plan: BookChapterRepairPlan,
        in db: Database
    ) throws {
        var insertedSegmentCount = 0
        for chapter in plan.chapters {
            guard let segments = plan.splitSegmentsByChapterID[chapter.chapterID],
                  segments.count > 1
            else {
                continue
            }

            let currentSortOrder = chapter.sortOrder + insertedSegmentCount
            let addedSegmentCount = segments.count - 1

            try db.execute(
                sql: """
                UPDATE chapters
                SET sortOrder = sortOrder + ?
                WHERE bookId = ?
                    AND sortOrder > ?
                """,
                arguments: [
                    addedSegmentCount,
                    plan.bookID.uuidString,
                    currentSortOrder
                ]
            )

            let firstSegment = segments[0]
            try db.execute(
                sql: """
                UPDATE chapters
                SET title = ?,
                    startOffset = ?,
                    endOffset = ?,
                    sortOrder = ?,
                    source = ?
                WHERE id = ?
                """,
                arguments: [
                    firstSegment.title,
                    firstSegment.startOffset,
                    firstSegment.endOffset,
                    currentSortOrder,
                    firstSegment.source.rawValue,
                    chapter.chapterID.uuidString
                ]
            )

            for (index, segment) in segments.enumerated().dropFirst() {
                try db.execute(
                    sql: """
                    INSERT INTO chapters (
                        id, bookId, title, startOffset, endOffset, sortOrder, source
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        segment.id.uuidString,
                        plan.bookID.uuidString,
                        segment.title,
                        segment.startOffset,
                        segment.endOffset,
                        currentSortOrder + index,
                        segment.source.rawValue
                    ]
                )
            }

            try Self.remapProgress(
                bookID: plan.bookID,
                chapter: chapter,
                segments: segments,
                in: db
            )
            try Self.remapBookmarks(
                bookID: plan.bookID,
                chapter: chapter,
                segments: segments,
                in: db
            )
            try Self.remapHistory(
                bookID: plan.bookID,
                chapter: chapter,
                segments: segments,
                in: db
            )

            insertedSegmentCount += addedSegmentCount
        }
    }

    private static func remapProgress(
        bookID: UUID,
        chapter: LegacyChapterRow,
        segments: [ChapterRepairSegment],
        in db: Database
    ) throws {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT chapterId, chapterOffset
            FROM reading_progress
            WHERE bookId = ?
            """,
            arguments: [bookID.uuidString]
        ) else {
            return
        }

        let chapterID: String? = row["chapterId"]
        guard chapterID == chapter.chapterID.uuidString else {
            return
        }

        let chapterOffset: Int = row["chapterOffset"]
        let (segment, segmentOffset) = Self.segment(
            containing: chapterOffset,
            in: segments,
            chapter: chapter
        )
        guard segment.id != chapter.chapterID || segmentOffset != chapterOffset else {
            return
        }

        try db.execute(
            sql: """
            UPDATE reading_progress
            SET chapterId = ?,
                chapterOffset = ?
            WHERE bookId = ?
            """,
            arguments: [
                segment.id.uuidString,
                segmentOffset,
                bookID.uuidString
            ]
        )
    }

    private static func remapBookmarks(
        bookID: UUID,
        chapter: LegacyChapterRow,
        segments: [ChapterRepairSegment],
        in db: Database
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, offset
            FROM bookmarks
            WHERE bookId = ?
                AND chapterId = ?
            """,
            arguments: [
                bookID.uuidString,
                chapter.chapterID.uuidString
            ]
        )

        for row in rows {
            let id: String = row["id"]
            let offset: Int = row["offset"]
            let (segment, segmentOffset) = Self.segment(
                containing: offset,
                in: segments,
                chapter: chapter
            )
            guard segment.id.uuidString != chapter.chapterID.uuidString
                || segmentOffset != offset
            else {
                continue
            }

            try db.execute(
                sql: """
                UPDATE bookmarks
                SET chapterId = ?,
                    offset = ?
                WHERE id = ?
                """,
                arguments: [
                    segment.id.uuidString,
                    segmentOffset,
                    id
                ]
            )
        }
    }

    private static func remapHistory(
        bookID: UUID,
        chapter: LegacyChapterRow,
        segments: [ChapterRepairSegment],
        in db: Database
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, offset
            FROM reading_history
            WHERE bookId = ?
                AND chapterId = ?
            """,
            arguments: [
                bookID.uuidString,
                chapter.chapterID.uuidString
            ]
        )

        for row in rows {
            let id: String = row["id"]
            let offset: Int = row["offset"]
            let (segment, segmentOffset) = Self.segment(
                containing: offset,
                in: segments,
                chapter: chapter
            )
            guard segment.id.uuidString != chapter.chapterID.uuidString
                || segmentOffset != offset
            else {
                continue
            }

            try db.execute(
                sql: """
                UPDATE reading_history
                SET chapterId = ?,
                    offset = ?
                WHERE id = ?
                """,
                arguments: [
                    segment.id.uuidString,
                    segmentOffset,
                    id
                ]
            )
        }
    }

    private static func segment(
        containing chapterOffset: Int,
        in segments: [ChapterRepairSegment],
        chapter: LegacyChapterRow
    ) -> (segment: ChapterRepairSegment, offset: Int) {
        let clampedOffset = min(max(chapterOffset, 0), max(chapter.byteLength - 1, 0))
        let absoluteOffset = chapter.startOffset + clampedOffset
        let segment = segments.last(where: {
            absoluteOffset >= $0.startOffset && absoluteOffset < $0.endOffset
        }) ?? segments[0]
        return (segment, max(absoluteOffset - segment.startOffset, 0))
    }

    private static func readChapterText(
        from sourceURL: URL,
        chapter: LegacyChapterRow
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(chapter.startOffset))
        let data = handle.readData(ofLength: chapter.byteLength)
        guard data.count == chapter.byteLength else {
            throw RepairError.incompleteContent
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RepairError.invalidUTF8Content
        }
        return text
    }

    private struct LegacyChapterRow {
        let bookID: UUID
        let sourcePath: String
        let chapterID: UUID
        let title: String
        let startOffset: Int
        let endOffset: Int
        let sortOrder: Int
        let source: ChapterSource

        var byteLength: Int {
            max(0, endOffset - startOffset)
        }

        init?(row: Row) {
            let bookIDString: String = row["bookId"]
            let sourcePath: String = row["sourcePath"]
            let chapterIDString: String = row["chapterId"]
            let sourceRawValue: String = row["source"]

            guard let bookID = UUID(uuidString: bookIDString),
                  let chapterID = UUID(uuidString: chapterIDString),
                  let source = ChapterSource(rawValue: sourceRawValue)
            else {
                return nil
            }

            self.bookID = bookID
            self.sourcePath = sourcePath
            self.chapterID = chapterID
            self.title = row["title"]
            self.startOffset = row["startOffset"]
            self.endOffset = row["endOffset"]
            self.sortOrder = row["sortOrder"]
            self.source = source
        }
    }

    private struct ChapterRepairSegment {
        let id: UUID
        let title: String
        let startOffset: Int
        let endOffset: Int
        let source: ChapterSource
    }

    private struct BookChapterRepairPlan {
        let bookID: UUID
        let chapters: [LegacyChapterRow]
        let splitSegmentsByChapterID: [UUID: [ChapterRepairSegment]]
    }

    private enum RepairError: Error {
        case incompleteContent
        case invalidUTF8Content
    }
}
