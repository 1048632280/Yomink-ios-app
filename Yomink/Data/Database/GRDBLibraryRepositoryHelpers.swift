import Foundation
import GRDB

extension GRDBLibraryRepository {
    static func normalizedGroupName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("sidebar.untitledGroup", comment: "") : trimmed
    }

    static func normalizedTagName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("tags.untitled", comment: "") : trimmed
    }

    static func normalizedBookTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    static func normalizedOptionalText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func likePattern(for keyword: String) -> String {
        let escaped = keyword
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    static func fetchTag(_ db: Database, name: String) throws -> BookTag? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
            SELECT id, name, createdAt
            FROM tags
            WHERE name = ? COLLATE NOCASE
            LIMIT 1
            """,
            arguments: [name]
        ) else {
            return nil
        }
        return BookTag(row: row)
    }

    static func bookNotFoundError() -> NSError {
        NSError(
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

    static func normalizedImportedChapter(
        _ chapter: ImportedChapterDraft,
        fallbackSortOrder: Int
    ) -> ImportedChapterDraft {
        let startOffset = max(chapter.startOffset, 0)
        let endOffset = max(chapter.endOffset, startOffset)
        let sortOrder = chapter.sortOrder >= 0 ? chapter.sortOrder : fallbackSortOrder
        return ImportedChapterDraft(
            id: chapter.id,
            title: chapter.title,
            startOffset: startOffset,
            endOffset: endOffset,
            sortOrder: sortOrder,
            source: chapter.source
        )
    }
}
