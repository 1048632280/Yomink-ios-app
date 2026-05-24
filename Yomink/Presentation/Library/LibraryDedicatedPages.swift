import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var draggingGroup: BookGroup?

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
                            reorderProvider: {
                                draggingGroup = group
                                return NSItemProvider(object: group.id.uuidString as NSString)
                            }
                        )
                        .overlay {
                            NonBlockingLongPressRecognizer(
                                isEnabled: !isEditing,
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
                        .onDrop(
                            of: [UTType.text],
                            delegate: GroupReorderDropDelegate(
                                item: group,
                                groups: $groups,
                                draggingGroup: $draggingGroup,
                                persistOrder: persistGroupOrder
                            )
                        )
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

private struct GroupReorderDropDelegate: DropDelegate {
    let item: BookGroup
    @Binding var groups: [BookGroup]
    @Binding var draggingGroup: BookGroup?
    let persistOrder: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingGroup,
              draggingGroup != item,
              let fromIndex = groups.firstIndex(of: draggingGroup),
              let toIndex = groups.firstIndex(of: item)
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            groups.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggingGroup != nil else {
            return false
        }

        draggingGroup = nil
        persistOrder()
        return true
    }
}

private struct NonBlockingLongPressRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onEnded: () -> Void
    let onRecognized: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onEnded: onEnded,
            onRecognized: onRecognized
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.45
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer

        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onEnded = onEnded
        context.coordinator.onRecognized = onRecognized
        context.coordinator.recognizer?.isEnabled = isEnabled
        view.isUserInteractionEnabled = isEnabled
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onEnded: () -> Void
        var onRecognized: () -> Void
        weak var recognizer: UILongPressGestureRecognizer?

        init(
            onBegan: @escaping () -> Void,
            onEnded: @escaping () -> Void,
            onRecognized: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onEnded = onEnded
            self.onRecognized = onRecognized
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onBegan()
                onRecognized()
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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
    var reorderProvider: (() -> NSItemProvider)?

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

            if showsReorderControl {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(.systemGray2))
                    .frame(width: 36, height: DedicatedPageStyle.rowHeight)
                    .contentShape(Rectangle())
                    .onDrag {
                        reorderProvider?() ?? NSItemProvider()
                    }
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
