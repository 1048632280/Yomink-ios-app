import Foundation
import GRDB

enum BookQuery {
    static let selectedColumns = "books.*, COALESCE(reading_progress.globalProgress, 0) AS progressPercentage"
    static let progressJoin = """
    LEFT JOIN reading_progress
        ON reading_progress.bookId = books.id
    """

    static func booksSQL(
        where whereClause: String? = nil,
        sortOrder: LibrarySettings.SortOrder? = nil,
        usesFavoriteDateForImportedAt: Bool = false,
        limit: Int? = nil
    ) -> String {
        var sql = """
        SELECT
            \(selectedColumns)
        FROM books
        \(progressJoin)
        """

        if let whereClause = whereClause {
            sql += "\nWHERE \(whereClause)"
        }
        if let sortOrder = sortOrder {
            sql += "\n\(orderClause(for: sortOrder, usesFavoriteDateForImportedAt: usesFavoriteDateForImportedAt))"
        }
        if let limit = limit {
            sql += "\nLIMIT \(limit)"
        }
        return sql
    }

    private static func orderClause(
        for sortOrder: LibrarySettings.SortOrder,
        usesFavoriteDateForImportedAt: Bool
    ) -> String {
        let importedAtColumn = usesFavoriteDateForImportedAt ? "books.favoriteAt" : "books.importedAt"
        switch sortOrder {
        case .lastReadAt:
            return "ORDER BY books.lastReadAt DESC, \(importedAtColumn) DESC"
        case .importedAt:
            return "ORDER BY \(importedAtColumn) DESC"
        }
    }
}

extension GRDBLibraryRepository {
    static func fetchBook(_ db: Database, contentHash: String) throws -> Book? {
        let normalizedHash = contentHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHash.isEmpty else {
            return nil
        }

        guard let row = try Row.fetchOne(
            db,
            sql: BookQuery.booksSQL(
                where: "books.contentHash = ?",
                sortOrder: .importedAt,
                limit: 1
            ),
            arguments: [normalizedHash]
        ) else {
            return nil
        }
        return Book(row: row)
    }
}
