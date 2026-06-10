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
        let bodyCandidateIndices = candidates.indices.filter {
            candidates[$0].kind != .special
        }
        if bodyCandidateIndices.isEmpty {
            return Self.pseudoChapters(for: text)
        }
        if let onlyBodyCandidateIndex = bodyCandidateIndices.first,
           bodyCandidateIndices.count == 1 {
            return Self.pseudoChaptersForSingleBodyCandidate(
                candidates,
                bodyCandidateIndex: onlyBodyCandidateIndex,
                totalByteLength: totalByteLength,
                in: text
            )
        }

        var chapters = Self.prefaceChapterIfNeeded(
            before: candidates.first,
            in: text
        )
        Self.appendRegexChapters(
            from: candidates.indices,
            candidates: candidates,
            totalByteLength: totalByteLength,
            to: &chapters
        )

        return chapters.isEmpty
            ? Self.pseudoChapters(for: text)
            : chapters
    }

    private static func pseudoChaptersForSingleBodyCandidate(
        _ candidates: [ChapterCandidate],
        bodyCandidateIndex: Int,
        totalByteLength: Int,
        in text: String
    ) -> [ImportedChapterDraft] {
        var chapters = Self.prefaceChapterIfNeeded(
            before: candidates.first,
            in: text
        )

        let prefixIndices = candidates.indices.filter { $0 < bodyCandidateIndex }
        Self.appendRegexChapters(
            from: prefixIndices,
            candidates: candidates,
            totalByteLength: totalByteLength,
            to: &chapters
        )

        let bodyCandidate = candidates[bodyCandidateIndex]
        let bodyEndOffset = candidates.indices.contains(bodyCandidateIndex + 1)
            ? candidates[bodyCandidateIndex + 1].startOffset
            : totalByteLength
        if bodyEndOffset > bodyCandidate.startOffset {
            chapters.append(
                contentsOf: Self.pseudoChapters(
                    for: text,
                    from: bodyCandidate.lineStartIndex,
                    startOffset: bodyCandidate.startOffset,
                    endOffset: bodyEndOffset,
                    startingSortOrder: chapters.count
                )
            )
        }

        let suffixIndices = candidates.indices.filter { $0 > bodyCandidateIndex }
        Self.appendRegexChapters(
            from: suffixIndices,
            candidates: candidates,
            totalByteLength: totalByteLength,
            to: &chapters
        )

        return chapters
    }

    private static func prefaceChapterIfNeeded(
        before firstCandidate: ChapterCandidate?,
        in text: String
    ) -> [ImportedChapterDraft] {
        guard let firstCandidate = firstCandidate,
              firstCandidate.startOffset > 0,
              Self.containsMeaningfulText(text[..<firstCandidate.lineStartIndex])
        else {
            return []
        }

        return [
            Self.chapter(
                title: Self.prefaceTitle,
                startOffset: 0,
                endOffset: firstCandidate.startOffset,
                sortOrder: 0,
                source: .regex
            )
        ]
    }

    private static func appendRegexChapters(
        from indices: Range<Array<ChapterCandidate>.Index>,
        candidates: [ChapterCandidate],
        totalByteLength: Int,
        to chapters: inout [ImportedChapterDraft]
    ) {
        for index in indices {
            let endOffset = candidates.indices.contains(index + 1)
                ? candidates[index + 1].startOffset
                : totalByteLength
            Self.appendRegexChapter(
                candidate: candidates[index],
                endOffset: endOffset,
                to: &chapters
            )
        }
    }

    private static func appendRegexChapters(
        from indices: [Array<ChapterCandidate>.Index],
        candidates: [ChapterCandidate],
        totalByteLength: Int,
        to chapters: inout [ImportedChapterDraft]
    ) {
        for index in indices {
            let endOffset = candidates.indices.contains(index + 1)
                ? candidates[index + 1].startOffset
                : totalByteLength
            Self.appendRegexChapter(
                candidate: candidates[index],
                endOffset: endOffset,
                to: &chapters
            )
        }
    }

    private static func appendRegexChapter(
        candidate: ChapterCandidate,
        endOffset: Int,
        to chapters: inout [ImportedChapterDraft]
    ) {
        guard endOffset > candidate.startOffset else {
            return
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
        Self.pseudoChapters(
            for: text,
            from: text.startIndex,
            startOffset: 0,
            endOffset: text.utf8.count,
            startingSortOrder: 0
        )
    }

    private static func pseudoChapters(
        for text: String,
        from rangeStartIndex: String.Index,
        startOffset rangeStartOffset: Int,
        endOffset rangeEndOffset: Int,
        startingSortOrder: Int
    ) -> [ImportedChapterDraft] {
        var chapters: [ImportedChapterDraft] = []
        var chapterStartIndex = rangeStartIndex
        var chapterStartOffset = rangeStartOffset

        while chapterStartOffset < rangeEndOffset {
            let remainingByteLength = rangeEndOffset - chapterStartOffset
            let sortOrder = startingSortOrder + chapters.count
            let titleNumber = chapters.count
            guard remainingByteLength > fallbackHardMaximumChapterByteLength else {
                chapters.append(
                    chapter(
                        title: pseudoChapterTitle(number: titleNumber),
                        startOffset: chapterStartOffset,
                        endOffset: rangeEndOffset,
                        sortOrder: sortOrder,
                        source: .pseudo
                    )
                )
                break
            }

            let chunkEnd = Self.fallbackChunkEnd(
                from: chapterStartIndex,
                startOffset: chapterStartOffset,
                rangeEndOffset: rangeEndOffset,
                in: text
            )
            guard chunkEnd.offset > chapterStartOffset else {
                chapters.append(
                    chapter(
                        title: pseudoChapterTitle(number: titleNumber),
                        startOffset: chapterStartOffset,
                        endOffset: rangeEndOffset,
                        sortOrder: sortOrder,
                        source: .pseudo
                    )
                )
                break
            }

            chapters.append(
                chapter(
                    title: pseudoChapterTitle(number: titleNumber),
                    startOffset: chapterStartOffset,
                    endOffset: chunkEnd.offset,
                    sortOrder: sortOrder,
                    source: .pseudo
                )
            )
            chapterStartIndex = chunkEnd.index
            chapterStartOffset = chunkEnd.offset
        }

        if chapters.isEmpty {
            chapters.append(
                chapter(
                    title: pseudoChapterTitle(number: 0),
                    startOffset: rangeStartOffset,
                    endOffset: rangeEndOffset,
                    sortOrder: startingSortOrder,
                    source: .pseudo
                )
            )
        }

        return Self.mergingShortTrailingPseudoChapter(chapters)
    }

    private static func fallbackChunkEnd(
        from startIndex: String.Index,
        startOffset: Int,
        rangeEndOffset: Int,
        in text: String
    ) -> (index: String.Index, offset: Int) {
        let targetOffset = min(
            startOffset + fallbackTargetChapterByteLength,
            rangeEndOffset
        )
        let scanEndOffset = min(
            startOffset + fallbackHardMaximumChapterByteLength,
            rangeEndOffset
        )

        var boundaries: [FallbackBoundary] = []
        var hardFallbackIndex = startIndex
        var hardFallbackOffset = startOffset
        var index = startIndex
        var offset = startOffset

        while index < text.endIndex, offset < scanEndOffset {
            let character = text[index]
            let nextIndex = text.index(after: index)
            let nextOffset = offset + String(character).utf8.count
            guard nextOffset <= scanEndOffset, nextOffset <= rangeEndOffset else {
                break
            }

            if nextOffset <= targetOffset {
                hardFallbackIndex = nextIndex
                hardFallbackOffset = nextOffset
            }

            if let priority = fallbackBoundaryPriority(for: character) {
                let boundary = Self.fallbackBoundary(
                    after: character,
                    nextIndex: nextIndex,
                    nextOffset: nextOffset,
                    priority: priority,
                    scanEndOffset: scanEndOffset,
                    rangeEndOffset: rangeEndOffset,
                    in: text
                )
                boundaries.append(
                    FallbackBoundary(
                        index: boundary.index,
                        offset: boundary.offset,
                        priority: priority
                    )
                )
            }

            index = nextIndex
            offset = nextOffset
        }

        if let boundary = Self.bestFallbackBoundary(
            in: boundaries,
            lowerOffset: max(
                startOffset + fallbackMinimumChapterByteLength,
                targetOffset - fallbackBoundarySearchWindowByteLength
            ),
            upperOffset: min(
                scanEndOffset,
                targetOffset + fallbackBoundarySearchWindowByteLength
            ),
            targetOffset: targetOffset,
            rangeEndOffset: rangeEndOffset
        ) {
            return (boundary.index, boundary.offset)
        }

        if let boundary = Self.bestFallbackBoundary(
            in: boundaries,
            lowerOffset: startOffset + fallbackMinimumChapterByteLength,
            upperOffset: scanEndOffset,
            targetOffset: targetOffset,
            rangeEndOffset: rangeEndOffset
        ) {
            return (boundary.index, boundary.offset)
        }

        if hardFallbackOffset > startOffset {
            return (hardFallbackIndex, hardFallbackOffset)
        }

        return (index, offset)
    }

    private static func fallbackBoundary(
        after _: Character,
        nextIndex: String.Index,
        nextOffset: Int,
        priority: Int,
        scanEndOffset: Int,
        rangeEndOffset: Int,
        in text: String
    ) -> (index: String.Index, offset: Int) {
        if priority == fallbackLineBreakPriority {
            return Self.boundaryAfterFollowingLineBreaks(
                from: nextIndex,
                offset: nextOffset,
                scanEndOffset: scanEndOffset,
                rangeEndOffset: rangeEndOffset,
                in: text
            )
        }

        return Self.boundaryAfterTrailingClosers(
            from: nextIndex,
            offset: nextOffset,
            scanEndOffset: scanEndOffset,
            rangeEndOffset: rangeEndOffset,
            in: text
        )
    }

    private static func boundaryAfterFollowingLineBreaks(
        from startIndex: String.Index,
        offset startOffset: Int,
        scanEndOffset: Int,
        rangeEndOffset: Int,
        in text: String
    ) -> (index: String.Index, offset: Int) {
        var index = startIndex
        var offset = startOffset

        while index < text.endIndex {
            let character = text[index]
            guard lineBreakByteLength(in: character) != nil else {
                break
            }

            let nextIndex = text.index(after: index)
            let nextOffset = offset + String(character).utf8.count
            guard nextOffset <= scanEndOffset, nextOffset <= rangeEndOffset else {
                break
            }

            index = nextIndex
            offset = nextOffset
        }

        return (index, offset)
    }

    private static func boundaryAfterTrailingClosers(
        from startIndex: String.Index,
        offset startOffset: Int,
        scanEndOffset: Int,
        rangeEndOffset: Int,
        in text: String
    ) -> (index: String.Index, offset: Int) {
        var index = startIndex
        var offset = startOffset

        while index < text.endIndex {
            let character = text[index]
            guard Self.isTrailingQuoteOrBracket(character) else {
                break
            }

            let nextIndex = text.index(after: index)
            let nextOffset = offset + String(character).utf8.count
            guard nextOffset <= scanEndOffset, nextOffset <= rangeEndOffset else {
                break
            }

            index = nextIndex
            offset = nextOffset
        }

        return (index, offset)
    }

    private static func bestFallbackBoundary(
        in boundaries: [FallbackBoundary],
        lowerOffset: Int,
        upperOffset: Int,
        targetOffset: Int,
        rangeEndOffset: Int
    ) -> FallbackBoundary? {
        for priority in fallbackBoundaryPriorities {
            let candidates = boundaries.filter {
                $0.priority == priority
                    && $0.offset >= lowerOffset
                    && $0.offset <= upperOffset
                    && Self.hasAcceptableTrailingLength(
                        after: $0.offset,
                        rangeEndOffset: rangeEndOffset
                    )
            }
            if let candidate = candidates.min(by: { lhs, rhs in
                let lhsDistance = abs(lhs.offset - targetOffset)
                let rhsDistance = abs(rhs.offset - targetOffset)
                if lhsDistance == rhsDistance {
                    return lhs.offset > rhs.offset
                }
                return lhsDistance < rhsDistance
            }) {
                return candidate
            }
        }

        return nil
    }

    private static func fallbackBoundaryPriority(for character: Character) -> Int? {
        if lineBreakByteLength(in: character) != nil {
            return fallbackLineBreakPriority
        }

        let scalars = String(character).unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return nil
        }

        switch scalar.value {
        case _ where fallbackSentenceEndingScalarValues.contains(scalar.value):
            return fallbackSentenceEndingPriority
        case _ where fallbackSemicolonScalarValues.contains(scalar.value):
            return fallbackSemicolonPriority
        case _ where fallbackCommaScalarValues.contains(scalar.value):
            return fallbackCommaPriority
        default:
            return nil
        }
    }

    private static func isTrailingQuoteOrBracket(_ character: Character) -> Bool {
        let scalars = String(character).unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else {
            return false
        }
        return fallbackTrailingQuoteAndBracketScalarValues.contains(scalar.value)
    }

    private static func hasAcceptableTrailingLength(
        after offset: Int,
        rangeEndOffset: Int
    ) -> Bool {
        let trailingLength = rangeEndOffset - offset
        return trailingLength == 0
            || trailingLength >= fallbackMinimumTrailingChapterByteLength
    }

    private static func mergingShortTrailingPseudoChapter(
        _ chapters: [ImportedChapterDraft]
    ) -> [ImportedChapterDraft] {
        guard chapters.count > 1,
              let trailingChapter = chapters.last,
              trailingChapter.endOffset - trailingChapter.startOffset < fallbackMinimumTrailingChapterByteLength
        else {
            return chapters
        }

        var mergedChapters = chapters
        let trailingEndOffset = trailingChapter.endOffset
        let previousIndex = mergedChapters.index(before: mergedChapters.index(before: mergedChapters.endIndex))
        mergedChapters[previousIndex].endOffset = trailingEndOffset
        mergedChapters.removeLast()
        return mergedChapters
    }

    private static func pseudoChapterTitle(number: Int) -> String {
        String(
            format: NSLocalizedString("chapter.pseudo.numbered", comment: ""),
            number + 1
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
    private static let fallbackTargetChapterByteLength = 9_000
    private static let fallbackBoundarySearchWindowByteLength = 1_500
    private static let fallbackMinimumChapterByteLength = 7_200
    private static let fallbackHardMaximumChapterByteLength = 13_500
    private static let fallbackMinimumTrailingChapterByteLength = 3_600
    private static let fallbackLineBreakPriority = 0
    private static let fallbackSentenceEndingPriority = 1
    private static let fallbackSemicolonPriority = 2
    private static let fallbackCommaPriority = 3
    private static let fallbackBoundaryPriorities = [
        fallbackLineBreakPriority,
        fallbackSentenceEndingPriority,
        fallbackSemicolonPriority,
        fallbackCommaPriority
    ]
    private static let fallbackSentenceEndingScalarValues: Set<UInt32> = [
        0x0021,
        0x002E,
        0x003F,
        0x3002,
        0xFF01,
        0xFF1F
    ]
    private static let fallbackSemicolonScalarValues: Set<UInt32> = [
        0x003B,
        0xFF1B
    ]
    private static let fallbackCommaScalarValues: Set<UInt32> = [
        0x002C,
        0xFF0C
    ]
    private static let fallbackTrailingQuoteAndBracketScalarValues: Set<UInt32> = [
        0x0022,
        0x0027,
        0x0029,
        0x005D,
        0x007D,
        0x2019,
        0x201D,
        0x3009,
        0x300B,
        0x300D,
        0x300F,
        0x3011,
        0xFF09
    ]
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

private struct FallbackBoundary {
    let index: String.Index
    let offset: Int
    let priority: Int
}
