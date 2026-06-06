import Foundation
import SwiftUI
import UIKit

struct LibraryTagsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let sortOrder: LibrarySettings.SortOrder
    let onOpenBook: (Book) -> Void

    @State private var tagUsages: [BookTagUsage] = []
    @State private var selectedUsage: BookTagUsage?
    @State private var tagNameEditorPresented = false
    @State private var isEditingTags = false
    @State private var tagPendingDeletion: BookTagUsage?
    @State private var tagNameDraft = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tagUsages.isEmpty {
                        emptyTagsView
                    } else {
                        tagCloudCard
                        tagListCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }

            tagRouteLink

            if tagNameEditorPresented {
                DedicatedPromptOverlay(
                    title: "tags.new",
                    message: "tags.name.message",
                    text: $tagNameDraft,
                    placeholder: NSLocalizedString("tags.name.placeholder", comment: ""),
                    confirmTitle: "common.save",
                    confirmRole: nil,
                    confirmAction: createTag,
                    cancelAction: cancelCreatingTag
                )
            }

            if tagPendingDeletion != nil {
                DedicatedConfirmationOverlay(
                    title: "tags.delete.title",
                    message: "tags.delete.message",
                    confirmTitle: "tags.delete.action",
                    confirmRole: .destructive,
                    confirmAction: deletePendingTag,
                    cancelAction: {
                        tagPendingDeletion = nil
                    }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("tags.page.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("common.new") {
                    beginCreatingTag()
                }

                if !tagUsages.isEmpty {
                    Button(tagEditButtonTitle) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditingTags.toggle()
                        }
                    }
                }
            }
        }
        .task {
            await reloadTags()
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

    private var emptyTagsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("tags.empty.message")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("tags.new") {
                beginCreatingTag()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .storageCardStyle()
    }

    private var tagCloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("tags.cloud.title")
                .font(.headline)
                .foregroundColor(.primary)

            TagWordCloudView(tagUsages: tagUsages) { usage in
                selectedUsage = usage
            }
            .frame(height: 260)
        }
        .storageCardStyle()
    }

    private var tagEditButtonTitle: LocalizedStringKey {
        isEditingTags ? "common.done" : "common.edit"
    }

    private var tagListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tags.all.title")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                ForEach(Array(tagUsages.enumerated()), id: \.element.id) { index, usage in
                    if isEditingTags {
                        LibraryTagListRow(
                            usage: usage,
                            countText: countText(for: usage.bookCount),
                            isEditing: true,
                            deleteAction: {
                                tagPendingDeletion = usage
                            }
                        )
                    } else {
                        Button {
                            selectedUsage = usage
                        } label: {
                            LibraryTagListRow(
                                usage: usage,
                                countText: countText(for: usage.bookCount),
                                isEditing: false,
                                deleteAction: {}
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if index < tagUsages.count - 1 {
                        SettingsPageStyle.separator
                    }
                }
            }
        }
        .storageCardStyle()
    }

    private var tagRouteLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { selectedUsage != nil },
                set: { isActive in
                    if !isActive {
                        selectedUsage = nil
                    }
                }
            )
        ) {
            if let selectedUsage {
                TaggedBooksPage(
                    tag: selectedUsage.tag,
                    repository: repository,
                    sortOrder: sortOrder,
                    onOpenBook: onOpenBook
                )
            } else {
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .hidden()
        .frame(width: 0, height: 0)
    }

    private func countText(for count: Int) -> String {
        String(
            format: NSLocalizedString("tags.count.format", comment: ""),
            count
        )
    }

    @MainActor
    private func reloadTags() async {
        do {
            tagUsages = try await repository.fetchTagsWithUsage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCreatingTag() {
        tagNameDraft = ""
        tagNameEditorPresented = true
    }

    private func cancelCreatingTag() {
        tagNameDraft = ""
        tagNameEditorPresented = false
    }

    private func createTag() {
        let name = tagNameDraft

        Task {
            do {
                _ = try await repository.createTag(name: name)
                cancelCreatingTag()
                await reloadTags()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingTag() {
        guard let usage = tagPendingDeletion else {
            return
        }

        Task {
            do {
                try await repository.deleteTag(id: usage.id)
                if selectedUsage?.id == usage.id {
                    selectedUsage = nil
                }
                tagPendingDeletion = nil
                await reloadTags()
                if tagUsages.isEmpty {
                    isEditingTags = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
