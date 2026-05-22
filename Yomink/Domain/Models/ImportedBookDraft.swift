import Foundation

struct ImportedBookDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    var fileName: String
    var fileSize: Int64
    var encoding: String
    var wordCount: Int
    var chapters: [ImportedChapterDraft]
    var importedAt: Date
    var importSourceDisplayPath: String?
    var sourcePath: String
    var normalizedPath: String
}

struct ImportedChapterDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    var startOffset: Int
    var endOffset: Int
    var sortOrder: Int
}
