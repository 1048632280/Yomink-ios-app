import Foundation

struct Bookmark: Identifiable, Equatable, Sendable {
    let id: UUID
    var bookID: UUID
    var chapterID: UUID?
    var offset: Int {
        didSet {
            offset = max(offset, 0)
        }
    }
    var preview: String
    var createdAt: Date

    init(
        id: UUID,
        bookID: UUID,
        chapterID: UUID?,
        offset: Int,
        preview: String,
        createdAt: Date
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterID = chapterID
        self.offset = max(offset, 0)
        self.preview = preview
        self.createdAt = createdAt
    }
}
