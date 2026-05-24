import Foundation

struct ChapterIndexer: Sendable {
    func indexChapters(
        for text: String
    ) -> [ImportedChapterDraft] {
        let candidates = Self.chapterCandidates(in: text)
        guard candidates.isEmpty == false else {
            return Self.pseudoChapters(for: text)
        }

        let totalByteLength = text.utf8.count
        var chapters: [ImportedChapterDraft] = []

        if let firstCandidate = candidates.first,
           firstCandidate.startOffset > 0,
           Self.containsMeaningfulText(text[..<firstCandidate.lineStartIndex]) {
            chapters.append(
                Self.chapter(
                    title: Self.prefaceTitle,
                    startOffset: 0,
                    endOffset: firstCandidate.startOffset,
                    sortOrder: chapters.count,
                    source: .regex
                )
            )
        }

        for (index, candidate) in candidates.enumerated() {
            let endOffset = candidates.indices.contains(index + 1)
                ? candidates[index + 1].startOffset
                : totalByteLength

            guard endOffset > candidate.startOffset else {
                continue
            }

            chapters.append(
                Self.chapter(
                    title: candidate.title,
                    startOffset: candidate.startOffset,
                    endOffset: endOffset,
                    sortOrder: chapters.count,
                    source: .regex
                )
            )
        }

        return chapters.isEmpty
            ? Self.pseudoChapters(for: text)
            : chapters
    }

    private static func chapterCandidates(in text: String) -> [ChapterCandidate] {
        var candidates: [ChapterCandidate] = []
        var lineStartIndex = text.startIndex
        var lineStartOffset = 0

        while lineStartIndex < text.endIndex {
            var lineEndIndex = lineStartIndex
            while lineEndIndex < text.endIndex,
                  text[lineEndIndex] != "\n",
                  text[lineEndIndex] != "\r" {
                lineEndIndex = text.index(after: lineEndIndex)
            }

            let rawLine = String(text[lineStartIndex..<lineEndIndex])
            if let kind = Self.chapterTitleKind(rawLine) {
                candidates.append(
                    ChapterCandidate(
                        title: rawLine.trimmingCharacters(in: .whitespacesAndNewlines),
                        startOffset: lineStartOffset,
                        lineStartIndex: lineStartIndex,
                        kind: kind
                    )
                )
            }

            var nextLineStartIndex = lineEndIndex
            var newlineByteLength = 0
            if nextLineStartIndex < text.endIndex {
                let newline = text[nextLineStartIndex]
                if newline == "\r" {
                    newlineByteLength += 1
                    nextLineStartIndex = text.index(after: nextLineStartIndex)
                    if nextLineStartIndex < text.endIndex,
                       text[nextLineStartIndex] == "\n" {
                        newlineByteLength += 1
                        nextLineStartIndex = text.index(after: nextLineStartIndex)
                    }
                } else if newline == "\n" {
                    newlineByteLength += 1
                    nextLineStartIndex = text.index(after: nextLineStartIndex)
                }
            }

            lineStartOffset += rawLine.utf8.count + newlineByteLength
            lineStartIndex = nextLineStartIndex
        }

        return Self.filterNumberedListFalsePositives(candidates)
    }

    private static func chapterTitleKind(_ rawLine: String) -> ChapterCandidate.Kind? {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.isEmpty == false,
              trimmedLine.count < maximumTitleCharacterCount,
              !endsWithSentencePunctuation(trimmedLine)
        else {
            return nil
        }

        let matchingLine = normalizedLineForMatching(trimmedLine)
        let range = NSRange(matchingLine.startIndex..<matchingLine.endIndex, in: matchingLine)
        return titleExpressions.first { titleExpression in
            titleExpression.expression.firstMatch(in: matchingLine, options: [], range: range) != nil
        }?.kind
    }

    private static func filterNumberedListFalsePositives(
        _ candidates: [ChapterCandidate]
    ) -> [ChapterCandidate] {
        let numberedCount = candidates.filter { $0.kind == .numbered }.count
        guard numberedCount > 0 else {
            return candidates
        }

        let hasRegularCandidate = candidates.contains { $0.kind == .regular }
        let shouldKeepNumberedCandidates = numberedCount >= minimumNumberedTitleCandidates
            || !hasRegularCandidate
        guard !shouldKeepNumberedCandidates else {
            return candidates
        }

        return candidates.filter { $0.kind != .numbered }
    }

