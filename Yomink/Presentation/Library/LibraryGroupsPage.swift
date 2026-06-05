import Foundation
import SwiftUI
import UIKit

struct LibraryGroupsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onGroupsChanged: (UUID?) -> Void

    @State private var groups: [BookGroup] = []
    @State private var books: [Book] = []
    @State private var isEditing = false
    @State private var groupNameEditor: GroupNameEditor?
    @State private var groupPendingDeletion: BookGroup?
    @State private var nameDraft = ""
    @State private var errorMessage: String?
    @State private var pressedGroupID: UUID?
    @State private var draggedGroupID: UUID?
    @State private var reorderStartIndex: Int?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    DedicatedGroupListRow(
                        title: groupTitle(
                            name: NSLocalizedString("sidebar.ungrouped", comment: ""),
                            count: books.filter { $0.groupID == nil }.count
                        )
                    )

                    ForEach(groups) { group in
                        DedicatedGroupListRow(
                            title: groupTitle(
                                name: group.name,
                                count: books.filter { $0.groupID == group.id }.count
                            ),
                            showsDeleteControl: isEditing,
                            showsReorderControl: isEditing,
                            isPressed: pressedGroupID == group.id,
                            isDragging: draggedGroupID == group.id,
                            dragOffset: dragOffset(for: group),
                            deleteAction: {
                                groupPendingDeletion = group
                            },
                            reorderDragChanged: { translation in
                                reorderGroup(group, translation: translation)
                            },
                            reorderDragEnded: {
                                finishReordering()
                            }
                        )
                        .overlay {
                            if !isEditing {
                                NonBlockingLongPressRecognizer(
                                    isEnabled: true,
                                    onBegan: {
                                        pressedGroupID = group.id
                                    },
                                    onEnded: {
                                        pressedGroupID = nil
                                    },
                                    onRecognized: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                            pressedGroupID = nil
                                            beginRename(group)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGray6))
            .animation(.easeInOut(duration: 0.18), value: isEditing)

            if groupNameEditor != nil {
                groupNameOverlay
            }

            if groupPendingDeletion != nil {
                deleteConfirmationOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("groups.page.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("common.new") {
                    beginAdd()
                }

                Button(editButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditing.toggle()
                        pressedGroupID = nil
                    }
                }
            }
        }
        .task {
            await reloadGroups()
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
        groupNameEditor?.title ?? "groups.new"
    }

    private var editButtonTitle: LocalizedStringKey {
        isEditing ? "common.done" : "common.edit"
    }

    private var groupNameOverlay: some View {
        DedicatedPromptOverlay(
            title: editTitle,
            message: "groups.name.message",
            text: $nameDraft,
            placeholder: NSLocalizedString("groups.name.placeholder", comment: ""),
            confirmTitle: "common.save",
            confirmRole: nil,
            confirmAction: saveGroup,
            cancelAction: cancelEditing
        )
    }

    private var deleteConfirmationOverlay: some View {
        DedicatedConfirmationOverlay(
            title: "groups.delete.title",
            message: "groups.delete.message",
            confirmTitle: "library.delete",
            confirmRole: .destructive,
            confirmAction: deletePendingGroup,
            cancelAction: {
                groupPendingDeletion = nil
            }
        )
    }

    @MainActor
    private func reloadGroups() async {
        do {
            groups = try await repository.fetchGroups()
            books = try await repository.fetchBooks(scope: .all, sortOrder: .lastReadAt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginAdd() {
        nameDraft = ""
        groupNameEditor = .new
    }

    private func beginRename(_ group: BookGroup) {
        nameDraft = group.name
        groupNameEditor = .rename(group)
    }

    private func cancelEditing() {
        groupNameEditor = nil
        nameDraft = ""
    }

    private func saveGroup() {
        let editor = groupNameEditor
        let name = nameDraft

        Task {
            do {
                if case let .rename(group) = editor {
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

    private func persistGroupOrder() {
        let ids = groups.map(\.id)

        Task {
            do {
                try await repository.reorderGroups(ids: ids)
                await reloadGroups()
                onGroupsChanged(nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reorderGroup(_ group: BookGroup, translation: CGSize) {
        dragTranslation = translation

        if draggedGroupID != group.id {
            draggedGroupID = group.id
            reorderStartIndex = groups.firstIndex(of: group)
        }

        guard let startIndex = reorderStartIndex,
              let currentIndex = groups.firstIndex(where: { $0.id == group.id })
        else {
            return
        }

        let offset = Int((translation.height / DedicatedPageStyle.rowHeight).rounded())
        let targetIndex = min(max(startIndex + offset, 0), max(groups.count - 1, 0))

        guard targetIndex != currentIndex else {
            return
        }

        withAnimation(DedicatedPageStyle.reorderAnimation) {
            groups.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    private func finishReordering() {
        guard draggedGroupID != nil else {
            return
        }

        withAnimation(DedicatedPageStyle.reorderAnimation) {
            draggedGroupID = nil
            reorderStartIndex = nil
            dragTranslation = .zero
        }
        persistGroupOrder()
    }

    private func dragOffset(for group: BookGroup) -> CGSize {
        guard draggedGroupID == group.id,
              let startIndex = reorderStartIndex,
              let currentIndex = groups.firstIndex(where: { $0.id == group.id })
        else {
            return .zero
        }

        let settledOffset = CGFloat(currentIndex - startIndex) * DedicatedPageStyle.rowHeight
        return CGSize(width: 0, height: dragTranslation.height - settledOffset)
    }

    private func groupTitle(name: String, count: Int) -> String {
        String(
            format: NSLocalizedString("sidebar.groupWithCount", comment: ""),
            name,
            count
        )
    }
}

private enum GroupNameEditor {
    case new
    case rename(BookGroup)

    var title: LocalizedStringKey {
        switch self {
        case .new:
            return "groups.new"
        case .rename:
            return "groups.rename"
        }
    }
}

