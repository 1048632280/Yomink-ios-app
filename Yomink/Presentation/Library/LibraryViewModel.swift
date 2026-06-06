import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var allBooks: [Book] = []
    @Published var groups: [BookGroup] = []
    @Published var settings = LibrarySettings.default
    @Published private(set) var hasLoadedInitialData = false
    @Published var selectedBookIDs: Set<UUID> = []
    @Published var isSelectionMode = false
    @Published var isImporting = false
    @Published var importErrorTitle: LocalizedStringKey = "library.error.title"
    @Published var importErrorMessage: String?
    @Published var importPreview: ImportBookPreview?
    @Published private(set) var importTargetGroupID: UUID?
    @Published var batchImportProgress: ImportBatchProgress?
    private var currentImportTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var settingsSaveTask: Task<Void, Never>?
    private var settingsSaveGeneration = 0
    private var persistedSettings = LibrarySettings.default

    var isSelecting: Bool {
        isSelectionMode
    }

    var selectionCountText: String {
        String(
            format: NSLocalizedString("library.selection.count", comment: ""),
            selectedBookIDs.count
        )
    }

    var importProgressStatusText: String {
        guard let progress = batchImportProgress else {
            return NSLocalizedString("import.progress.message", comment: "")
        }

        switch progress.phase {
        case .scanning:
            return NSLocalizedString("import.batch.scanning", comment: "")
        case .downloading:
            return NSLocalizedString("import.batch.downloading.prefix", comment: "")
        case .importing:
            return NSLocalizedString("import.batch.progress.prefix", comment: "")
        }
    }

    var importProgressCountText: String? {
        guard let progress = batchImportProgress,
              progress.phase != .scanning,
              progress.totalCount > 0 else {
            return nil
        }
        return "\(importProgressDisplayCount)/\(progress.totalCount)"
    }

    private var importProgressDisplayCount: Int {
        guard let progress = batchImportProgress else {
            return 0
        }

        switch progress.phase {
        case .scanning:
            return progress.processedCount
        case .downloading:
            return min(progress.processedCount + 1, progress.totalCount)
        case .importing:
            return min(
                progress.processedCount + (progress.currentFileName == nil ? 0 : 1),
                progress.totalCount
            )
        }
    }

    func bootstrap(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) async {
        guard !isImporting else {
            return
        }

        let generation = nextLoadGeneration()
        do {
            async let fetchedSettings = repository.fetchLibrarySettings()
            async let fetchedGroups = repository.fetchGroups()
            let settings = try await fetchedSettings
            async let fetchedAllBooks = repository.fetchBooks(
                scope: .all,
                sortOrder: settings.sortOrder
            )
            async let fetchedBooks = repository.fetchBooks(
                scope: scope,
                sortOrder: settings.sortOrder
            )
            let groups = try await fetchedGroups
            let allBooks = try await fetchedAllBooks
            let books = try await fetchedBooks
            guard isCurrentLoadGeneration(generation) else {
                return
            }
            self.settings = settings
            self.persistedSettings = settings
            self.groups = groups
            self.allBooks = allBooks
            self.books = books
            self.hasLoadedInitialData = true
            pruneSelection()
        } catch is CancellationError {
        } catch {
            guard isCurrentLoadGeneration(generation) else {
                return
            }
            hasLoadedInitialData = true
            showError(error, title: "library.error.title")
        }
    }

    func loadBooks(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) async {
        guard !isImporting else {
            return
        }

        let generation = nextLoadGeneration()
        let sortOrder = settings.sortOrder
        do {
            async let fetchedGroups = repository.fetchGroups()
            async let fetchedAllBooks = repository.fetchBooks(
                scope: .all,
                sortOrder: sortOrder
            )
            async let fetchedBooks = repository.fetchBooks(
                scope: scope,
                sortOrder: sortOrder
            )
            let groups = try await fetchedGroups
            let allBooks = try await fetchedAllBooks
            let books = try await fetchedBooks
            guard isCurrentLoadGeneration(generation) else {
                return
            }
            self.groups = groups
            self.allBooks = allBooks
            self.books = books
            self.hasLoadedInitialData = true
            pruneSelection()
        } catch is CancellationError {
        } catch {
            guard isCurrentLoadGeneration(generation) else {
                return
            }
            hasLoadedInitialData = true
            showError(error, title: "library.error.title")
        }
    }

    func handleImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService,
        targetGroupID: UUID?
    ) {
        guard !isImporting else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            prepareImportPreview(
                from: url,
                importService: importService,
                targetGroupID: targetGroupID
            )
        case let .failure(error):
            showError(error, title: "import.error.title")
        }
    }

    func handleBatchImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService,
        targetGroupID: UUID?,
        onCompleted: @escaping () -> Void
    ) {
        guard !isImporting else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            startBatchImport(
                in: url,
                importService: importService,
                targetGroupID: targetGroupID,
                onCompleted: onCompleted
            )
        case let .failure(error):
            showError(error, title: "import.error.title")
        }
    }

    func loadIfNeededAfterPickerDismissal(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        guard !isImporting else {
            return
        }

        Task {
            await loadBooks(repository: repository, scope: scope)
        }
    }

    func beginSelection(with bookID: UUID) {
        isSelectionMode = true
        selectedBookIDs = [bookID]
    }

    func toggleSelection(for bookID: UUID) {
        if selectedBookIDs.contains(bookID) {
            selectedBookIDs.remove(bookID)
        } else {
            selectedBookIDs.insert(bookID)
        }
    }

    func invertSelection() {
        isSelectionMode = true
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs = visibleIDs.subtracting(selectedBookIDs)
    }

    func exitSelection() {
        isSelectionMode = false
        selectedBookIDs.removeAll()
    }

    func updateLibrarySettings(
        _ settings: LibrarySettings,
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        let previousSettings = self.settings
        guard settings != previousSettings else {
            return
        }

        self.settings = settings
        settingsSaveGeneration += 1
        let generation = settingsSaveGeneration
        let previousSaveTask = settingsSaveTask
        settingsSaveTask = Task {
            if let previousSaveTask {
                await previousSaveTask.value
            }
            do {
                try Task.checkCancellation()
                try await repository.saveLibrarySettings(settings)
                persistedSettings = settings
                try Task.checkCancellation()
                guard isCurrentSettingsSaveGeneration(generation) else {
                    return
                }
                await loadBooks(repository: repository, scope: scope)
                if isCurrentSettingsSaveGeneration(generation) {
                    settingsSaveTask = nil
                }
            } catch is CancellationError {
            } catch {
                guard isCurrentSettingsSaveGeneration(generation) else {
                    return
                }
                if self.settings == settings {
                    self.settings = persistedSettings
                }
                settingsSaveTask = nil
                showError(error, title: "settings.error.title")
            }
        }
    }

    func moveSelectedBooks(
        to groupID: UUID?,
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        let ids = selectedBookIDs
        guard !ids.isEmpty else {
            return
        }

        Task {
            do {
                try await repository.moveBooks(ids: ids, to: groupID)
                await loadBooks(repository: repository, scope: scope)
                exitSelection()
            } catch {
                showError(error, title: "library.move.error.title")
            }
        }
    }

    func deleteBooks(
        ids: Set<UUID>,
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        scope: LibraryScope
    ) {
        let ids = ids.filter { id in
            books.contains(where: { $0.id == id })
        }
        guard !ids.isEmpty else {
            return
        }

        Task {
            do {
                var stagedFiles: [(id: UUID, stagedURL: URL?)] = []
                do {
                    for id in ids {
                        let stagedURL = try fileStore.stageBookFilesForDeletion(id: id)
                        stagedFiles.append((id: id, stagedURL: stagedURL))
                    }
                } catch {
                    for entry in stagedFiles.reversed() {
                        if let stagedURL = entry.stagedURL {
                            try? fileStore.restoreStagedBookFiles(stagedURL, id: entry.id)
                        }
                    }
                    throw error
                }

                do {
                    try await repository.deleteBooks(ids: Set(ids))
                    for entry in stagedFiles {
                        if let stagedURL = entry.stagedURL {
                            try? fileStore.removeStagedBookFiles(stagedURL)
                        }
                    }
                } catch {
                    for entry in stagedFiles.reversed() {
                        if let stagedURL = entry.stagedURL {
                            try? fileStore.restoreStagedBookFiles(stagedURL, id: entry.id)
                        }
                    }
                    throw error
                }
                exitSelection()
                await loadBooks(repository: repository, scope: scope)
            } catch {
                showError(error, title: "library.delete.error.title")
            }
        }
    }

    func exportURLs(fileStore: AppFileStore) throws -> BookExportService.ExportedFiles {
        try BookExportService.exportURLs(
            for: books.filter { selectedBookIDs.contains($0.id) },
            fileStore: fileStore
        )
    }

    private func prepareImportPreview(
        from url: URL,
        importService: ImportService,
        targetGroupID: UUID?
    ) {
        isImporting = true
        importTargetGroupID = targetGroupID
        batchImportProgress = nil
        currentImportTask = Task {
            do {
                importPreview = try await importService.previewImport(from: url)
                try Task.checkCancellation()
                currentImportTask = nil
            } catch {
                if !Task.isCancelled {
                    showError(error, title: "import.error.title")
                    currentImportTask = nil
                    importTargetGroupID = nil
                }
            }
            isImporting = false
            if Task.isCancelled {
                currentImportTask = nil
            }
        }
    }

    private func startBatchImport(
        in directoryURL: URL,
        importService: ImportService,
        targetGroupID: UUID?,
        onCompleted: @escaping () -> Void
    ) {
        isImporting = true
        clearError()
        batchImportProgress = ImportBatchProgress(
            phase: .scanning,
            processedCount: 0,
            totalCount: 0,
            currentFileName: nil
        )
        currentImportTask = Task {
            do {
                let summary = try await importService.importBooks(
                    in: directoryURL,
                    targetGroupID: targetGroupID
                ) { progress in
                    await MainActor.run {
                        self.batchImportProgress = progress
                    }
                }
                batchImportProgress = nil
                isImporting = false
                currentImportTask = nil
                showBatchImportResult(summary)
                onCompleted()
            } catch is CancellationError {
                batchImportProgress = nil
                isImporting = false
                currentImportTask = nil
            } catch {
                batchImportProgress = nil
                isImporting = false
                currentImportTask = nil
                showError(error, title: "import.error.title")
            }
        }
    }

    func showError(_ error: Error, title: LocalizedStringKey) {
        guard !(error is CancellationError) else {
            return
        }
        importErrorTitle = title
        importErrorMessage = error.localizedDescription
    }

    func showBatchImportResult(_ summary: ImportBatchSummary) {
        let message = ImportBatchResultMessage(summary: summary).message
        importErrorMessage = nil
        Task { @MainActor in
            await Task.yield()
            self.importErrorTitle = "import.batch.result.title"
            self.importErrorMessage = message
        }
    }

    func clearError() {
        importErrorMessage = nil
    }

    func clearImportPreview() {
        importPreview = nil
        importTargetGroupID = nil
    }

    private func pruneSelection() {
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs.formIntersection(visibleIDs)
    }

    private func nextLoadGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    private func isCurrentLoadGeneration(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    private func isCurrentSettingsSaveGeneration(_ generation: Int) -> Bool {
        generation == settingsSaveGeneration
    }
}

private struct ImportBatchResultMessage {
    let summary: ImportBatchSummary

    var message: String {
        var lines = [
            String(
                format: NSLocalizedString("import.batch.result.summary", comment: ""),
                summary.totalCount,
                summary.importedCount,
                summary.duplicateCount,
                summary.failedCount
            )
        ]

        if summary.totalCount == 0 {
            lines.append(NSLocalizedString("import.batch.result.empty", comment: ""))
        }

        if !summary.failures.isEmpty {
            let visibleFailures = summary.failures.prefix(5).map { failure in
                String(
                    format: NSLocalizedString("import.batch.result.failureLine", comment: ""),
                    failure.fileName,
                    failure.errorDescription
                )
            }
            lines.append("")
            lines.append(NSLocalizedString("import.batch.result.failures", comment: ""))
            lines.append(contentsOf: visibleFailures)

            let remainingCount = summary.failures.count - visibleFailures.count
            if remainingCount > 0 {
                lines.append(
                    String(
                        format: NSLocalizedString("import.batch.result.moreFailures", comment: ""),
                        remainingCount
                    )
                )
            }
        }

        return lines.joined(separator: "\n")
    }
}
