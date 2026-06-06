import Foundation
import SwiftUI
import UIKit

struct StorageUsageChartCard: View {
    let snapshot: StorageUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("storage.usage.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 18) {
                StorageDonutChart(categories: snapshot.categories)
                    .frame(width: 132, height: 132)
                    .overlay {
                        VStack(spacing: 3) {
                            Text(StorageByteCountFormatter.string(from: snapshot.totalBytes))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.64)
                                .lineLimit(1)

                            Text("storage.total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }

                VStack(spacing: 8) {
                    ForEach(snapshot.categories) { category in
                        StorageLegendRow(category: category)
                    }
                }
            }
        }
        .storageCardStyle()
    }
}

private struct StorageDonutChart: View {
    let categories: [StorageUsageCategory]

    private var visibleCategories: [StorageUsageCategory] {
        categories.filter { $0.bytes > 0 }
    }

    private var totalBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 18)

            if totalBytes > 0 {
                ForEach(chartSlices) { slice in
                    Circle()
                        .trim(from: CGFloat(slice.start), to: CGFloat(slice.end))
                        .stroke(
                            slice.category.kind.color,
                            style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }

    private var chartSlices: [StorageDonutSlice] {
        guard totalBytes > 0 else {
            return []
        }

        var start = 0.0
        return visibleCategories.map { category in
            let fraction = Double(category.bytes) / Double(totalBytes)
            let slice = StorageDonutSlice(
                category: category,
                start: start,
                end: min(start + fraction, 1)
            )
            start += fraction
            return slice
        }
    }
}

private struct StorageLegendRow: View {
    let category: StorageUsageCategory

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(category.kind.color)
                .frame(width: 9, height: 9)

            Text(category.kind.titleKey)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(verbatim: StorageByteCountFormatter.string(from: category.bytes))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

struct StorageDashboardCard: View {
    let snapshot: StorageUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("storage.dashboard.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                StorageMetricTile(
                    title: "storage.dashboard.books",
                    value: "\(snapshot.bookCount)"
                )
                StorageMetricTile(
                    title: "storage.dashboard.total",
                    value: StorageByteCountFormatter.string(from: snapshot.totalBytes)
                )
            }
        }
        .storageCardStyle()
    }
}

