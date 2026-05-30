import Foundation
import XCTest
@testable import Yomink

final class ChapterIndexerTests: XCTestCase {
    private let maxChapterBytes = 128 * 1_024

    func testRegexChapterLargerThanLimitIsSplit() {
        let body = String(repeating: "a", count: 300 * 1_024)
        let chapters = ChapterIndexer().indexChapters(for: "Chapter 1\n" + body)

        XCTAssertGreaterThan(chapters.count, 1)
        XCTAssertTrue(chapters.allSatisfy { $0.endOffset > $0.startOffset })
        XCTAssertLessThanOrEqual(
            chapters.map { $0.endOffset - $0.startOffset }.max() ?? 0,
            maxChapterBytes
        )
        XCTAssertEqual(chapters.map(\.sortOrder), Array(chapters.indices))
    }

    func testOversizedRegexChapterSplitsOnlyAtUTF8Boundaries() {
        let body = String(repeating: "\u{4F60}\u{597D}", count: 80 * 1_024)
        let text = "Chapter 1\n" + body
        let bytes = Array(text.utf8)
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertGreaterThan(chapters.count, 1)
        for chapter in chapters {
            let data = Data(bytes[chapter.startOffset..<chapter.endOffset])
            XCTAssertNotNil(String(data: data, encoding: .utf8))
        }
    }
}
