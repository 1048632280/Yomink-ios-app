import Foundation

struct ImportedBookDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String?
    var intro: String?
    var fileName: String
    var fileSize: Int64
    var encoding: String
    var wordCount: Int
    var contentHash: String
    var chapters: [ImportedChapterDraft]
    var importedAt: Date
    var importSourceDisplayPath: String?
    var sourcePath: String
}

struct ImportedChapterDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    /// UTF-8 byte offset in the canonical content file, inclusive.
    var startOffset: Int
    /// UTF-8 byte offset in the canonical content file, exclusive.
    var endOffset: Int
    var sortOrder: Int
    var source: ChapterSource
}
