import Foundation
import SwiftUI
import UIKit

struct BookTagPickerPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    @Binding var selectedTagIDs: Set<UUID>
    let onCatalogChanged: () -> Void
    let onSelectionFinished: (Set<UUID>) -> Void

    @State private var tagUsages: [BookTagUsage] = []
    @State private var tagNameEditorPresented = false
    @State private var tagNameDraft = ""
    @State private var errorMessage: String?

    init(
        repository: any LibraryRepository,
        selectedTagIDs: Binding<Set<UUID>>,
        onCatalogChanged: @escaping () -> Void = {},
        onSelectionFinished: @escaping (Set<UUID>) -> Void = { _ in }
    ) {
        self.repository = repository
        _selectedTagIDs = selectedTagIDs
        self.onCatalogChanged = onCatalogChanged
        self.onSelectionFinished = onSelectionFinished
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    if tagUsages.isEmpty {
                        Text("tags.empty.message")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        ForEach(Array(tagUsages.enumerated()), id: \.element.id) { index, usage in
                            Button {
                                toggleTag(usage.tag)
                            } label: {
                                BookTagSelectionRow(
                                    usage: usage,
                                    isSelected: selectedTagIDs.contains(usage.id)
                                )
                            }
                            .buttonStyle(.plain)

                            if index < tagUsages.count - 1 {
                                SettingsPageStyle.separator
                            }
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }

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
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("tags.select.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("common.new") {
                    beginCreatingTag()
                }
            }
        }
        .task {
            await reloadTags()
        }
        .onDisappear {
            onSelectionFinished(selectedTagIDs)
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

    private func toggleTag(_ tag: BookTag) {
        if selectedTagIDs.contains(tag.id) {
            selectedTagIDs.remove(tag.id)
        } else {
            selectedTagIDs.insert(tag.id)
        }
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
                let tag = try await repository.createTag(name: name)
                selectedTagIDs.insert(tag.id)
                cancelCreatingTag()
                await reloadTags()
                onCatalogChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct BookTagSelectionRow: View {
    let usage: BookTagUsage
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: usage.tag.name)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(countText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .monospacedDigit()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.semibold))
                .foregroundColor(isSelected ? .accentColor : Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    private var countText: String {
        String(
            format: NSLocalizedString("tags.count.format", comment: ""),
            usage.bookCount
        )
    }
}

private struct BookTagBubble: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.accentColor)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(8)
    }
}

private struct NonBlockingLongPressRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onEnded: () -> Void
    let onRecognized: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.isRecognizerEnabled = isEnabled
        view.onBegan = onBegan
        view.onEnded = onEnded
        view.onRecognized = onRecognized
        view.isUserInteractionEnabled = isEnabled
    }

    final class TouchView: UIView {
        var isRecognizerEnabled = false
        var onBegan: () -> Void
        var onEnded: () -> Void
        var onRecognized: () -> Void
        private var startPoint: CGPoint?
        private var isPressing = false
        private var recognitionWorkItem: DispatchWorkItem?

        init() {
            onBegan = {}
            onEnded = {}
            onRecognized = {}
            super.init(frame: .zero)
            isMultipleTouchEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            guard isRecognizerEnabled,
                  let touch = touches.first
            else {
                return
            }

            startPoint = touch.location(in: self)
            isPressing = true
            onBegan()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.isPressing
                else {
                    return
                }
                self.onRecognized()
            }
            recognitionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            guard let startPoint,
                  let touch = touches.first
            else {
                return
            }

            let point = touch.location(in: self)
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance > 10 {
                cancelPress()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            cancelPress()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            cancelPress()
        }

        private func cancelPress() {
            recognitionWorkItem?.cancel()
            recognitionWorkItem = nil
            startPoint = nil
            guard isPressing else {
                return
            }
            isPressing = false
            onEnded()
        }
    }
}

