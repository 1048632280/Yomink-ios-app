import SwiftUI
import UIKit

struct LibrarySidebarView: View {
    let repository: (any LibraryRepository)?
    let selectedScope: LibraryScope
    let settings: LibrarySettings?
    let onSelectScope: (LibraryScope) -> Void
    let onGroupsChanged: () -> Void
    let onSettingsChanged: (LibrarySettings) -> Void

    @State private var groups: [BookGroup] = []
    @State private var librarySettings = LibrarySettings.default
    @State private var activeSheet: SidebarSheet?
    @State private var groupErrorMessage: String?

    init(
        repository: (any LibraryRepository)? = nil,
        selectedScope: LibraryScope = .all,
        settings: LibrarySettings? = nil,
        onSelectScope: @escaping (LibraryScope) -> Void = { _ in },
        onGroupsChanged: @escaping () -> Void = {},
        onSettingsChanged: @escaping (LibrarySettings) -> Void = { _ in }
    ) {
        self.repository = repository
        self.selectedScope = selectedScope
        self.settings = settings
        self.onSelectScope = onSelectScope
        self.onGroupsChanged = onGroupsChanged
        self.onSettingsChanged = onSettingsChanged
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                sidebarHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("sidebar.groups.section")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .padding(.bottom, 4)

                        Button {
                            onSelectScope(.all)
                        } label: {
                            SidebarItemRow(
                                localizedTitle: "sidebar.allBooks",
                                systemImage: "book",
                                isSelected: selectedScope == .all
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onSelectScope(.ungrouped)
                        } label: {
                            SidebarItemRow(
                                localizedTitle: "sidebar.ungrouped",
                                systemImage: "tray",
                                isSelected: selectedScope == .ungrouped
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(groups) { group in
                            Button {
                                onSelectScope(.group(group.id))
                            } label: {
                                SidebarItemRow(
                                    verbatimTitle: group.name,
                                    systemImage: "folder",
                                    isSelected: selectedScope == .group(group.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            activeSheet = .groups
                        } label: {
                            SidebarItemRow(
                                localizedTitle: "sidebar.manageGroups",
                                systemImage: "folder.badge.gearshape"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 16)
                }

                Divider()

                Button {
                    activeSheet = .settings
                } label: {
                    SidebarItemRow(
                        localizedTitle: "settings.title",
                        systemImage: "gearshape"
                    )
                    .padding(.vertical, 10)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }
            .navigationBarHidden(true)
            .background(Color(.systemGray6))
            .task {
                await reloadGroups()
            }
            .sheet(item: $activeSheet, onDismiss: {
                Task {
                    await reloadGroups()
                }
            }) { sheet in
                switch sheet {
                case .groups:
                    GroupManagementView(
                        repository: repository,
                        onGroupsChanged: onGroupsChanged
                    )
                case .settings:
                    AppSettingsView(
                        repository: repository,
                        settings: librarySettings
                    ) { settings in
                        librarySettings = settings
                        onSettingsChanged(settings)
                    }
                }
            }
            .alert(
                "groups.error.title",
                isPresented: Binding(
                    get: { groupErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            groupErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    groupErrorMessage = nil
                }
            } message: {
                Text(groupErrorMessage ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("sidebar.header.placeholder")
                .font(.headline)
            Text("sidebar.header.subtitle")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color(.systemGray6))
    }

    @MainActor
    private func reloadGroups() async {
        guard let repository else {
            groups = []
            return
        }

        do {
            if let settings {
                librarySettings = settings
            } else if let fetchedSettings = try? await repository.fetchLibrarySettings() {
                librarySettings = fetchedSettings
            }
            groups = try await repository.fetchGroups()
        } catch {
            groupErrorMessage = error.localizedDescription
        }
    }
}

struct SidebarItemRow: View {
    private enum Title {
        case localized(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    let systemImage: String
    let isSelected: Bool

    init(
        localizedTitle: LocalizedStringKey,
        systemImage: String,
        isSelected: Bool = false
    ) {
        self.title = .localized(localizedTitle)
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    init(
        verbatimTitle: String,
        systemImage: String,
        isSelected: Bool = false
    ) {
        self.title = .verbatim(verbatimTitle)
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    var body: some View {
        Label {
            titleText
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundColor(.accentColor)
                .frame(width: 28)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(.horizontal, 12)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleText: some View {
        switch title {
        case let .localized(title):
            Text(title)
        case let .verbatim(title):
            Text(verbatim: title)
        }
    }
}

private struct GroupManagementView: View {
    let repository: (any LibraryRepository)?
    let onGroupsChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [BookGroup] = []
    @State private var editingGroup: BookGroup?
    @State private var isAddingGroup = false
    @State private var nameDraft = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                if groups.isEmpty {
                    Text("groups.empty.message")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(groups) { group in
                        Button {
                            beginRename(group)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundColor(.accentColor)
                                Text(verbatim: group.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteGroups)
                }
            }
            .navigationTitle("sidebar.manageGroups")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        beginAdd()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("groups.add"))
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
    }

    private var editTitle: LocalizedStringKey {
        isAddingGroup ? "groups.add" : "groups.rename"
    }

    @MainActor
    private func reloadGroups() async {
        guard let repository else {
            groups = []
            return
        }

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
        guard let repository else {
            cancelEditing()
            return
        }

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
                onGroupsChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteGroups(at offsets: IndexSet) {
        guard let repository else {
            return
        }

        let ids = offsets.compactMap { index in
            groups.indices.contains(index) ? groups[index].id : nil
        }

        Task {
            do {
                for id in ids {
                    try await repository.deleteGroup(id: id)
                }
                await reloadGroups()
                onGroupsChanged()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AppSettingsView: View {
    let repository: (any LibraryRepository)?
    let onChange: (LibrarySettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: LibrarySettings
    @State private var errorMessage: String?

    init(
        repository: (any LibraryRepository)?,
        settings: LibrarySettings,
        onChange: @escaping (LibrarySettings) -> Void
    ) {
        self.repository = repository
        self.onChange = onChange
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("settings.sortOrder", selection: sortOrderBinding) {
                        ForEach(LibrarySettings.SortOrder.allCases, id: \.self) { sortOrder in
                            Text(sortOrder.localizedTitle)
                                .tag(sortOrder)
                        }
                    }

                    Picker("settings.viewMode", selection: viewModeBinding) {
                        ForEach(LibrarySettings.ViewMode.allCases, id: \.self) { viewMode in
                            Text(viewMode.localizedTitle)
                                .tag(viewMode)
                        }
                    }
                }
            }
                .navigationTitle("settings.title")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.close") {
                            dismiss()
                        }
                    }
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
    }

    private var sortOrderBinding: Binding<LibrarySettings.SortOrder> {
        Binding(
            get: { settings.sortOrder },
            set: { newValue in
                settings.sortOrder = newValue
                persistSettings()
            }
        )
    }

    private var viewModeBinding: Binding<LibrarySettings.ViewMode> {
        Binding(
            get: { settings.viewMode },
            set: { newValue in
                settings.viewMode = newValue
                persistSettings()
            }
        )
    }

    private func persistSettings() {
        let settings = settings
        onChange(settings)

        guard let repository else {
            return
        }

        Task {
            do {
                try await repository.saveLibrarySettings(settings)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private extension LibrarySettings.SortOrder {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .importedAt:
            return "library.sort.importedAt"
        case .lastReadAt:
            return "library.sort.lastReadAt"
        }
    }
}

private extension LibrarySettings.ViewMode {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .list:
            return "settings.viewMode.list"
        case .grid:
            return "settings.viewMode.grid"
        }
    }
}

private enum SidebarSheet: Identifiable {
    case groups
    case settings

    var id: String {
        switch self {
        case .groups:
            return "groups"
        case .settings:
            return "settings"
        }
    }
}
