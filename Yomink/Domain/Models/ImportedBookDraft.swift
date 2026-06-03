import Foundation

struct ImportedBookDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    var author: String?
    var intro: String?
    var fileName: String
    var fileSize: Int64 {
        didSet {
            fileSize = max(fileSize, 0)
        }
    }
    var encoding: String
    var wordCount: Int {
        didSet {
            wordCount = max(wordCount, 0)
        }
    }
    var contentHash: String
    var chapters: [ImportedChapterDraft]
    var importedAt: Date
    var importSourceDisplayPath: String?
    var sourcePath: String

    init(
        id: UUID,
        title: String,
        author: String?,
        intro: String?,
        fileName: String,
        fileSize: Int64,
        encoding: String,
        wordCount: Int,
        contentHash: String,
        chapters: [ImportedChapterDraft],
        importedAt: Date,
        importSourceDisplayPath: String?,
        sourcePath: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.intro = intro
        self.fileName = fileName
        self.fileSize = max(fileSize, 0)
        self.encoding = encoding
        self.wordCount = max(wordCount, 0)
        self.contentHash = contentHash
        self.chapters = chapters
        self.importedAt = importedAt
        self.importSourceDisplayPath = importSourceDisplayPath
        self.sourcePath = sourcePath
    }
}

struct ImportedChapterDraft: Equatable, Sendable {
    let id: UUID
    var title: String
    /// UTF-8 byte offset in the canonical content file, inclusive.
    var startOffset: Int {
        didSet {
            startOffset = max(startOffset, 0)
            endOffset = max(endOffset, startOffset)
        }
    }
    /// UTF-8 byte offset in the canonical content file, exclusive.
    var endOffset: Int {
        didSet {
            endOffset = max(endOffset, startOffset)
        }
    }
    var sortOrder: Int {
        didSet {
            sortOrder = max(sortOrder, 0)
        }
    }
    var source: ChapterSource

    init(
        id: UUID,
        title: String,
        startOffset: Int,
        endOffset: Int,
        sortOrder: Int,
        source: ChapterSource
    ) {
        let normalizedStartOffset = max(startOffset, 0)
        self.id = id
        self.title = title
        self.startOffset = normalizedStartOffset
        self.endOffset = max(endOffset, normalizedStartOffset)
        self.sortOrder = max(sortOrder, 0)
        self.source = source
    }
}
