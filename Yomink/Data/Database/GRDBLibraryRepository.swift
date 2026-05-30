import Foundation
import GRDB
import OSLog

struct GRDBLibraryRepository: LibraryRepository {
    private let database: AppDatabase
    private static let settingsLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
        category: "AppSettings"
    )

    init(database: AppDatabase) {
        self.database = database
    }

    func findBook(contentHash: String) async throws -> Book? {
        let normalizedHash = contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else {
            return nil
        }

        return try await database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    books.*,
                    COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
                FROM books
                LEFT JOIN reading_progress
                    ON reading_progress.bookId = books.id
                WHERE books.contentHash = ?
                ORDER BY books.importedAt DESC
                LIMIT 1
                """,
                arguments: [normalizedHash]
            ) else {
                return nil
            }
            return Book(row: row)
        }
    }

    func fetchBooks(
        scope: LibraryScope = .all,
        sortOrder: LibrarySettings.SortOrder = .lastReadAt
    ) async throws -> [Book] {
        try await database.writer.read { db in
            var sql = """
            SELECT
                books.*,
                COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
            FROM books
            LEFT JOIN reading_progress
                ON reading_progress.bookId = books.id
            """
            let arguments: StatementArguments

            switch scope {
            case .all:
                arguments = []
                break
            case .ungrouped:
                sql += "\nWHERE books.groupId IS NULL"
                arguments = []
            case let .group(groupID):
                sql += "\nWHERE books.groupId = ?"
                arguments = [groupID.uuidString]
            }

            switch sortOrder {
            case .lastReadAt:
                sql += "\nORDER BY books.lastReadAt DESC, books.importedAt DESC"
            case .importedAt:
                sql += "\nORDER BY books.importedAt DESC"
            }

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return rows.compactMap(Book.init(row:))
        }
    }

    func searchBooks(
        keyword: String,
        sortOrder: LibrarySettings.SortOrder
    ) async throws -> [Book] {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty else {
            return []
        }

        return try await database.writer.read { db in
            var sql = """
            SELECT
                books.*,
                COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
            FROM books
            LEFT JOIN reading_progress
                ON reading_progress.bookId = books.id
            WHERE books.title LIKE ? ESCAPE '\\'
            """

            switch sortOrder {
            case .lastReadAt:
                sql += "\nORDER BY books.lastReadAt DESC, books.importedAt DESC"
            case .importedAt:
                sql += "\nORDER BY books.importedAt DESC"
            }

            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: [Self.likePattern(for: normalizedKeyword)]
            )
            return rows.compactMap(Book.init(row:))
        }
    }

    func fetchSearchHistory() async throws -> [SearchHistoryItem] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, keyword, createdAt
                FROM search_history
                ORDER BY createdAt DESC
                LIMIT 20
                """
            )
            return rows.compactMap(SearchHistoryItem.init(row:))
        }
    }

    func saveSearchKeyword(_ keyword: String) async throws {
        let normalizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKeyword.isEmpty else {
            return
        }

        try await database.writer.write { db in
            let now = DatabaseDateFormatter.string(from: Date())
            try db.execute(
                sql: """
                INSERT INTO search_history (id, keyword, createdAt)
                VALUES (?, ?, ?)
                ON CONFLICT(keyword) DO UPDATE SET
                    createdAt = excluded.createdAt
                """,
                arguments: [
                    UUID().uuidString,
                    normalizedKeyword,
                    now
                ]
            )
        }
    }

    func clearSearchHistory() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM search_history")
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

    func createGroup(name: String) async throws -> BookGroup {
        let trimmedName = Self.normalizedGroupName(name)
        let id = UUID()
        let createdAt = Date()

        return try await database.writer.write { db in
            let nextSortOrder = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM book_groups"
            ) ?? 0)
            let record = BookGroupRecord(
                id: id.uuidString,
                name: trimmedName,
                sortOrder: nextSortOrder,
                createdAt: DatabaseDateFormatter.string(from: createdAt)
            )
            try record.insert(db)
            return BookGroup(
                id: id,
                name: trimmedName,
                sortOrder: nextSortOrder
            )
        }
    }

    func renameGroup(id: UUID, name: String) async throws {
        let trimmedName = Self.normalizedGroupName(name)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE book_groups
                SET name = ?
                WHERE id = ?
                """,
                arguments: [
                    trimmedName,
                    id.uuidString
                ]
            )
        }
    }

    func deleteGroup(id: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE books
                SET groupId = NULL
                WHERE groupId = ?
                """,
                arguments: [id.uuidString]
            )
            try BookGroupRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func reorderGroups(ids: [UUID]) async throws {
        try await database.writer.write { db in
            for (index, id) in ids.enumerated() {
                try db.execute(
                    sql: """
                    UPDATE book_groups
                    SET sortOrder = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        index,
                        id.uuidString
                    ]
                )
            }
        }
    }

    func moveBooks(ids: Set<UUID>, to groupID: UUID?) async throws {
        guard !ids.isEmpty else {
            return
        }

        try await database.writer.write { db in
            for bookID in ids {
                try db.execute(
                    sql: """
                    UPDATE books
                    SET groupId = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        groupID?.uuidString,
                        bookID.uuidString
                    ]
                )
            }
        }
    }

    func updateBookDetails(
        id: UUID,
        title: String,
        author: String?,
        intro: String?
    ) async throws -> Book {
        let normalizedTitle = Self.normalizedBookTitle(title)
        let normalizedAuthor = Self.normalizedOptionalText(author)
        let normalizedIntro = Self.normalizedOptionalText(intro)

        return try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE books
                SET title = ?, author = ?, intro = ?
                WHERE id = ?
                """,
                arguments: [
                    normalizedTitle,
                    normalizedAuthor,
                    normalizedIntro,
                    id.uuidString
                ]
            )

            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT
                    books.*,
                    COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
                FROM books
                LEFT JOIN reading_progress
                    ON reading_progress.bookId = books.id
                WHERE books.id = ?
                """,
                arguments: [id.uuidString]
            ),
                let book = Book(row: row)
            else {
                throw NSError(
                    domain: "Yomink.LibraryRepository",
                    code: 404,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString(
                            "library.error.bookNotFound",
                            comment: ""
                        )
                    ]
                )
            }

            return book
        }
    }

    func fetchChapters(bookID: UUID) async throws -> [Chapter] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, bookId, title, startOffset, endOffset, sortOrder, source
                FROM chapters
                WHERE bookId = ?
                ORDER BY sortOrder
                """,
                arguments: [bookID.uuidString]
            )
            return rows.compactMap(Chapter.init(row:))
        }
    }

    func fetchBookmarks(bookID: UUID) async throws -> [Bookmark] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, bookId, chapterId, offset, preview, createdAt
                FROM bookmarks
                WHERE bookId = ?
                ORDER BY createdAt DESC
                """,
                arguments: [bookID.uuidString]
            )
            return rows.compactMap(Bookmark.init(row:))
        }
    }

    func createBookmark(
        bookID: UUID,
        chapterID: UUID?,
        offset: Int,
        preview: String
    ) async throws -> Bookmark {
        let bookmark = Bookmark(
            id: UUID(),
            bookID: bookID,
            chapterID: chapterID,
            offset: max(offset, 0),
            preview: preview,
            createdAt: Date()
        )

        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO bookmarks (
                    id, bookId, chapterId, offset, preview, createdAt
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    bookmark.id.uuidString,
                    bookmark.bookID.uuidString,
                    bookmark.chapterID?.uuidString,
                    bookmark.offset,
                    bookmark.preview,
                    DatabaseDateFormatter.string(from: bookmark.createdAt)
                ]
            )
        }

        return bookmark
    }

    func deleteBookmark(id: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM bookmarks
                WHERE id = ?
                """,
                arguments: [id.uuidString]
            )
        }
    }

    func fetchFilterRules(bookID: UUID) async throws -> [TextFilterRule] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT id, bookId, source, replacement, createdAt
                FROM filter_rules
                WHERE bookId = ?
                ORDER BY createdAt ASC
                """,
                arguments: [bookID.uuidString]
            )
            return rows.compactMap(TextFilterRule.init(row:))
        }
    }

    func createFilterRule(
        bookID: UUID,
        source: String,
        replacement: String?
    ) async throws -> TextFilterRule {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else {
            throw LibraryRepositoryError.emptyFilterSource
        }

        let rule = TextFilterRule(
            id: UUID(),
            bookID: bookID,
            source: normalizedSource,
            replacement: Self.normalizedOptionalText(replacement),
            createdAt: Date()
        )

        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO filter_rules (
                    id, bookId, source, replacement, createdAt
                )
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    rule.id.uuidString,
                    rule.bookID.uuidString,
                    rule.source,
                    rule.replacement,
                    DatabaseDateFormatter.string(from: rule.createdAt)
                ]
            )
        }

        return rule
    }

    func updateFilterRule(
        id: UUID,
        source: String,
        replacement: String?
    ) async throws -> TextFilterRule {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSource.isEmpty else {
            throw LibraryRepositoryError.emptyFilterSource
        }

        let normalizedReplacement = Self.normalizedOptionalText(replacement)

        return try await database.writer.write { db in
            try db.execute(
                sql: """
                UPDATE filter_rules
                SET source = ?, replacement = ?
                WHERE id = ?
                """,
                arguments: [
                    normalizedSource,
                    normalizedReplacement,
                    id.uuidString
                ]
            )

            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT id, bookId, source, replacement, createdAt
                FROM filter_rules
                WHERE id = ?
                """,
                arguments: [id.uuidString]
            ),
                let rule = TextFilterRule(row: row)
            else {
                throw LibraryRepositoryError.filterRuleNotFound
            }

            return rule
        }
    }

    func deleteFilterRule(id: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM filter_rules
                WHERE id = ?
                """,
                arguments: [id.uuidString]
            )
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

    func fetchReadingHistory(limit: Int) async throws -> [ReadingHistoryItem] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT
                    reading_history.id AS historyId,
                    reading_history.offset,
                    reading_history.readAt,
                    chapters.title AS chapterTitle,
                    books.*,
                    COALESCE(reading_progress.globalProgress, 0) AS progressPercentage
                FROM reading_history
                INNER JOIN books
                    ON books.id = reading_history.bookId
                LEFT JOIN chapters
                    ON chapters.id = reading_history.chapterId
                LEFT JOIN reading_progress
                    ON reading_progress.bookId = books.id
                WHERE reading_history.id = (
                    SELECT latest.id
                    FROM reading_history latest
                    WHERE latest.bookId = reading_history.bookId
                    ORDER BY latest.readAt DESC, latest.id DESC
                    LIMIT 1
                )
                ORDER BY reading_history.readAt DESC
                LIMIT ?
                """,
                arguments: [max(limit, 1)]
            )
            return rows.compactMap(ReadingHistoryItem.init(row:))
        }
    }

    func clearReadingHistory() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM reading_history")
        }
    }

    func deleteReadingHistory(bookID: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                DELETE FROM reading_history
                WHERE bookId = ?
                """,
                arguments: [bookID.uuidString]
            )
        }
    }

    func fetchLibrarySettings() async throws -> LibrarySettings {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: """
                SELECT value
                FROM app_settings
                WHERE key = ?
                """,
                arguments: [LibrarySettings.storageKey]
            ) else {
                return .default
            }

            guard let data = value.data(using: .utf8) else {
                Self.settingsLogger.warning(
                    "Stored app setting is not valid UTF-8: key=\(LibrarySettings.storageKey, privacy: .public)"
                )
                return .default
            }

            do {
                return try JSONDecoder().decode(LibrarySettings.self, from: data)
            } catch {
                Self.settingsLogger.warning(
                    "Failed to decode app setting: key=\(LibrarySettings.storageKey, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                return .default
            }
        }
    }

    func saveLibrarySettings(_ settings: LibrarySettings) async throws {
        let data = try JSONEncoder().encode(settings)
        guard let value = String(data: data, encoding: .utf8) else {
            return
        }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value
                """,
                arguments: [
                    LibrarySettings.storageKey,
                    value
                ]
            )
        }
    }

    func fetchRandomPickerState() async throws -> RandomPickerState {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: """
                SELECT value
                FROM app_settings
                WHERE key = ?
                """,
                arguments: [RandomPickerState.storageKey]
            ) else {
                return .default
            }

            guard let data = value.data(using: .utf8) else {
                Self.settingsLogger.warning(
                    "Stored app setting is not valid UTF-8: key=\(RandomPickerState.storageKey, privacy: .public)"
                )
                return .default
            }

            do {
                return try JSONDecoder().decode(RandomPickerState.self, from: data).normalized
            } catch {
                Self.settingsLogger.warning(
                    "Failed to decode app setting: key=\(RandomPickerState.storageKey, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                return .default
            }
        }
    }

    func saveRandomPickerState(_ state: RandomPickerState) async throws {
        let normalizedState = state.normalized
        let data = try JSONEncoder().encode(normalizedState)
        guard let value = String(data: data, encoding: .utf8) else {
            return
        }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value
                """,
                arguments: [
                    RandomPickerState.storageKey,
                    value
                ]
            )
        }
    }

    func fetchReaderSettings() async throws -> ReaderSettings {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: """
                SELECT value
                FROM app_settings
                WHERE key = ?
                """,
                arguments: [ReaderSettings.storageKey]
            ) else {
                return .default
            }

            guard let data = value.data(using: .utf8) else {
                Self.settingsLogger.warning(
                    "Stored app setting is not valid UTF-8: key=\(ReaderSettings.storageKey, privacy: .public)"
                )
                return .default
            }

            do {
                return try JSONDecoder().decode(ReaderSettings.self, from: data).normalized
            } catch {
                Self.settingsLogger.warning(
                    "Failed to decode app setting: key=\(ReaderSettings.storageKey, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
                )
                return .default
            }
        }
    }

    func saveReaderSettings(_ settings: ReaderSettings) async throws {
        let normalizedSettings = settings.normalized
        let data = try JSONEncoder().encode(normalizedSettings)
        guard let value = String(data: data, encoding: .utf8) else {
            return
        }

        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO app_settings (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value
                """,
                arguments: [
                    ReaderSettings.storageKey,
                    value
                ]
            )
        }
    }

    func markBookOpened(id: UUID, at date: Date) async throws {
        try await database.writer.write { db in
            let progressRow = try Row.fetchOne(
                db,
                sql: """
                SELECT chapterId, chapterOffset
                FROM reading_progress
                WHERE bookId = ?
                """,
                arguments: [id.uuidString]
            )
            let chapterID: String? = progressRow?["chapterId"]
            let chapterOffset: Int64 = progressRow?["chapterOffset"] ?? 0
            let dateString = DatabaseDateFormatter.string(from: date)

            try db.execute(
                sql: """
                UPDATE books
                SET lastReadAt = ?
                WHERE id = ?
                """,
                arguments: [
                    dateString,
                    id.uuidString
                ]
            )

            try db.execute(
                sql: """
                INSERT INTO reading_history (id, bookId, chapterId, offset, readAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID().uuidString,
                    id.uuidString,
                    chapterID,
                    chapterOffset,
                    dateString
                ]
            )
        }
    }

    func insertImportedBook(_ draft: ImportedBookDraft) async throws -> Book {
        let record = BookRecord(
            id: draft.id.uuidString,
            title: draft.title,
            author: draft.author,
            intro: draft.intro,
            fileName: draft.fileName,
            fileSize: draft.fileSize,
            encoding: draft.encoding,
            wordCount: draft.wordCount,
            importedAt: DatabaseDateFormatter.string(from: draft.importedAt),
            lastReadAt: nil,
            groupId: nil,
            contentHash: draft.contentHash,
            importSourceDisplayPath: draft.importSourceDisplayPath,
            sourceBookmark: nil,
            sourcePath: draft.sourcePath
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
                        id, bookId, title, startOffset, endOffset, sortOrder, source
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chapter.id.uuidString,
                        draft.id.uuidString,
                        chapter.title,
                        chapter.startOffset,
                        chapter.endOffset,
                        chapter.sortOrder,
                        chapter.source.rawValue
                    ]
                )
            }
            try progress.insert(db)

            return Book(
                id: draft.id,
                title: draft.title,
                author: draft.author,
                intro: draft.intro,
                fileName: draft.fileName,
                fileSize: draft.fileSize,
                encoding: draft.encoding,
                wordCount: draft.wordCount,
                importedAt: draft.importedAt,
                lastReadAt: nil,
                groupID: nil,
                progressPercentage: 0,
                contentHash: draft.contentHash,
                sourcePath: draft.sourcePath
            )
        }
    }

    func deleteBook(id: UUID) async throws {
        _ = try await database.writer.write { db in
            try BookRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func deleteBooks(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else {
            return
        }

        try await database.writer.write { db in
            for id in ids {
                _ = try BookRecord.deleteOne(db, key: id.uuidString)
            }
        }
    }

    private static func normalizedGroupName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("sidebar.untitledGroup", comment: "") : trimmed
    }

    private static func normalizedBookTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private static func normalizedOptionalText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func likePattern(for keyword: String) -> String {
        let escaped = keyword
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
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
            contentHash: row["contentHash"],
            sourcePath: row["sourcePath"]
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
        let sourceRawValue: String = row["source"]

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
            sortOrder: row["sortOrder"],
            source: ChapterSource(rawValue: sourceRawValue) ?? .pseudo
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

private extension Bookmark {
    init?(row: Row) {
        let idString: String = row["id"]
        let bookIDString: String = row["bookId"]
        let chapterIDString: String? = row["chapterId"]
        let createdAtString: String = row["createdAt"]

        guard
            let id = UUID(uuidString: idString),
            let bookID = UUID(uuidString: bookIDString),
            let createdAt = DatabaseDateFormatter.date(from: createdAtString)
        else {
            return nil
        }

        self.init(
            id: id,
            bookID: bookID,
            chapterID: chapterIDString.flatMap(UUID.init(uuidString:)),
            offset: row["offset"],
            preview: row["preview"],
            createdAt: createdAt
        )
    }
}

private extension TextFilterRule {
    init?(row: Row) {
        let idString: String = row["id"]
        let bookIDString: String = row["bookId"]
        let createdAtString: String = row["createdAt"]

        guard
            let id = UUID(uuidString: idString),
            let bookID = UUID(uuidString: bookIDString),
            let createdAt = DatabaseDateFormatter.date(from: createdAtString)
        else {
            return nil
        }

        self.init(
            id: id,
            bookID: bookID,
            source: row["source"],
            replacement: row["replacement"],
            createdAt: createdAt
        )
    }
}

private extension SearchHistoryItem {
    init?(row: Row) {
        let idString: String = row["id"]
        let createdAtString: String = row["createdAt"]

        guard
            let id = UUID(uuidString: idString),
            let createdAt = DatabaseDateFormatter.date(from: createdAtString)
        else {
            return nil
        }

        self.init(
            id: id,
            keyword: row["keyword"],
            createdAt: createdAt
        )
    }
}

private extension ReadingHistoryItem {
    init?(row: Row) {
        let idString: String = row["historyId"]
        let readAtString: String = row["readAt"]

        guard
            let id = UUID(uuidString: idString),
            let readAt = DatabaseDateFormatter.date(from: readAtString),
            let book = Book(row: row)
        else {
            return nil
        }

        self.init(
            id: id,
            book: book,
            chapterTitle: row["chapterTitle"],
            offset: row["offset"],
            readAt: readAt
        )
    }
}
