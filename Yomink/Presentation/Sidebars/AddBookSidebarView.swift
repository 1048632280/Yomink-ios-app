import SwiftUI
import UIKit

struct AddBookSidebarView: View {
    let repository: (any LibraryRepository)?
    let revealToken: Int
    let onImportFromFile: () -> Void
    let onOpenBook: (Book) -> Void

    @State private var historyItems: [ReadingHistoryItem] = []
    @State private var errorMessage: String?

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
            VStack(spacing: 0) {
                sidebarHeader

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

                        Text("add.reading.history")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .padding(.bottom, 4)

                        if historyItems.isEmpty {
                            Text("history.empty.message")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
            }
            .navigationBarHidden(true)
            .background(Color(.systemGray6))
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
        .navigationViewStyle(.stack)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("add.header.placeholder")
                .font(.headline)
            Text("add.header.subtitle")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color(.systemGray6))
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
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: item.book.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.primary)
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
                .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 24)
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
