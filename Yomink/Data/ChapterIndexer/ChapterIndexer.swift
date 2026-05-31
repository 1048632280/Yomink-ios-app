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

        let indexedChapters = chapters.isEmpty
            ? Self.pseudoChapters(for: text)
            : chapters
        return Self.splitOversizedChapters(indexedChapters, in: text)
    }

    private static func chapterCandidates(in text: String) -> [ChapterCandidate] {
        var candidates: [ChapterCandidate] = []
        var lineStartIndex = text.startIndex
        var lineStartOffset = 0
        var lineByteLength = 0
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            guard let lineBreakByteLength = Self.lineBreakByteLength(in: character) else {
                lineByteLength += String(character).utf8.count
                index = text.index(after: index)
                continue
            }

            Self.appendChapterCandidateIfNeeded(
                text: text,
                lineStartIndex: lineStartIndex,
                lineEndIndex: index,
                lineStartOffset: lineStartOffset,
                to: &candidates
            )

            var newlineByteLength = lineBreakByteLength
            var nextLineStartIndex = text.index(after: index)
            if Self.isSingleCarriageReturn(character),
               nextLineStartIndex < text.endIndex,
               Self.isSingleLineFeed(text[nextLineStartIndex]) {
                newlineByteLength += String(text[nextLineStartIndex]).utf8.count
                nextLineStartIndex = text.index(after: nextLineStartIndex)
            }

            lineStartOffset += lineByteLength + newlineByteLength
            lineStartIndex = nextLineStartIndex
            lineByteLength = 0
            index = nextLineStartIndex
        }

        Self.appendChapterCandidateIfNeeded(
            text: text,
            lineStartIndex: lineStartIndex,
            lineEndIndex: text.endIndex,
            lineStartOffset: lineStartOffset,
            to: &candidates
        )

        return Self.filterNumberedListFalsePositives(candidates)
    }

    private static func appendChapterCandidateIfNeeded(
        text: String,
        lineStartIndex: String.Index,
        lineEndIndex: String.Index,
        lineStartOffset: Int,
        to candidates: inout [ChapterCandidate]
    ) {
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
    }

    private static func chapterTitleKind(_ rawLine: String) -> ChapterCandidate.Kind? {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.isEmpty == false,
              trimmedLine.count < maximumTitleCharacterCount
        else {
            return nil
        }

        let matchingLine = normalizedLineForMatching(trimmedLine)
        let range = NSRange(matchingLine.startIndex..<matchingLine.endIndex, in: matchingLine)
        guard let kind = titleExpressions.first(where: { titleExpression in
            titleExpression.expression.firstMatch(in: matchingLine, options: [], range: range) != nil
        })?.kind else {
            return nil
        }

        if kind == .numbered,
           endsWithSentencePunctuation(trimmedLine) {
            return nil
        }

        return kind
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
        var normalizedScalars = String.UnicodeScalarView()
        normalizedScalars.reserveCapacity(line.unicodeScalars.count)

        for scalar in line.unicodeScalars {
            normalizedScalars.append(
                scalar.properties.isWhitespace ? normalizedWhitespaceScalar : scalar
            )
        }

        return String(normalizedScalars)
    }

    private static func isLineBreakScalar(_ scalar: UnicodeScalar) -> Bool {
        lineBreakScalarValues.contains(scalar.value)
    }

    private static func lineBreakByteLength(in character: Character) -> Int? {
        var byteLength = 0
        var foundLineBreak = false

        for scalar in String(character).unicodeScalars {
            guard isLineBreakScalar(scalar) else {
                return nil
            }
            foundLineBreak = true
            byteLength += utf8ByteLength(of: scalar)
        }

        return foundLineBreak ? byteLength : nil
    }

    private static func isSingleCarriageReturn(_ character: Character) -> Bool {
        let scalars = String(character).unicodeScalars
        return scalars.count == 1
            && scalars.first?.value == carriageReturnScalarValue
    }

    private static func isSingleLineFeed(_ character: Character) -> Bool {
        let scalars = String(character).unicodeScalars
        return scalars.count == 1
            && scalars.first?.value == lineFeedScalarValue
    }

    private static func utf8ByteLength(of scalar: UnicodeScalar) -> Int {
        switch scalar.value {
        case 0...0x7F:
            return 1
        case 0x80...0x7FF:
            return 2
        case 0x800...0xFFFF:
            return 3
        default:
            return 4
        }
    }

    private static func pseudoChapters(for text: String) -> [ImportedChapterDraft] {
        var chapters: [ImportedChapterDraft] = []
        var chapterStartOffset = 0
        var currentOffset = 0

        for character in text {
            let characterByteCount = String(character).utf8.count
            if currentOffset > chapterStartOffset,
               currentOffset + characterByteCount - chapterStartOffset > oversizedChapterByteLength {
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

    static func splitOversizedChapters(
        _ chapters: [ImportedChapterDraft],
        in text: String
    ) -> [ImportedChapterDraft] {
        guard chapters.contains(where: { $0.endOffset - $0.startOffset > oversizedChapterByteLength }) else {
            return chapters
        }

        var splitChapters: [ImportedChapterDraft] = []
        var textIndex = text.startIndex
        var currentOffset = 0

        for chapter in chapters {
            Self.advance(
                index: &textIndex,
                offset: &currentOffset,
                to: chapter.startOffset,
                in: text
            )

            var startOffset = chapter.startOffset
            var startIndex = textIndex
            var partIndex = 0

            while chapter.endOffset - startOffset > oversizedChapterByteLength {
                let (endIndex, endOffset) = Self.chunkEnd(
                    from: startIndex,
                    startOffset: startOffset,
                    chapterEndOffset: chapter.endOffset,
                    in: text
                )
                splitChapters.append(
                    Self.chapter(
                        title: splitTitle(for: chapter.title, partIndex: partIndex),
                        startOffset: startOffset,
                        endOffset: endOffset,
                        sortOrder: splitChapters.count,
                        source: chapter.source
                    )
                )
                currentOffset = endOffset
                textIndex = endIndex
                startOffset = endOffset
                startIndex = endIndex
                partIndex += 1
            }

            guard startOffset < chapter.endOffset else {
                continue
            }

            splitChapters.append(
                Self.chapter(
                    title: splitTitle(for: chapter.title, partIndex: partIndex),
                    startOffset: startOffset,
                    endOffset: chapter.endOffset,
                    sortOrder: splitChapters.count,
                    source: chapter.source
                )
            )

            Self.advance(
                index: &textIndex,
                offset: &currentOffset,
                to: chapter.endOffset,
                in: text
            )
        }

        return splitChapters
    }

    private static func chunkEnd(
        from startIndex: String.Index,
        startOffset: Int,
        chapterEndOffset: Int,
        in text: String
    ) -> (String.Index, Int) {
        var index = startIndex
        var offset = startOffset

        while index < text.endIndex {
            let characterByteCount = String(text[index]).utf8.count
            let nextOffset = offset + characterByteCount
            guard nextOffset <= chapterEndOffset else {
                break
            }
            if offset > startOffset,
               nextOffset - startOffset > oversizedChapterByteLength {
                break
            }

            offset = nextOffset
            index = text.index(after: index)

            if offset - startOffset >= oversizedChapterByteLength {
                break
            }
        }

        return (index, offset)
    }

    private static func advance(
        index: inout String.Index,
        offset: inout Int,
        to targetOffset: Int,
        in text: String
    ) {
        while index < text.endIndex, offset < targetOffset {
            offset += String(text[index]).utf8.count
            index = text.index(after: index)
        }
    }

    private static func splitTitle(for title: String, partIndex: Int) -> String {
        guard partIndex > 0 else {
            return title
        }

        return "\(title) (\(partIndex + 1))"
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
        let optionalOpening = #"[【\[\(（「『《]?\s*"#
        let optionalClosing = #"\s*[】\]\)）」』》]?\s*"#
        let chineseNumber = #"[0-9０-９零〇一二两三四五六七八九十百千万]+(?:\s*[0-9０-９零〇一二两三四五六七八九十百千万]+)*"#
        let chineseChapterUnit = #"[章回节折卷部篇集话幕]"#
        let englishChapterNumber = #"(?:[0-9０-９]+|[IVXLCDM]+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)"#
        let specialTitle = #"(前言|引子|序|序言|序章|楔子|后记|尾声|终章|外传)"#
        return [
            TitleExpression(
                expression: makeExpression(#"^\s*"# + optionalOpening + #"第\s*("# + chineseNumber + #")\s*"# + chineseChapterUnit + #"\s*(.*?)"# + optionalClosing + #"$"#),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*"# + optionalOpening + #"卷\s*("# + chineseNumber + #")\s*(.*?)"# + optionalClosing + #"$"#),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*"# + optionalOpening + #"Chapter\s+"# + englishChapterNumber + #"(?:\s*[-:：\.\)]?\s*.*?)?"# + optionalClosing + #"$"#, options: [.caseInsensitive]),
                kind: .regular
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*(?:[0-9０-９]+|[零〇一二两三四五六七八九十百千万]+)[\.．、]\s*.+$"#),
                kind: .numbered
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*[\(（]?(?:[0-9０-９]+|[零〇一二两三四五六七八九十百千万]+)[\)）][\s\.．、]*.+$"#),
                kind: .numbered
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*"# + optionalOpening + specialTitle + #"(\s+.*|[:：].*)?"# + optionalClosing + #"$"#),
                kind: .special
            ),
            TitleExpression(
                expression: makeExpression(#"^\s*"# + optionalOpening + #"番外\s*.*"# + optionalClosing + #"$"#),
                kind: .special
            )
        ]
    }

    private static let titleExpressions: [TitleExpression] = makeTitleExpressions()
    private static let prefaceTitle = NSLocalizedString("chapter.preface", comment: "")
    private static let maximumTitleCharacterCount = 50
    private static let minimumNumberedTitleCandidates = 3
    static let oversizedChapterByteLength = 128 * 1_024
    private static let normalizedWhitespaceScalar = UnicodeScalar(" ")
    private static let lineFeedScalarValue: UInt32 = 0x000A
    private static let carriageReturnScalarValue: UInt32 = 0x000D
    private static let lineBreakScalarValues: Set<UInt32> = [
        lineFeedScalarValue,
        carriageReturnScalarValue,
        0x0085,
        0x2028,
        0x2029
    ]
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
