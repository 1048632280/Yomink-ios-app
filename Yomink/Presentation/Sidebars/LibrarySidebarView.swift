import SwiftUI
import UIKit

struct LibrarySidebarView: View {
    let repository: (any LibraryRepository)?
    let groups: [BookGroup]
    let books: [Book]
    let selectedScope: LibraryScope
    let settings: LibrarySettings?
    let onSelectScope: (LibraryScope) -> Void
    let onSettingsChanged: (LibrarySettings) -> Void
    let onDisplayOptionChanged: () -> Void
    let onOpenGroupsPage: () -> Void

    @State private var librarySettings = LibrarySettings.default
    @State private var isSettingsPresented = false
    @State private var groupErrorMessage: String?

    init(
        repository: (any LibraryRepository)? = nil,
        groups: [BookGroup] = [],
        books: [Book] = [],
        selectedScope: LibraryScope = .ungrouped,
        settings: LibrarySettings? = nil,
        onSelectScope: @escaping (LibraryScope) -> Void = { _ in },
        onSettingsChanged: @escaping (LibrarySettings) -> Void = { _ in },
        onDisplayOptionChanged: @escaping () -> Void = {},
        onOpenGroupsPage: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.groups = groups
        self.books = books
        self.selectedScope = selectedScope
        self.settings = settings
        self.onSelectScope = onSelectScope
        self.onSettingsChanged = onSettingsChanged
        self.onDisplayOptionChanged = onDisplayOptionChanged
        self.onOpenGroupsPage = onOpenGroupsPage
        _librarySettings = State(initialValue: settings ?? .default)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                displayControls

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        groupHeader

                        Button {
                            onSelectScope(.ungrouped)
                        } label: {
                            SidebarItemRow(
                                localizedTitle: "sidebar.ungrouped",
                                isSelected: selectedScope == .ungrouped
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(groups) { group in
                            Button {
                                onSelectScope(.group(group.id))
                            } label: {
                                SidebarItemRow(
                                    verbatimTitle: groupTitle(group),
                                    isSelected: selectedScope == .group(group.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            onOpenGroupsPage()
                        } label: {
                            SidebarItemRow(
                                localizedTitle: "sidebar.manageGroups"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, SidebarStyle.groupHeaderHeight)
                }

                sectionGap

                Button {
                    openSettings()
                } label: {
                    SidebarItemRow(
                        localizedTitle: "settings.title"
                    )
                }
                .buttonStyle(.plain)
            }
            .navigationBarHidden(true)
            .background(SidebarStyle.background)
            .task {
                await reloadSettings()
            }
            .onChange(of: settings) { nextSettings in
                librarySettings = nextSettings ?? .default
            }
            .sheet(isPresented: $isSettingsPresented, onDismiss: {
                Task {
                    await reloadSettings()
                }
            }) {
                AppSettingsView(
                    repository: repository,
                    settings: librarySettings
                ) { settings in
                    librarySettings = settings
                    onSettingsChanged(settings)
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

    private var displayControls: some View {
        VStack(spacing: 0) {
            Button {
                toggleSortOrder()
            } label: {
                SidebarItemRow(
                    localizedTitle: librarySettings.sortOrder.sidebarTitle
                )
            }
            .buttonStyle(.plain)

            Button {
                toggleViewMode()
            } label: {
                SidebarItemRow(
                    localizedTitle: librarySettings.viewMode.toggleTargetTitle
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, SidebarStyle.groupHeaderHeight)
        .background(SidebarStyle.background)
    }

    private var groupHeader: some View {
        Text("sidebar.groups.section")
            .font(.footnote.weight(.semibold))
            .foregroundColor(SidebarStyle.secondaryText)
            .frame(maxWidth: .infinity, minHeight: SidebarStyle.groupHeaderHeight, alignment: .bottomLeading)
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
            .background(SidebarStyle.background)
    }

    private var sectionGap: some View {
        SidebarStyle.background
            .frame(height: SidebarStyle.groupHeaderHeight)
    }

    private func groupTitle(_ group: BookGroup) -> String {
        String(
            format: NSLocalizedString("sidebar.groupWithCount", comment: ""),
            group.name,
            books.filter { $0.groupID == group.id }.count
        )
    }

    private func toggleViewMode() {
        librarySettings.viewMode = librarySettings.viewMode == .list ? .grid : .list
        persistLibrarySettings(returningToShelf: true)
    }

    private func toggleSortOrder() {
        librarySettings.sortOrder = librarySettings.sortOrder == .lastReadAt ? .importedAt : .lastReadAt
        persistLibrarySettings(returningToShelf: true)
    }

    private func persistLibrarySettings(returningToShelf: Bool = false) {
        let settings = librarySettings
        onSettingsChanged(settings)
        if returningToShelf {
            onDisplayOptionChanged()
        }
        guard let repository else {
            return
        }

        Task {
            do {
                try await repository.saveLibrarySettings(settings)
            } catch {
                groupErrorMessage = error.localizedDescription
            }
        }
    }

    private func openSettings() {
        isSettingsPresented = true
    }

    @MainActor
    private func reloadSettings() async {
        guard let repository else {
            librarySettings = settings ?? .default
            return
        }

        if let settings {
            librarySettings = settings
        } else if let fetchedSettings = try? await repository.fetchLibrarySettings() {
            librarySettings = fetchedSettings
        }
    }
}

struct SidebarItemRow: View {
    private enum Title {
        case localized(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    let isSelected: Bool

    init(
        localizedTitle: LocalizedStringKey,
        isSelected: Bool = false
    ) {
        self.title = .localized(localizedTitle)
        self.isSelected = isSelected
    }

    init(
        verbatimTitle: String,
        isSelected: Bool = false
    ) {
        self.title = .verbatim(verbatimTitle)
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 12) {
            titleText
                .font(.body.weight(.medium))
                .foregroundColor(SidebarStyle.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SidebarStyle.primaryText)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: SidebarStyle.itemHeight, alignment: .leading)
        .background(SidebarStyle.rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SidebarStyle.separator)
                .frame(height: 0.5)
        }
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

    var sidebarTitle: LocalizedStringKey {
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

    var toggleTargetTitle: LocalizedStringKey {
        switch self {
        case .list:
            return "settings.viewMode.gridMode"
        case .grid:
            return "settings.viewMode.listMode"
        }
    }
}
