import Foundation
import SwiftUI
import UIKit

struct StorageManagementPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let fileStore: AppFileStore
    let onOpenBook: (Book) -> Void
    let onLibraryChanged: () -> Void

    @State private var snapshot: StorageUsageSnapshot?
    @State private var sort: StorageBookSort = .size
    @State private var filter: StorageBookFilter = .all
    @State private var isLoading = true
    @State private var errorTitle: LocalizedStringKey = "storage.error.title"
    @State private var errorMessage: String?
    @State private var exportPayload: StorageExportPayload?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    if let snapshot {
                        StorageUsageChartCard(snapshot: snapshot)
                        StorageDashboardCard(snapshot: snapshot)
                        StorageBookManagementCard(
                            repository: repository,
                            books: snapshot.books,
                            groups: snapshot.groups,
                            sort: $sort,
                            filter: $filter,
                            onOpenBook: onOpenBook,
                            onExportBook: exportBook,
                            onDeleteBook: deleteBook
                        )
                    } else {
                        StorageLoadingCard(isLoading: isLoading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .refreshable {
                await reloadStorage()
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("storage.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .task {
            await reloadStorage()
        }
        .sheet(item: $exportPayload) { payload in
            ActivityPresenter(
                activityItems: [payload.url as Any],
                onComplete: {
                    BookExportService.cleanupExportDirectory(payload.directoryURL)
                }
            )
        }
        .alert(
            errorTitle,
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

    @MainActor
    private func reloadStorage() async {
        isLoading = true
        do {
            async let fetchedBooks = repository.fetchBooks(scope: .all, sortOrder: .lastReadAt)
            async let fetchedGroups = repository.fetchGroups()
            let books = try await fetchedBooks
            let groups = try await fetchedGroups
            snapshot = await StorageUsageScanner.snapshot(
                fileStore: fileStore,
                books: books,
                groups: groups
            )
        } catch {
            errorTitle = "storage.error.title"
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func exportBook(_ book: Book) {
        do {
            let export = try BookExportService.exportURL(for: book, fileStore: fileStore)
            exportPayload = StorageExportPayload(
                url: export.url,
                directoryURL: export.directoryURL
            )
        } catch {
            errorTitle = "library.export.error.title"
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBook(_ book: Book) {
        Task {
            do {
                let stagedURL = try fileStore.stageBookFilesForDeletion(id: book.id)
                do {
                    try await repository.deleteBook(id: book.id)
                    if let stagedURL {
                        try? fileStore.removeStagedBookFiles(stagedURL)
                    }
                } catch {
                    if let stagedURL {
                        try? fileStore.restoreStagedBookFiles(stagedURL, id: book.id)
                    }
                    throw error
                }
                await reloadStorage()
                await MainActor.run {
                    onLibraryChanged()
                }
            } catch {
                await MainActor.run {
                    errorTitle = "library.delete.error.title"
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct StorageUsageChartCard: View {
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

private struct StorageDashboardCard: View {
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

private struct StorageBookManagementCard: View {
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

private struct StorageLoadingCard: View {
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

private enum StorageUsageScanner {
    static func snapshot(
        fileStore: AppFileStore,
        books: [Book],
        groups: [BookGroup]
    ) async -> StorageUsageSnapshot {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let bookUsages = books.map { book in
                StorageBookUsage(
                    book: book,
                    bytes: Self.contentSize(for: book, fileStore: fileStore, fileManager: fileManager)
                )
            }

            let txtBytes = bookUsages.reduce(Int64(0)) { $0 + $1.bytes }
            let booksDirectoryBytes = Self.directorySize(at: fileStore.booksURL, fileManager: fileManager)
            let documentsBytes = Self.directorySize(at: fileStore.documentsURL, fileManager: fileManager)
            let applicationSupportBytes = Self.directorySize(
                at: fileStore.applicationSupportURL,
                fileManager: fileManager
            )
            let databaseBytes = Self.databaseSize(fileStore: fileStore, fileManager: fileManager)
            let temporaryExportBytes = Self.directorySize(
                at: Self.temporaryExportURL(fileManager: fileManager),
                fileManager: fileManager
            )
            let indexCacheBytes = max(0, booksDirectoryBytes - txtBytes)
                + max(0, applicationSupportBytes - databaseBytes)
            let otherBytes = max(0, documentsBytes - booksDirectoryBytes)

            let categories = [
                StorageUsageCategory(kind: .txt, bytes: txtBytes),
                StorageUsageCategory(kind: .database, bytes: databaseBytes),
                StorageUsageCategory(kind: .temporaryExport, bytes: temporaryExportBytes),
                StorageUsageCategory(kind: .indexCache, bytes: indexCacheBytes),
                StorageUsageCategory(kind: .other, bytes: otherBytes)
            ]

            return StorageUsageSnapshot(
                categories: categories,
                books: bookUsages,
                groups: groups
            )
        }.value
    }

    private static func contentSize(
        for book: Book,
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        guard let url = try? fileStore.url(forRelativePath: book.sourcePath) else {
            return 0
        }
        return fileSize(at: url, fileManager: fileManager)
    }

    private static func databaseSize(
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        [
            fileStore.databaseURL,
            URL(fileURLWithPath: fileStore.databaseURL.path + "-wal"),
            URL(fileURLWithPath: fileStore.databaseURL.path + "-shm")
        ].reduce(Int64(0)) { result, url in
            result + fileSize(at: url, fileManager: fileManager)
        }
    }

    private static func temporaryExportURL(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("YominkExports", isDirectory: true)
    }

    private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey
                ]
              )
        else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return total
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
              ])
        else {
            return 0
        }
        return Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
        )
    }
}

private struct StorageUsageSnapshot: Sendable {
    let categories: [StorageUsageCategory]
    let books: [StorageBookUsage]
    let groups: [BookGroup]

    var totalBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var bookCount: Int {
        books.count
    }
}

private struct StorageUsageCategory: Identifiable, Sendable {
    let kind: StorageUsageKind
    let bytes: Int64

    var id: String {
        kind.rawValue
    }
}

private enum StorageUsageKind: String, Sendable {
    case txt
    case database
    case temporaryExport
    case indexCache
    case other

    var titleKey: LocalizedStringKey {
        switch self {
        case .txt:
            return "storage.category.txt"
        case .database:
            return "storage.category.database"
        case .temporaryExport:
            return "storage.category.temporaryExport"
        case .indexCache:
            return "storage.category.indexCache"
        case .other:
            return "storage.category.other"
        }
    }

    var color: Color {
        switch self {
        case .txt:
            return Color(red: 0.20, green: 0.45, blue: 0.78)
        case .database:
            return Color(red: 0.28, green: 0.58, blue: 0.34)
        case .temporaryExport:
            return Color(red: 0.84, green: 0.52, blue: 0.22)
        case .indexCache:
            return Color(red: 0.48, green: 0.38, blue: 0.70)
        case .other:
            return Color(.systemGray3)
        }
    }
}

private struct StorageDonutSlice: Identifiable {
    let category: StorageUsageCategory
    let start: Double
    let end: Double

    var id: String {
        category.id
    }
}

private struct StorageBookUsage: Identifiable, Sendable {
    let book: Book
    let bytes: Int64

    var id: UUID {
        book.id
    }

    var title: String {
        book.title
    }

    var groupID: UUID? {
        book.groupID
    }

    var importedAt: Date {
        book.importedAt
    }

    var lastReadAt: Date? {
        book.lastReadAt
    }

    var progressPercentage: Double {
        book.progressPercentage
    }

    var isUnread: Bool {
        progressPercentage <= 0.0001
    }
}

private enum StorageBookSort: CaseIterable, Hashable {
    case size
    case lastReadAt
    case importedAt

    var titleKey: LocalizedStringKey {
        switch self {
        case .size:
            return "storage.sort.size"
        case .lastReadAt:
            return "storage.sort.lastReadAt"
        case .importedAt:
            return "storage.sort.importedAt"
        }
    }

    func areInIncreasingOrder(_ lhs: StorageBookUsage, _ rhs: StorageBookUsage) -> Bool {
        switch self {
        case .size:
            if lhs.bytes == rhs.bytes {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        case .lastReadAt:
            let leftDate = lhs.lastReadAt ?? .distantPast
            let rightDate = rhs.lastReadAt ?? .distantPast
            if leftDate == rightDate {
                return lhs.importedAt > rhs.importedAt
            }
            return leftDate > rightDate
        case .importedAt:
            return lhs.importedAt > rhs.importedAt
        }
    }
}

private enum StorageBookFilter: Equatable {
    case all
    case ungrouped
    case group(UUID)
    case unread
    case longUnread

    private static let longUnreadInterval: TimeInterval = 30 * 24 * 60 * 60

    func title(groups: [BookGroup]) -> String {
        switch self {
        case .all:
            return NSLocalizedString("storage.filter.all", comment: "")
        case .ungrouped:
            return NSLocalizedString("sidebar.ungrouped", comment: "")
        case let .group(id):
            return groups.first { $0.id == id }?.name
                ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
        case .unread:
            return NSLocalizedString("storage.filter.unread", comment: "")
        case .longUnread:
            return NSLocalizedString("storage.filter.longUnread", comment: "")
        }
    }

    func includes(
        _ book: StorageBookUsage,
        groups: [BookGroup],
        now: Date
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .ungrouped:
            return book.groupID == nil
        case let .group(id):
            return book.groupID == id && groups.contains { $0.id == id }
        case .unread:
            return book.isUnread
        case .longUnread:
            guard let lastReadAt = book.lastReadAt else {
                return false
            }
            return lastReadAt < now.addingTimeInterval(-Self.longUnreadInterval)
        }
    }
}

private enum StorageByteCountFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

private enum StorageDateFormatter {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}


private struct StorageExportPayload: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let directoryURL: URL
}

