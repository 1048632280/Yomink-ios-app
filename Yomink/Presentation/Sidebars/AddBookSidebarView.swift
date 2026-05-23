import SwiftUI
import UIKit

struct AddBookSidebarView: View {
    let repository: (any LibraryRepository)?
    let revealToken: Int
    let onImportFromFile: () -> Void
    let onOpenBook: (Book) -> Void

    init(
        repository: (any LibraryRepository)? = nil,
        revealToken: Int = 0,
        onImportFromFile: @escaping () -> Void = {},
        onOpenBook: @escaping (Book) -> Void = { _ in }
    ) {
        self.repository = repository
        self.revealToken = revealToken
        self.onImportFromFile = onImportFromFile
        self.onOpenBook = onOpenBook
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    Button {
                        onImportFromFile()
                    } label: {
                        SidebarItemRow(
                            localizedTitle: "add.import.file",
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ReadingHistoryPage(
                            repository: repository,
                            revealToken: revealToken,
                            onOpenBook: onOpenBook
                        )
                    } label: {
                        SidebarItemRow(
                            localizedTitle: "add.reading.history",
                            systemImage: "clock"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .navigationBarHidden(true)
            .background(SidebarStyle.background)
        }
        .navigationViewStyle(.stack)
    }
}

private struct ReadingHistoryPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: (any LibraryRepository)?
    let revealToken: Int
    let onOpenBook: (Book) -> Void

    @State private var historyItems: [ReadingHistoryItem] = []
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if historyItems.isEmpty {
                    Text("history.empty.message")
                        .font(.subheadline)
                        .foregroundColor(SidebarStyle.secondaryText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                } else {
                    ForEach(historyItems) { item in
                        Button {
                            onOpenBook(item.book)
                        } label: {
                            ReadingHistoryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            historyTitleBar
        }
        .background(SidebarStyle.background)
        .navigationBarHidden(true)
        .task {
            await reloadHistory()
        }
        .onChange(of: revealToken) { _ in
            Task {
                await reloadHistory()
            }
        }
        .alert(
            "history.error.title",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("common.ok", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var historyTitleBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SidebarStyle.primaryText)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("common.back"))

            Text("add.reading.history")
                .font(.headline)
                .foregroundColor(SidebarStyle.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
        .background(SidebarStyle.background)
    }

    @MainActor
    private func reloadHistory() async {
        guard let repository else {
            historyItems = []
            return
        }

        do {
            historyItems = try await repository.fetchReadingHistory(limit: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReadingHistoryRow: View {
    let item: ReadingHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(SidebarStyle.icon)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: item.book.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(SidebarStyle.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let chapterTitle = item.chapterTitle {
                        Text(verbatim: chapterTitle)
                            .lineLimit(1)
                    }

                    Text(historyDateText)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundColor(SidebarStyle.secondaryText)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SidebarStyle.rowBackground)
                .padding(.horizontal, 12)
        )
        .contentShape(Rectangle())
    }

    private var historyDateText: String {
        Self.dateFormatter.localizedString(for: item.readAt, relativeTo: Date())
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
