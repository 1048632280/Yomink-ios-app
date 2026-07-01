import Foundation
import GRDB
import OSLog

extension Book {
    private static let rowLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
        category: "BookRow"
    )

    init?(row: Row) {
        let idString: String = row["id"]
        let importedAtString: String = row["importedAt"]
        let lastReadAtString: String? = row["lastReadAt"]
        let favoriteAtString: String? = row["favoriteAt"]
        let groupIDString: String? = row["groupId"]
        let progressPercentage: Double = row["progressPercentage"] ?? 0
        let lastReadAt = lastReadAtString.flatMap(DatabaseDateFormatter.date(from:))
        let favoriteAt = favoriteAtString.flatMap(DatabaseDateFormatter.date(from:))
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
        if favoriteAtString != nil, favoriteAt == nil {
            Self.rowLogger.warning("Dropped invalid favoriteAt for book row: id=\(idString, privacy: .public)")
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
            favoriteAt: favoriteAt,
            groupID: groupID,
            progressPercentage: min(max(progressPercentage, 0), 1),
            contentHash: row["contentHash"],
            sourcePath: row["sourcePath"]
        )
    }
}

extension BookGroup {
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

extension BookTag {
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
            name: row["name"],
            createdAt: createdAt
        )
    }
}

extension BookTagUsage {
    init?(row: Row) {
        guard let tag = BookTag(row: row) else {
            return nil
        }

        self.init(
            tag: tag,
            bookCount: row["bookCount"] ?? 0
        )
    }
}

extension Chapter {
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

extension ReadingProgress {
    init?(row: Row) {
        let bookIDString: String = row["bookId"]
        let chapterIDString: String? = row["chapterId"]
        let usesPageIndexValue: Int? = row["usesPageIndex"]

        guard let bookID = UUID(uuidString: bookIDString) else {
            return nil
        }

        self.init(
            bookID: bookID,
            chapterID: chapterIDString.flatMap(UUID.init(uuidString:)),
            chapterOffset: row["chapterOffset"],
            globalProgress: row["globalProgress"],
            pageIndex: row["pageIndex"],
            pageCount: row["pageCount"],
            usesPageIndex: (usesPageIndexValue ?? 0) == 1,
            paginationSignature: row["paginationSignature"]
        )
    }
}

extension Bookmark {
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

extension TextFilterRule {
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

extension SearchHistoryItem {
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

extension ReadingHistoryItem {
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
