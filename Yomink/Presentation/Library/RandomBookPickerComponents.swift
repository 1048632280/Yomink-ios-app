import Foundation
import SwiftUI
import UIKit

struct RandomPickerStatsPage: View {
    @Environment(\.dismiss) private var dismiss

    let books: [Book]
    let pickerState: RandomPickerState
    let onOpenBook: (Book) -> Void

    private var rankedBooks: [RandomPickerRankedBook] {
        let bookLookup = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        return pickerState.drawCounts.compactMap { entry -> RandomPickerCountedBook? in
            guard entry.value > 0,
                  let book = bookLookup[entry.key]
            else {
                return nil
            }
            return RandomPickerCountedBook(book: book, count: entry.value)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let titleOrder = lhs.book.title.localizedStandardCompare(rhs.book.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.book.id.uuidString < rhs.book.id.uuidString
        }
        .prefix(10)
        .enumerated()
        .map { index, item in
            RandomPickerRankedBook(rank: index + 1, book: item.book, count: item.count)
        }
    }

    private var remainingRankedBooks: [RandomPickerRankedBook] {
        Array(rankedBooks.dropFirst(3))
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            if rankedBooks.isEmpty {
                Text("randomPicker.stats.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        podiumSection
                        leaderboardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("randomPicker.stats.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
    }

    private var podiumSection: some View {
        HStack(alignment: .bottom, spacing: 10) {
            podiumColumn(
                item: rankedBook(forRank: 2),
                rank: 2,
                width: 92,
                coverHeight: 112,
                baseHeight: 58
            )
            podiumColumn(
                item: rankedBook(forRank: 1),
                rank: 1,
                width: 110,
                coverHeight: 140,
                baseHeight: 74
            )
            podiumColumn(
                item: rankedBook(forRank: 3),
                rank: 3,
                width: 92,
                coverHeight: 104,
                baseHeight: 50
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private func rankedBook(forRank rank: Int) -> RandomPickerRankedBook? {
        rankedBooks.first { $0.rank == rank }
    }

    @ViewBuilder
    private func podiumColumn(
        item: RandomPickerRankedBook?,
        rank: Int,
        width: CGFloat,
        coverHeight: CGFloat,
        baseHeight: CGFloat
    ) -> some View {
        VStack(spacing: 8) {
            if let item {
                Button {
                    onOpenBook(item.book)
                } label: {
                    VStack(spacing: 7) {
                        RandomPickerCoverView(
                            title: item.book.title,
                            initialFontSize: rank == 1 ? 40 : 32
                        )
                        .frame(width: coverHeight * 0.75, height: coverHeight)
                        .shadow(
                            color: rank == 1
                                ? Color.accentColor.opacity(0.28)
                                : Color.black.opacity(0.08),
                            radius: rank == 1 ? 14 : 8,
                            x: 0,
                            y: rank == 1 ? 8 : 5
                        )

                        Text(displayTitle(for: item.book))
                            .font(rank == 1 ? .subheadline.weight(.semibold) : .caption.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: width)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: width, height: coverHeight + 42)
            }

            if let item {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(rank == 1 ? Color.accentColor.opacity(0.2) : Color.white)

                    VStack(spacing: 3) {
                        Text(verbatim: "\(rank)")
                            .font(.system(size: rank == 1 ? 22 : 18, weight: .bold))
                            .foregroundColor(rank == 1 ? .accentColor : .primary)

                        Text(countText(item.count))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: width, height: baseHeight)
            } else {
                Color.clear
                    .frame(width: width, height: baseHeight)
            }
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        if !remainingRankedBooks.isEmpty {
            VStack(spacing: 0) {
                ForEach(remainingRankedBooks) { item in
                    RandomPickerStatsRow(
                        item: item,
                        countText: countText(item.count),
                        onOpenBook: onOpenBook
                    )

                    if item.id != remainingRankedBooks.last?.id {
                        DedicatedPageStyle.separator
                            .padding(.leading, 76)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func displayTitle(for book: Book) -> String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private func countText(_ count: Int) -> String {
        String(
            format: NSLocalizedString("randomPicker.stats.count", comment: ""),
            count
        )
    }
}

private struct RandomPickerCountedBook: Equatable {
    let book: Book
    let count: Int
}

private struct RandomPickerRankedBook: Identifiable, Equatable {
    let rank: Int
    let book: Book
    let count: Int

    var id: UUID {
        book.id
    }
}

private struct RandomPickerStatsRow: View {
    let item: RandomPickerRankedBook
    let countText: String
    let onOpenBook: (Book) -> Void

    var body: some View {
        Button {
            onOpenBook(item.book)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: "\(item.rank)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                RandomPickerCoverView(title: item.book.title, initialFontSize: 22)
                    .frame(width: 42, height: 56)

                Text(displayTitle)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        let trimmed = item.book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

struct RandomPickerScopeChip: View {
    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .accentColor : Color(.systemGray3))

            Text(verbatim: title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(
                String(
                    format: NSLocalizedString("randomPicker.scope.count", comment: ""),
                    count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
    }
}

struct RandomPickerBookCard: View {
    let book: Book
    let isHighlighted: Bool
    private let coverWidth: CGFloat = 106

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RandomPickerCoverView(title: displayTitle, initialFontSize: 42)
                .frame(width: coverWidth, height: coverWidth * 4.0 / 3.0)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: RandomPickerCoverStyle.cornerRadius)
                        .stroke(
                            isHighlighted ? Color.accentColor.opacity(0.65) : Color.clear,
                            lineWidth: 2
                        )
                }

            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(progressText)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var progressText: String {
        ReadingProgressFormatter.percentString(from: book.progressPercentage)
    }
}

struct RandomPickerPlaceholderCard: View {
    let textKey: LocalizedStringKey

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay {
                Text(textKey)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
    }
}

struct RandomPickerHistoryCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RandomPickerCoverView(title: displayTitle, initialFontSize: 24)
                .frame(width: 50, height: 50 * 4.0 / 3.0)

            Text(displayTitle)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 66, alignment: .leading)
        }
        .frame(width: 66, height: 100, alignment: .topLeading)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

private struct RandomPickerCoverView: View {
    let title: String
    let initialFontSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: RandomPickerCoverStyle.cornerRadius, style: .continuous)
            .fill(RandomPickerCoverStyle.background)
            .overlay {
                Text(verbatim: coverInitial)
                    .font(.system(size: initialFontSize, weight: .semibold))
                    .foregroundColor(RandomPickerCoverStyle.coverText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
    }

    private var coverInitial: String {
        title.dedicatedFirstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
    }
}

private enum RandomPickerCoverStyle {
    static let cornerRadius: CGFloat = 5
    static let background = Color(.systemGray5)
    static let coverText = Color(.darkGray).opacity(0.62)
}
