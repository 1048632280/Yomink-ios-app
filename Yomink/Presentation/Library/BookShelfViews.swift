import Foundation
import SwiftUI
import UIKit

struct BookShelfItemButton<Content: View>: View {
    private let isSelected: Bool
    @State private var suppressNextTap = false
    private let content: () -> Content
    private let action: () -> Void
    private let longPressAction: (() -> Void)?

    init(
        isSelected: Bool,
        @ViewBuilder content: @escaping () -> Content,
        action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil
    ) {
        self.isSelected = isSelected
        self.content = content
        self.action = action
        self.longPressAction = longPressAction
    }

    var body: some View {
        if let longPressAction {
            tappableContent
                .onLongPressGesture(minimumDuration: 0.18) {
                    suppressNextTap = true
                    longPressAction()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        suppressNextTap = false
                    }
                }
        } else {
            tappableContent
        }
    }

    private var tappableContent: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                guard !suppressNextTap else {
                    suppressNextTap = false
                    return
                }
                action()
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct BookRowView: View {
    private let book: Book
    private let isSelecting: Bool
    private let isSelected: Bool

    init(book: Book, isSelecting: Bool, isSelected: Bool) {
        self.book = book
        self.isSelecting = isSelecting
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(alignment: .top, spacing: BookListStyle.coverTrailingSpacing) {
            thumbnailView

            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    PreciseProgressBar(value: clampedProgress)
                        .frame(maxWidth: 120)
                        .frame(height: BookListStyle.progressHeight)

                    Text(progressText)
                        .font(.system(size: 13))
                        .foregroundColor(BookCoverStyle.progressText)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: BookListStyle.coverHeight, alignment: .topLeading)
            .padding(.top, BookListStyle.textTopOffset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, BookListStyle.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var thumbnailView: some View {
        BookCoverPlaceholder(
            title: book.title,
            isSelecting: isSelecting,
            isSelected: isSelected,
            initialFontSize: BookListStyle.coverInitialFontSize,
            selectionPadding: 5
        )
        .frame(
            width: BookListStyle.coverWidth,
            height: BookListStyle.coverHeight
        )
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var clampedProgress: Double {
        min(max(book.progressPercentage, 0), 1)
    }

    private var progressText: String {
        ReadingProgressFormatter.percentString(from: clampedProgress)
    }
}

struct BookGridItemView: View {
    private let book: Book
    private let isSelecting: Bool
    private let isSelected: Bool

    init(book: Book, isSelecting: Bool, isSelected: Bool) {
        self.book = book
        self.isSelecting = isSelecting
        self.isSelected = isSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverView

            Text(displayTitle)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Text(progressText)
                .font(.system(size: 12))
                .foregroundColor(BookCoverStyle.progressText)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
        }
        .padding(.horizontal, BookGridStyle.coverHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var coverView: some View {
        BookCoverPlaceholder(
            title: book.title,
            isSelecting: isSelecting,
            isSelected: isSelected,
            initialFontSize: BookGridStyle.coverInitialFontSize,
            selectionPadding: 6
        )
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var clampedProgress: Double {
        min(max(book.progressPercentage, 0), 1)
    }

    private var progressText: String {
        let progress = ReadingProgressFormatter.percentString(from: clampedProgress)
        return String(
            format: NSLocalizedString("library.grid.progress", comment: ""),
            progress
        )
    }
}

private struct BookCoverPlaceholder: View {
    let title: String
    let isSelecting: Bool
    let isSelected: Bool
    let initialFontSize: CGFloat
    let selectionPadding: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: BookCoverStyle.cornerRadius)
                .fill(BookCoverStyle.background)
                .overlay {
                    Text(verbatim: coverInitial)
                        .font(.system(size: initialFontSize, weight: .semibold))
                        .foregroundColor(BookCoverStyle.coverText)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: BookCoverStyle.cornerRadius)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .brightness(isSelecting && !isSelected ? -0.18 : 0)

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color(.systemGray),
                        Color.white
                    )
                    .padding(selectionPadding)
            }
        }
    }

    private var coverInitial: String {
        title
            .firstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
    }
}

private struct PreciseProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedValue = min(max(value, 0), 1)
            let fillWidth = proxy.size.width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))

                if fillWidth > 0 {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: fillWidth)
                }
            }
        }
        .accessibilityValue(Text(progressText))
    }

    private var progressText: String {
        ReadingProgressFormatter.percentString(from: value)
    }
}

private enum BookListStyle {
    static let coverWidth: CGFloat = 60
    static let coverHeight: CGFloat = 84
    static let coverInitialFontSize: CGFloat = 32
    static let coverTrailingSpacing: CGFloat = 14
    static let progressHeight: CGFloat = 4
    static let textTopOffset: CGFloat = 5
    static let verticalPadding: CGFloat = 12
}

enum BookGridStyle {
    static let columnSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 22
    fileprivate static let coverHorizontalInset: CGFloat = 6
    fileprivate static let coverInitialFontSize: CGFloat = 40
}

private enum BookCoverStyle {
    static let cornerRadius: CGFloat = 5
    static let background = Color(.systemGray5)
    static let coverText = Color(.darkGray).opacity(0.62)
    static let progressText = Color(.systemGray)
}

struct FixedWidthImportBatchCountText: View {
    private let text: String

    init(text: String) {
        self.text = text
    }

    var body: some View {
        ZStack(alignment: .center) {
            Text(verbatim: "999/999")
                .font(.subheadline.monospacedDigit())
                .hidden()

            Text(verbatim: text)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 22, alignment: .center)
    }
}

private extension String {
    var firstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
    }
}
