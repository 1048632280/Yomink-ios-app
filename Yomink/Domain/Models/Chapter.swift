import Foundation

enum ChapterSource: String, Codable, Equatable, Sendable {
    case regex
    case pseudo
}

struct Chapter: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var title: String
    var startOffset: Int {
        didSet {
            startOffset = max(startOffset, 0)
            endOffset = max(endOffset, startOffset)
        }
    }
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

    var byteLength: Int {
        max(0, endOffset - startOffset)
    }

    init(
        id: UUID,
        bookID: UUID,
        title: String,
        startOffset: Int,
        endOffset: Int,
        sortOrder: Int,
        source: ChapterSource
    ) {
        let normalizedStartOffset = max(startOffset, 0)
        self.id = id
        self.bookID = bookID
        self.title = title
        self.startOffset = normalizedStartOffset
        self.endOffset = max(endOffset, normalizedStartOffset)
        self.sortOrder = max(sortOrder, 0)
        self.source = source
    }
}
