import Foundation
import SwiftUI
import UIKit

enum BookExportService {
    struct ExportedFiles {
        let urls: [URL]
        let directoryURL: URL
    }

    struct ExportedFile {
        let url: URL
        let directoryURL: URL
    }

    static func exportURL(for book: Book, fileStore: AppFileStore) throws -> ExportedFile {
        let export = try exportURLs(for: [book], fileStore: fileStore)
        return ExportedFile(url: export.urls[0], directoryURL: export.directoryURL)
    }

    static func exportURLs(for books: [Book], fileStore: AppFileStore) throws -> ExportedFiles {
        let exportDirectory = exportDirectoryURL()
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )

        var usedFileNames: Set<String> = []
        let urls = try books.map { book in
            let contentURL = try fileStore.url(forRelativePath: book.sourcePath)
            let destinationURL = exportDirectory.appendingPathComponent(
                exportFileName(for: book, contentURL: contentURL, usedFileNames: &usedFileNames),
                isDirectory: false
            )
            try FileManager.default.copyItem(at: contentURL, to: destinationURL)
            return destinationURL
        }
        return ExportedFiles(urls: urls, directoryURL: exportDirectory)
    }

    static func cleanupExportDirectory(_ directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func exportDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkExports-\(UUID().uuidString)", isDirectory: true)
    }

    private static func exportFileName(
        for book: Book,
        contentURL: URL,
        usedFileNames: inout Set<String>
    ) -> String {
        let rawTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedExportFileName(
            rawTitle.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : rawTitle
        )
        let contentExtension = contentURL.pathExtension
        let fileExtension = contentExtension.isEmpty ? "txt" : contentExtension
        var candidate = "\(baseName).\(fileExtension)"
        var suffix = 2
        while usedFileNames.contains(candidate) {
            candidate = "\(baseName) \(suffix).\(fileExtension)"
            suffix += 1
        }
        usedFileNames.insert(candidate)
        return candidate
    }

    private static func sanitizedExportFileName(_ fileName: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = fileName
            .components(separatedBy: illegalCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : sanitized
    }
}

