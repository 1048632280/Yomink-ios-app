import Foundation
import SwiftUI
import UIKit

struct ImportBookEditPage: View {
    @Environment(\.dismiss) private var dismiss

    let preview: ImportBookPreview
    let importService: ImportService
    let repository: any LibraryRepository
    let targetGroupID: UUID?
    let onImported: () -> Void
    let onOpenExistingBook: (Book) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var author: String
    @State private var intro: String
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var isImporting = false
    @State private var duplicateBook: Book?
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?

    init(
        preview: ImportBookPreview,
        importService: ImportService,
        repository: any LibraryRepository,
        targetGroupID: UUID? = nil,
        onImported: @escaping () -> Void,
        onOpenExistingBook: @escaping (Book) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.preview = preview
        self.importService = importService
        self.repository = repository
        self.targetGroupID = targetGroupID
        self.onImported = onImported
        self.onOpenExistingBook = onOpenExistingBook
        self.onCancel = onCancel
        _title = State(initialValue: preview.title)
        _author = State(initialValue: preview.author ?? "")
        _intro = State(initialValue: preview.intro ?? "")
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                metadataRows

                Spacer(minLength: 0)
            }

            if isImporting {
                importingOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    cancel()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("import.action") {
                    startImport()
                }
                .disabled(isImporting)
            }
        }
        .alert(item: $duplicateBook) { book in
            Alert(
                title: Text("import.duplicate.title"),
                message: Text("import.duplicate.message"),
                primaryButton: .default(Text("import.duplicate.openExisting")) {
                    isImporting = false
                    onOpenExistingBook(book)
                },
                secondaryButton: .cancel(Text("import.duplicate.cancel")) {
                    isImporting = false
                    cancel()
                }
            )
        }
        .alert(
            "import.error.title",
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
        .onDisappear {
            cancelImportTask()
        }
    }

    private var navigationTitle: String {
        String(
            format: NSLocalizedString("import.edit.title", comment: ""),
            preview.fileName
        )
    }

    private var metadataRows: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.title",
                    text: $title
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.title",
                    value: title
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.author",
                    text: $author
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.author",
                    value: author
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.intro",
                    text: $intro
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.intro",
                    value: intro
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                BookTagPickerPage(
                    repository: repository,
                    selectedTagIDs: $selectedTagIDs
                )
            } label: {
                ImportMetadataRow(
                    title: "tags.field.title",
                    value: selectedTagsSummary
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text("import.progress.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    private func startImport() {
        guard !isImporting else {
            return
        }

        isImporting = true
        let tagIDsToApply = selectedTagIDs
        let metadata = ImportBookMetadata(
            title: title,
            author: author,
            intro: intro
        )
        importTask = Task {
            do {
                switch try await importService.importBookCheckingDuplicate(
                    from: preview.sourceURL,
                    metadata: metadata,
                    targetGroupID: targetGroupID
                ) {
                case let .duplicate(existingBook):
                    try Task.checkCancellation()
                    isImporting = false
                    duplicateBook = existingBook
                case let .imported(book):
                    try Task.checkCancellation()
                    if !tagIDsToApply.isEmpty {
                        try await repository.setBookTags(
                            bookID: book.id,
                            tagIDs: tagIDsToApply
                        )
                    }
                    try Task.checkCancellation()
                    isImporting = false
                    onImported()
                }
            } catch is CancellationError {
                isImporting = false
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
            importTask = nil
        }
    }

    private func cancel() {
        cancelImportTask()
        onCancel()
        dismiss()
    }

    private func cancelImportTask() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
    }

    private var selectedTagsSummary: String {
        guard !selectedTagIDs.isEmpty else {
            return ""
        }

        return String(
            format: NSLocalizedString("tags.selected.count", comment: ""),
            selectedTagIDs.count
        )
    }
}

private struct ImportMetadataRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            if !trimmedValue.isEmpty {
                Text(verbatim: trimmedValue)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImportMetadataFieldEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .background(InteractivePopGestureRestorer())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackTextButton {
                        dismiss()
                    }
                }
            }
    }
}

