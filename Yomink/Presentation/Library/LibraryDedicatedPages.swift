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

        withAnimation(.easeInOut(duration: 0.18)) {
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

        draggedGroupID = nil
        reorderStartIndex = nil
        persistGroupOrder()
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

            if historyItems.isEmpty {
                Text("history.empty.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyItems) { item in
                            Button {
                                onOpenBook(item.book)
                            } label: {
                                DedicatedHistoryRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGray6))
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
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

struct LibrarySettingsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onChange: (LibrarySettings) -> Void

    @State private var settings: LibrarySettings
    @State private var errorMessage: String?

    init(
        repository: any LibraryRepository,
        settings: LibrarySettings,
        onChange: @escaping (LibrarySettings) -> Void
    ) {
        self.repository = repository
        self.onChange = onChange
        _settings = State(initialValue: settings)
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    settingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
            .background(Color(.systemGray6))
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("settings.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .onChange(of: settings) { nextSettings in
            onChange(nextSettings)
            persistSettings(nextSettings)
        }
        .alert(
            "settings.error.title",
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

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SettingsSortOrderPage(selection: $settings.sortOrder)
            } label: {
                SettingsListRow(
                    title: "settings.sortOrder",
                    value: settings.sortOrder.localizedTitle
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                SettingsViewModePage(selection: $settings.viewMode)
            } label: {
                SettingsListRow(
                    title: "settings.viewMode",
                    value: settings.viewMode.localizedTitle
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func persistSettings(_ settings: LibrarySettings) {
        Task {
            do {
                try await repository.saveLibrarySettings(settings)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SettingsSortOrderPage: View {
    @Binding var selection: LibrarySettings.SortOrder

    var body: some View {
        SettingsOptionListPage(title: "settings.sortOrder") {
            ForEach(Array(LibrarySettings.SortOrder.allCases.enumerated()), id: \.element) { index, sortOrder in
                Button {
                    selection = sortOrder
                } label: {
                    SettingsOptionRow(
                        title: sortOrder.localizedTitle,
                        isSelected: selection == sortOrder
                    )
                }
                .buttonStyle(.plain)

                if index < LibrarySettings.SortOrder.allCases.count - 1 {
                    SettingsPageStyle.separator
                }
            }
        }
    }
}

private struct SettingsViewModePage: View {
    @Binding var selection: LibrarySettings.ViewMode

    var body: some View {
        SettingsOptionListPage(title: "settings.viewMode") {
            ForEach(Array(LibrarySettings.ViewMode.allCases.enumerated()), id: \.element) { index, viewMode in
                Button {
                    selection = viewMode
                } label: {
                    SettingsOptionRow(
                        title: viewMode.localizedTitle,
                        isSelected: selection == viewMode
                    )
                }
                .buttonStyle(.plain)

                if index < LibrarySettings.ViewMode.allCases.count - 1 {
                    SettingsPageStyle.separator
                }
            }
        }
    }
}

private struct SettingsOptionListPage<Content: View>: View {
    let title: LocalizedStringKey
    private let content: () -> Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

private struct DedicatedPromptOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var text: String
    let placeholder: String
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }
}

private struct DedicatedConfirmationOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
    }
}

private struct DedicatedModalBackdrop<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Color.black.opacity(0.28)
            .ignoresSafeArea()
            .overlay {
                content()
                    .frame(width: 270)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
    }
}

private struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        DispatchQueue.main.async {
            context.coordinator.restoreGesture(on: controller.navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?

        func restoreGesture(on navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer
            else {
                return
            }

            self.navigationController = navigationController
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    final class Controller: UIViewController {
        var onMoveToNavigationController: ((UINavigationController?) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onMoveToNavigationController?(navigationController)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onMoveToNavigationController?(navigationController)
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

private struct DedicatedGroupListRow: View {
    let title: String
    var showsDeleteControl = false
    var showsReorderControl = false
    var isPressed = false
    var deleteAction: (() -> Void)?
    var reorderDragChanged: ((CGSize) -> Void)?
    var reorderDragEnded: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("library.delete"))
                .zIndex(2)
                .allowsHitTesting(true)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showsReorderControl {
                ReorderHandle(
                    onChanged: { translation in
                        reorderDragChanged?(translation)
                    },
                    onEnded: {
                        reorderDragEnded?()
                    }
                )
                .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                .zIndex(2)
                .accessibilityLabel(Text("groups.reorder"))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(isPressed ? Color(.systemGray5) : Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
    }
}

private struct ReorderHandle: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> HandleView {
        let view = HandleView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let imageView = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        imageView.tintColor = .systemGray2
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        view.panGesture = panGesture
        context.coordinator.view = view

        return view
    }

    func updateUIView(_ view: HandleView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.view = view
    }

    final class HandleView: UIView {
        weak var panGesture: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let panGesture else {
                return
            }
            nearestScrollView()?.panGestureRecognizer.require(toFail: panGesture)
        }

        private func nearestScrollView() -> UIScrollView? {
            var parent = superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void
        weak var view: UIView?

        init(
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .began:
                setParentScrollEnabled(false)
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .changed:
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                setParentScrollEnabled(true)
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func setParentScrollEnabled(_ isEnabled: Bool) {
            nearestScrollView(from: view)?.isScrollEnabled = isEnabled
        }

        private func nearestScrollView(from view: UIView?) -> UIScrollView? {
            var parent = view?.superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }
}

private struct DedicatedHistoryRow: View {
    let item: ReadingHistoryItem

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: item.book.title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(historyDateText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.compactRowHeight, alignment: .leading)
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
    static let compactRowHeight: CGFloat = 44
    static let controlHitWidth: CGFloat = 44

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
    }
}

private struct SettingsListRow: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: SettingsPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private struct SettingsOptionRow: View {
    let title: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: SettingsPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private enum SettingsPageStyle {
    static let rowHeight: CGFloat = 50

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}
