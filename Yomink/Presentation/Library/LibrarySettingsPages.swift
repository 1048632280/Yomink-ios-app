import Foundation
import SwiftUI
import UIKit

struct LibrarySettingsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let fileStore: AppFileStore
    let onOpenBook: (Book) -> Void
    let onLibraryChanged: () -> Void
    let onChange: (LibrarySettings) -> Void
    let currentSettings: LibrarySettings

    @State private var settings: LibrarySettings

    init(
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        settings: LibrarySettings,
        onOpenBook: @escaping (Book) -> Void,
        onLibraryChanged: @escaping () -> Void,
        onChange: @escaping (LibrarySettings) -> Void
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.onOpenBook = onOpenBook
        self.onLibraryChanged = onLibraryChanged
        self.onChange = onChange
        self.currentSettings = settings
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
        }
        .onChange(of: currentSettings) { nextSettings in
            settings = nextSettings
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

            SettingsPageStyle.separator

            NavigationLink {
                StorageManagementPage(
                    repository: repository,
                    fileStore: fileStore,
                    onOpenBook: onOpenBook,
                    onLibraryChanged: onLibraryChanged
                )
            } label: {
                SettingsListRow(
                    title: "storage.title",
                    value: "settings.storage.open"
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

