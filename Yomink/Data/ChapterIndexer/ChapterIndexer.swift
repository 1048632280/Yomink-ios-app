import Foundation

struct ChapterIndexer: Sendable {
    func indexChapters(
        for text: String,
        fallbackTitle title: String
    ) -> [ImportedChapterDraft] {
        let candidates = Self.chapterCandidates(in: text)
        guard candidates.isEmpty == false else {
            return Self.pseudoChapters(for: text, title: title)
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
            ? Self.pseudoChapters(for: text, title: title)
            : chapters
    }

    private static func chapterCandidates(in text: String) -> [ChapterCandidate] {
        let titleExpressions = makeTitleExpressions()
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
            if Self.isChapterTitleLine(rawLine, titleExpressions: titleExpressions) {
                candidates.append(
                    ChapterCandidate(
                        title: rawLine.trimmingCharacters(in: .whitespacesAndNewlines),
                        startOffset: lineStartOffset,
                        lineStartIndex: lineStartIndex
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

        return candidates
    }

    private static func isChapterTitleLine(
        _ rawLine: String,
        titleExpressions: [NSRegularExpression]
    ) -> Bool {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.isEmpty == false,
              trimmedLine.count < maximumTitleCharacterCount,
              !endsWithSentencePunctuation(trimmedLine)
        else {
            return false
        }

        let range = NSRange(trimmedLine.startIndex..<trimmedLine.endIndex, in: trimmedLine)
        return titleExpressions.contains { expression in
            expression.firstMatch(in: trimmedLine, options: [], range: range) != nil
        }
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

    private static func pseudoChapters(
        for text: String,
        title: String
    ) -> [ImportedChapterDraft] {
        var chapters: [ImportedChapterDraft] = []
        var chapterStartOffset = 0
        var currentOffset = 0

        for character in text {
            let characterByteCount = String(character).utf8.count
            if currentOffset > chapterStartOffset,
               currentOffset + characterByteCount - chapterStartOffset > pseudoChapterByteLength {
                chapters.append(
                    chapter(
                        title: title,
                        startOffset: chapterStartOffset,
                        endOffset: currentOffset,
                        sortOrder: chapters.count,
                        source: .pseudo
                    )
                )
                chapterStartOffset = currentOffset
            }
            currentOffset += characterByteCount
        }

        chapters.append(
            chapter(
                title: title,
                startOffset: chapterStartOffset,
                endOffset: currentOffset,
                sortOrder: chapters.count,
                source: .pseudo
            )
        )

        if chapters.count == 1 {
            return chapters
        }

        return chapters.map { chapter in
            var chapter = chapter
            chapter.title = "\(title) \(chapter.sortOrder + 1)"
            return chapter
        }
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

    private static func makeTitleExpressions() -> [NSRegularExpression] {
        [
            makeExpression(#"^\s*第\s*([0-9零〇一二两三四五六七八九十百千万]+)\s*[章回节折卷部篇集]\s*(.*)$"#),
            makeExpression(#"^\s*卷\s*([0-9零〇一二两三四五六七八九十百千万]+)\s*(.*)$"#),
            makeExpression(#"^\s*Chapter\s+\d+.*$"#, options: [.caseInsensitive]),
            makeExpression(#"^\s*\d+[\.\、]\s*.+$"#),
            makeExpression(#"^\s*(前言|引子|序|序言|序章|楔子|后记)(\s+.*|[:：].*)?$"#),
            makeExpression(#"^\s*番外\s*.*$"#)
        ]
    }

    private static let prefaceTitle = "序"
    private static let maximumTitleCharacterCount = 50
    private static let pseudoChapterByteLength = 128 * 1_024
    private static let sentenceEndingScalars = Set("。！？!?".unicodeScalars)
    private static let trailingQuoteAndBracketScalars = Set("\"'”’」』》）)]}".unicodeScalars)
}

private struct ChapterCandidate {
    let title: String
    let startOffset: Int
    let lineStartIndex: String.Index
}
