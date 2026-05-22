import Foundation

struct ImportedBookDraft: Equatable {
    let id: UUID
    var title: String
    var fileName: String
    var fileSize: Int64
    var encoding: String
    var wordCount: Int
    var importedAt: Date
    var importSourceDisplayPath: String?
    var sourcePath: String
    var normalizedPath: String
}
