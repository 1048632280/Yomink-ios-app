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