private struct StorageMetricTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(verbatim: value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct StorageBookManagementCard: View {
    let repository: any LibraryRepository
    let books: [StorageBookUsage]
    let groups: [BookGroup]
    @Binding var sort: StorageBookSort
    @Binding var filter: StorageBookFilter
    let onOpenBook: (Book) -> Void
    let onExportBook: (Book) -> Void
    let onDeleteBook: (Book) -> Void

    private var visibleBooks: [StorageBookUsage] {
        let now = Date()
        return books
            .filter { filter.includes($0, groups: groups, now: now) }
            .sorted { sort.areInIncreasingOrder($0, $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("storage.books.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 10) {
                StorageSortMenu(sort: $sort)
                StorageFilterMenu(
                    filter: $filter,
                    groups: groups
                )
            }

            if visibleBooks.isEmpty {
                Text("storage.books.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleBooks.enumerated()), id: \.element.id) { index, book in
                        NavigationLink {
                            StorageBookDetailPage(
                                repository: repository,
                                bookUsage: book,
                                groups: groups,
                                onOpenBook: onOpenBook,
                                onExportBook: onExportBook,
                                onDeleteBook: onDeleteBook
                            )
                        } label: {
                            StorageBookUsageRow(book: book)
                        }
                        .buttonStyle(.plain)

                        if index < visibleBooks.count - 1 {
                            SettingsPageStyle.separator
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .storageCardStyle()
    }
}

private struct StorageSortMenu: View {
    @Binding var sort: StorageBookSort

    var body: some View {
        Menu {
            ForEach(StorageBookSort.allCases, id: \.self) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.titleKey, systemImage: "checkmark")
                    } else {
                        Text(option.titleKey)
                    }
                }
            }
        } label: {
            StorageSelectorLabel(
                title: "storage.sort.title",
                value: sort.titleKey,
                systemImage: "arrow.up.arrow.down"
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StorageFilterMenu: View {
    @Binding var filter: StorageBookFilter
    let groups: [BookGroup]

    var body: some View {
        Menu {
            Button {
                filter = .all
            } label: {
                if filter == .all {
                    Label("storage.filter.all", systemImage: "checkmark")
                } else {
                    Text("storage.filter.all")
                }
            }

            Button {
                filter = .ungrouped
            } label: {
                if filter == .ungrouped {
                    Label("sidebar.ungrouped", systemImage: "checkmark")
                } else {
                    Text("sidebar.ungrouped")
                }
            }

            ForEach(groups) { group in
                Button {
                    filter = .group(group.id)
                } label: {
                    if filter == .group(group.id) {
                        Label {
                            Text(verbatim: group.name)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: group.name)
                    }
                }
            }

            Button {
                filter = .unread
            } label: {
                if filter == .unread {
                    Label("storage.filter.unread", systemImage: "checkmark")
                } else {
                    Text("storage.filter.unread")
                }
            }

            Button {
                filter = .longUnread
            } label: {
                if filter == .longUnread {
                    Label("storage.filter.longUnread", systemImage: "checkmark")
                } else {
                    Text("storage.filter.longUnread")
                }
            }
        } label: {
            StorageSelectorLabel(
                title: "storage.filter.title",
                value: filter.title(groups: groups),
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StorageSelectorLabel: View {
    let title: LocalizedStringKey
    let value: Text
    let systemImage: String

    init(
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        systemImage: String
    ) {
        self.title = title
        self.value = Text(value)
        self.systemImage = systemImage
    }

    init(
        title: LocalizedStringKey,
        value: String,
        systemImage: String
    ) {
        self.title = title
        self.value = Text(verbatim: value)
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                value
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StorageBookUsageRow: View {
    let book: StorageBookUsage

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: displayTitle)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(verbatim: StorageByteCountFormatter.string(from: book.bytes))
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.white)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

private struct StorageBookDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let bookUsage: StorageBookUsage
    let groups: [BookGroup]
    let onOpenBook: (Book) -> Void
    let onExportBook: (Book) -> Void
    let onDeleteBook: (Book) -> Void

    @State private var showsDeleteConfirmation = false
    @State private var tags: [BookTag] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    detailCard
                    actionCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("storage.book.detail.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .task(id: bookUsage.id) {
            await reloadTags()
        }
        .alert(
            "storage.book.delete.title",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("storage.book.delete.action", role: .destructive) {
                dismiss()
                onDeleteBook(bookUsage.book)
            }
        } message: {
            Text("storage.book.delete.message")
        }
        .alert(
            "tags.error.title",
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

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(.bottom, 12)

            StorageBookDetailRow(
                title: "storage.book.size",
                value: StorageByteCountFormatter.string(from: bookUsage.bytes)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.importedAt",
                value: StorageDateFormatter.string(from: bookUsage.importedAt)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.lastReadAt",
                value: bookUsage.lastReadAt.map { StorageDateFormatter.string(from: $0) }
                    ?? NSLocalizedString("storage.book.neverRead", comment: "")
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.progress",
                value: ReadingProgressFormatter.percentString(from: bookUsage.progressPercentage)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.group",
                value: groupName
            )
            SettingsPageStyle.separator

            StorageBookTagsDisplayRow(tags: tags)
        }
        .storageCardStyle()
    }

    private var actionCard: some View {
        VStack(spacing: 0) {
            Button {
                onOpenBook(bookUsage.book)
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.read",
                    systemImage: "book",
                    tint: .accentColor
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            Button {
                onExportBook(bookUsage.book)
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.export",
                    systemImage: "square.and.arrow.up",
                    tint: .accentColor
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.delete",
                    systemImage: "trash",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayTitle: String {
        let trimmed = bookUsage.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var groupName: String {
        guard let groupID = bookUsage.groupID else {
            return NSLocalizedString("sidebar.ungrouped", comment: "")
        }
        return groups.first { $0.id == groupID }?.name
            ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
    }

    @MainActor
    private func reloadTags() async {
        do {
            let fetchedTags = try await repository.fetchTags(bookID: bookUsage.id)
            tags = fetchedTags
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StorageBookDetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer(minLength: 16)

            Text(verbatim: value)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }
}

private struct StorageBookTagsDisplayRow: View {
    let tags: [BookTag]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("tags.field.title")
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.top, tags.isEmpty ? 0 : 7)

            Spacer(minLength: 16)

            if tags.isEmpty {
                Text("tags.none")
                    .font(.body)
                    .foregroundColor(.primary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags) { tag in
                            BookTagBubble(name: tag.name)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 11)
    }
}

private struct StorageBookActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 22)

            Text(title)
                .font(.body)
                .foregroundColor(tint)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

struct StorageLoadingCard: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("storage.loading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .storageCardStyle()
    }
}
