import Foundation

struct ImportBookMetadata: Equatable, Sendable {
    var title: String
    var author: String?
    var intro: String?
}

struct ImportBookPreview: Equatable, Sendable {
    var sourceURL: URL
    var fileName: String
    var title: String
    var author: String?
    var intro: String?
}

enum ImportBatchProgressPhase: Equatable, Sendable {
    case scanning
    case downloading
    case importing
}

struct ImportBatchProgress: Equatable, Sendable {
    var phase: ImportBatchProgressPhase
    var processedCount: Int
    var totalCount: Int
    var currentFileName: String?
}

struct ImportBatchFailure: Equatable, Sendable {
    var fileName: String
    var errorDescription: String
}

struct ImportBatchSummary: Equatable, Sendable {
    var totalCount: Int
    var importedBooks: [Book]
    var duplicateBooks: [Book]
    var failures: [ImportBatchFailure]

    var importedCount: Int {
        importedBooks.count
    }

    var duplicateCount: Int {
        duplicateBooks.count
    }

    var failedCount: Int {
        failures.count
    }
}
