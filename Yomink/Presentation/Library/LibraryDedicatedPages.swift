import SwiftUI

struct LibraryGroupsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onGroupsChanged: (UUID?) -> Void

    @State private var groups: [BookGroup] = []
    @State private var isEditing = false
    @State private var isAddingGroup = false
    @State private var editingGroup: BookGroup?
    @State private var groupPendingDeletion: BookGroup?
    @State private var nameDraft = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    DedicatedListRow(title: NSLocalizedString("sidebar.ungrouped", comment: ""))

                    ForEach(groups) { group in
                        DedicatedListRow(
                            title: group.name,
                            showsDeleteControl: isEditing,
                            deleteAction: {
                                groupPendingDeletion = group
                            }
                        )
                        .onLongPressGesture {
                            beginRename(group)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGray6))
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("groups.page.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("common.add") {
                    beginAdd()
                }

                Button(editButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditing.toggle()
                    }
                }
            }
        }
        .task {
            await reloadGroups()
        }
        .alert(
            editTitle,
            isPresented: Binding(
                get: { isAddingGroup || editingGroup != nil },
                set: { isPresented in
                    if !isPresented {
                        cancelEditing()
                    }
                }
            )
        ) {
            TextField("groups.name.placeholder", text: $nameDraft)
            Button("common.cancel", role: .cancel) {
                cancelEditing()
            }
            Button("common.save") {
                saveGroup()
            }
        } message: {
            Text("groups.name.message")
        }
        .alert(
            "groups.delete.title",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        groupPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("common.cancel", role: .cancel) {
                groupPendingDeletion = nil
            }
            Button("library.delete", role: .destructive) {
                deletePendingGroup()
            }
        } message: {
            Text("groups.delete.message")
        }
        .alert(
            "groups.error.title",
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

    private var editTitle: LocalizedStringKey {
        isAddingGroup ? "groups.add" : "groups.rename"
    }

    private var editButtonTitle: LocalizedStringKey {
        isEditing ? "common.done" : "common.edit"
    }

    @MainActor
    private func reloadGroups() async {
        do {
            groups = try await repository.fetchGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginAdd() {
        nameDraft = ""
        editingGroup = nil
        isAddingGroup = true
    }

    private func beginRename(_ group: BookGroup) {
        nameDraft = group.name
        editingGroup = group
        isAddingGroup = false
    }

    private func cancelEditing() {
        isAddingGroup = false
        editingGroup = nil
        nameDraft = ""
    }

    private func saveGroup() {
        let group = editingGroup
        let name = nameDraft

        Task {
            do {
                if let group {
                    try await repository.renameGroup(id: group.id, name: name)
                } else {
                    _ = try await repository.createGroup(name: name)
                }
                cancelEditing()
                await reloadGroups()
                onGroupsChanged(nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingGroup() {
        guard let group = groupPendingDeletion else {
            return
        }

        Task {
            do {
                try await repository.deleteGroup(id: group.id)
                groupPendingDeletion = nil
                await reloadGroups()
                onGroupsChanged(group.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ReadingHistoryPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onOpenBook: (Book) -> Void

    @State private var historyItems: [ReadingHistoryItem] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    if historyItems.isEmpty {
                        Text("history.empty.message")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight)
                            .background(Color.white)
                    } else {
                        ForEach(historyItems) { item in
                            Button {
                                onOpenBook(item.book)
                            } label: {
                                DedicatedHistoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGray6))
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("add.reading.history")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("history.clear") {
                    clearHistory()
                }
                .disabled(historyItems.isEmpty)
            }
        }
        .task {
            await reloadHistory()
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

    @MainActor
    private func reloadHistory() async {
        do {
            historyItems = try await repository.fetchReadingHistory(limit: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        Task {
            do {
                try await repository.clearReadingHistory()
                historyItems = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct BackTextButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("<")
                Text("common.back")
            }
        }
    }
}

private struct DedicatedListRow: View {
    let title: String
    var showsDeleteControl = false
    var deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
    }
}

private struct DedicatedHistoryRow: View {
    let item: ReadingHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: item.book.title)
                .font(.body)
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
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
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

private enum DedicatedPageStyle {
    static let rowHeight: CGFloat = 54

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
    }
}
