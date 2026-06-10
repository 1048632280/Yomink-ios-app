import Foundation
import XCTest
@testable import Yomink

final class ChapterIndexerTests: XCTestCase {
    func testUnindexedTextFallsBackToApproximateChineseLengthPseudoChapters() {
        let text = String(repeating: "\u{4F60}", count: 9_000)
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.map(\.title), pseudoTitles(count: 3))
        XCTAssertTrue(chapters.allSatisfy { $0.endOffset > $0.startOffset })
        XCTAssertEqual(chapters.map { $0.endOffset - $0.startOffset }, [9_000, 9_000, 9_000])
        XCTAssertEqual(chapters.map(\.sortOrder), Array(chapters.indices))
    }

    func testSingleRecognizedBodyChapterFallsBackToNumberedPseudoChapters() {
        let body = String(repeating: "\u{4F60}", count: 6_000)
        let text = "Chapter 1\n" + body
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.map(\.title), pseudoTitles(count: 2))
        XCTAssertEqual(chapters.map(\.source), [.pseudo, .pseudo])
        XCTAssertEqual(chapters.map(\.sortOrder), Array(chapters.indices))
        XCTAssertEqual(chapters.first?.startOffset, 0)
        XCTAssertEqual(chapters.last?.endOffset, text.utf8.count)
    }

    func testPrefaceAndSingleRecognizedBodyKeepsPrefaceThenFallsBack() {
        let preface = "Preface text.\n"
        let body = String(repeating: "\u{4F60}", count: 6_000)
        let text = preface + "Chapter 1\n" + body
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.map(\.title), [prefaceTitle] + pseudoTitles(count: 2))
        XCTAssertEqual(chapters.map(\.source), [.regex, .pseudo, .pseudo])
        XCTAssertEqual(chapters.map(\.sortOrder), Array(chapters.indices))
        XCTAssertEqual(chapters[1].startOffset, preface.utf8.count)
        XCTAssertEqual(chapters.last?.endOffset, text.utf8.count)
    }

    func testMultipleRecognizedBodyChaptersAreNotFallbackSplit() {
        let firstBody = String(repeating: "\u{4F60}", count: 6_000)
        let secondBody = String(repeating: "\u{597D}", count: 6_000)
        let text = "Chapter 1\n" + firstBody + "\nChapter 2\n" + secondBody
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(chapters.map(\.source), [.regex, .regex])
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.last?.endOffset, text.utf8.count)
    }

    func testMultipleRecognizedBodyChaptersAreNotSplitByLegacyByteLimit() {
        let firstBody = String(repeating: "a", count: 300 * 1_024)
        let secondBody = String(repeating: "b", count: 300 * 1_024)
        let text = "Chapter 1\n" + firstBody + "\nChapter 2\n" + secondBody
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.last?.endOffset, text.utf8.count)
    }

    func testFallbackPrefersNearestLineBreakAroundTarget() {
        let left = String(repeating: "\u{4F60}", count: 2_950)
        let right = String(repeating: "\u{597D}", count: 3_050)
        let text = left + "\n" + right
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.first?.endOffset, left.utf8.count + "\n".utf8.count)
    }

    func testFallbackUsesSentencePunctuationWhenNoLineBreakExists() {
        let left = String(repeating: "\u{4F60}", count: 2_950)
        let right = String(repeating: "\u{597D}", count: 3_050)
        let text = left + "\u{3002}" + right
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.first?.endOffset, left.utf8.count + "\u{3002}".utf8.count)
    }

    func testFallbackDoesNotSplitCarriageReturnLineFeed() {
        let left = String(repeating: "\u{4F60}", count: 2_950)
        let right = String(repeating: "\u{597D}", count: 3_050)
        let text = left + "\r\n" + right
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.first?.endOffset, left.utf8.count + "\r\n".utf8.count)
    }

    func testFallbackChaptersSplitOnlyAtUTF8Boundaries() {
        let body = String(repeating: "\u{4F60}\u{597D}", count: 80 * 1_024)
        let text = body + String(repeating: "\u{1F642}", count: 100)
        let bytes = Array(text.utf8)
        let chapters = ChapterIndexer().indexChapters(for: text)

        XCTAssertGreaterThan(chapters.count, 1)
        for chapter in chapters {
            let data = Data(bytes[chapter.startOffset..<chapter.endOffset])
            XCTAssertNotNil(String(data: data, encoding: .utf8))
        }
    }

    private func pseudoTitles(count: Int) -> [String] {
        (1...count).map {
            String(
                format: NSLocalizedString("chapter.pseudo.numbered", comment: ""),
                $0
            )
        }
    }

    private var prefaceTitle: String {
        NSLocalizedString("chapter.preface", comment: "")
    }
}
