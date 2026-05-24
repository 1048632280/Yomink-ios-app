import Foundation

struct FilteredReaderText: Sendable {
    let displayText: String
    let originalByteOffsetsByUTF16Index: [Int]

    func originalByteOffset(atDisplayUTF16Index index: Int) -> Int {
        guard originalByteOffsetsByUTF16Index.isEmpty == false else {
            return 0
        }

        let safeIndex = min(max(index, 0), originalByteOffsetsByUTF16Index.count - 1)
        return originalByteOffsetsByUTF16Index[safeIndex]
    }

    func displayUTF16Index(containingOriginalByteOffset offset: Int) -> Int {
        guard originalByteOffsetsByUTF16Index.isEmpty == false else {
            return 0
        }

        let clampedOffset = max(offset, 0)
        var lowerBound = 0
        var upperBound = originalByteOffsetsByUTF16Index.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if originalByteOffsetsByUTF16Index[middle] < clampedOffset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        if lowerBound < originalByteOffsetsByUTF16Index.count,
           originalByteOffsetsByUTF16Index[lowerBound] == clampedOffset {
            var firstMatchingIndex = lowerBound
            while firstMatchingIndex > 0,
                  originalByteOffsetsByUTF16Index[firstMatchingIndex - 1] == clampedOffset {
                firstMatchingIndex -= 1
            }
            return firstMatchingIndex
        }

        return max(0, lowerBound - 1)
    }
}

enum ReaderTextFilter {
    static func apply(
        rules: [TextFilterRule],
        to originalText: String
    ) -> FilteredReaderText {
        let activeRules = rules.filter { !$0.source.isEmpty }
        guard activeRules.isEmpty == false else {
            return identityFilteredText(for: originalText)
        }

        var characters = originalText.map { character in
            FilteredCharacter(
                text: String(character),
                originalByteOffset: 0
            )
        }
        var offset = 0
        for index in characters.indices {
            characters[index].originalByteOffset = offset
            offset += characters[index].text.utf8.count
            characters[index].originalEndByteOffset = offset
        }

        for rule in activeRules {
            apply(rule: rule, to: &characters)
        }

        return filteredText(from: characters, fallbackEndOffset: offset)
    }

    private static func identityFilteredText(for text: String) -> FilteredReaderText {
        var offsets: [Int] = []
        offsets.reserveCapacity(text.utf16.count + 1)

        var offset = 0
        offsets.append(offset)
        for character in text {
            let characterText = String(character)
            let previousOffset = offset
            offset += characterText.utf8.count
            let utf16Length = characterText.utf16.count
            if utf16Length > 1 {
                offsets.append(
                    contentsOf: Array(repeating: previousOffset, count: utf16Length - 1)
                )
            }
            offsets.append(offset)
        }

        return FilteredReaderText(
            displayText: text,
            originalByteOffsetsByUTF16Index: offsets
        )
    }

    private static func apply(
        rule: TextFilterRule,
        to characters: inout [FilteredCharacter]
    ) {
        let sourceCharacters = Array(rule.source)
        guard sourceCharacters.isEmpty == false,
              characters.isEmpty == false
        else {
            return
        }

        let replacement = rule.replacement ?? ""
        var result: [FilteredCharacter] = []
        result.reserveCapacity(characters.count)

        var index = 0
        while index < characters.count {
            if matches(sourceCharacters, in: characters, at: index) {
                let originalOffset = characters[index].originalByteOffset
                let originalEndOffset = characters[
                    min(index + sourceCharacters.count - 1, characters.count - 1)
                ].originalEndByteOffset
                for replacementCharacter in replacement {
                    result.append(
                        FilteredCharacter(
                            text: String(replacementCharacter),
                            originalByteOffset: originalOffset,
                            originalEndByteOffset: originalEndOffset
                        )
                    )
                }
                index += sourceCharacters.count
            } else {
                result.append(characters[index])
                index += 1
            }
        }

        characters = result
    }

    private static func matches(
        _ sourceCharacters: [Character],
        in characters: [FilteredCharacter],
        at index: Int
    ) -> Bool {
        guard index + sourceCharacters.count <= characters.count else {
            return false
        }

        for offset in sourceCharacters.indices where characters[index + offset].text != String(sourceCharacters[offset]) {
            return false
        }
        return true
    }

    private static func filteredText(
        from characters: [FilteredCharacter],
        fallbackEndOffset: Int
    ) -> FilteredReaderText {
        let visibleCharacters = characters.filter { !$0.text.isEmpty }
        guard visibleCharacters.isEmpty == false else {
            return FilteredReaderText(
                displayText: "",
                originalByteOffsetsByUTF16Index: [fallbackEndOffset]
            )
        }

        var textParts: [String] = []
        textParts.reserveCapacity(visibleCharacters.count)
        var offsets: [Int] = []
        offsets.reserveCapacity(visibleCharacters.count + 1)

        for character in visibleCharacters {
            textParts.append(character.text)
            let utf16Length = character.text.utf16.count
            offsets.append(
                contentsOf: Array(
                    repeating: character.originalByteOffset,
                    count: utf16Length
                )
            )
        }
        offsets.append(visibleCharacters.last?.originalEndByteOffset ?? fallbackEndOffset)

        return FilteredReaderText(
            displayText: textParts.joined(),
            originalByteOffsetsByUTF16Index: offsets
        )
    }

    private struct FilteredCharacter {
        var text: String
        var originalByteOffset: Int
        var originalEndByteOffset: Int = 0
    }
}