    private static func endsWithSentencePunctuation(_ line: String) -> Bool {
        let scalars = line.unicodeScalars
        var endIndex = scalars.endIndex

        while endIndex > scalars.startIndex {
            let previousIndex = scalars.index(before: endIndex)
            guard trailingQuoteAndBracketScalars.contains(scalars[previousIndex]) else {
                break
            }
            endIndex = previousIndex
        }

        guard endIndex > scalars.startIndex else {
            return false
        }

        let lastMeaningfulScalar = scalars[scalars.index(before: endIndex)]
        return sentenceEndingScalars.contains(lastMeaningfulScalar)
    }

    private static func containsMeaningfulText(_ text: Substring) -> Bool {
        text.unicodeScalars.contains { !$0.properties.isWhitespace }
    }

    private static func normalizedLineForMatching(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
    }

    private static func pseudoChapters(for text: String) -> [ImportedChapterDraft] {
        var chapters: [ImportedChapterDraft] = []
        var chapterStartOffset = 0
        var currentOffset = 0

        for character in text {
            let characterByteCount = String(character).utf8.count
            if currentOffset > chapterStartOffset,
               currentOffset + characterByteCount - chapterStartOffset > pseudoChapterByteLength {
                let sortOrder = chapters.count
                chapters.append(
                    chapter(
                        title: pseudoChapterTitle(sortOrder: sortOrder),
                        startOffset: chapterStartOffset,
                        endOffset: currentOffset,
                        sortOrder: sortOrder,
                        source: .pseudo
                    )
                )
                chapterStartOffset = currentOffset
            }
            currentOffset += characterByteCount
        }

        let sortOrder = chapters.count
        chapters.append(
            chapter(
                title: pseudoChapterTitle(sortOrder: sortOrder),
                startOffset: chapterStartOffset,
                endOffset: currentOffset,
                sortOrder: sortOrder,
                source: .pseudo
            )
        )

        return chapters
    }

    private static func pseudoChapterTitle(sortOrder: Int) -> String {
        String(
            format: NSLocalizedString("chapter.pseudo.numbered", comment: ""),
            sortOrder + 1
        )
    }

    private static func chapter(
        title: String,
        startOffset: Int,
        endOffset: Int,
        sortOrder: Int,
        source: ChapterSource
    ) -> ImportedChapterDraft {
        ImportedChapterDraft(
            id: UUID(),
            title: title,
            startOffset: startOffset,
            endOffset: endOffset,
            sortOrder: sortOrder,
            source: source
        )
    }

    private static func makeExpression(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid chapter title expression: \(pattern)")
        }
    }

    private static func makeTitleExpressions() -> [TitleExpression] {
        [
            TitleExpression(
                expression: makeExpression(#"^\s*第\s*([0-9零〇一二两三四五六七八九十百千万]+(?:\s*[0-9零〇一二两三四五六七八九十百千万]+)*)\s*[章回节折卷部篇集]\s*(.*)$"#),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*卷\s*([0-9零〇一二两三四五六七八九十百千万]+(?:\s*[0-9零〇一二两三四五六七八九十百千万]+)*)\s*(.*)$"#),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*Chapter\s+\d+.*$"#, options: [.caseInsensitive]),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*\d+[\.\、]\s*.+$"#),
                kind: .numbered
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*(前言|引子|序|序言|序章|楔子|后记)(\s+.*|[:：].*)?$"#),
                kind: .special
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*番外\s*.*$"#),
                kind: .special
            )
        ]
    }

    private static let titleExpressions: [TitleExpression] = makeTitleExpressions()
    private static let prefaceTitle = NSLocalizedString("chapter.preface", comment: "")
    private static let maximumTitleCharacterCount = 50
    private static let minimumNumberedTitleCandidates = 3
    private static let pseudoChapterByteLength = 128 * 1_024
    private static let sentenceEndingScalars = Set("。！？!?".unicodeScalars)
    private static let trailingQuoteAndBracketScalars = Set("\"'”’」』》）)]}".unicodeScalars)
}

private struct TitleExpression {
    let expression: NSRegularExpression
    let kind: ChapterCandidate.Kind
}

private struct ChapterCandidate {
    enum Kind {
        case regular
        case numbered
        case special
    }

    let title: String
    let startOffset: Int
    let lineStartIndex: String.Index
    let kind: Kind
}
