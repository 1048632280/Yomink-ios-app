import SwiftUI
import UIKit

struct LibrarySidebarView: View {
    let repository: (any LibraryRepository)?
    @State private var groups: [BookGroup] = []

    init(repository: (any LibraryRepository)? = nil) {
        self.repository = repository
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

                        SidebarItemRow(
                            title: "sidebar.allBooks",
                            systemImage: "book"
                        )
                        SidebarItemRow(
                            title: "sidebar.ungrouped",
                            systemImage: "tray"
                        )

                        ForEach(groups) { group in
                            SidebarItemRow(
                                title: group.name,
                                systemImage: "folder",
                                isLocalized: false
                            )
                        }

                        NavigationLink {
                            GroupManagementPlaceholderView()
                        } label: {
                            SidebarItemRow(
                                title: "sidebar.manageGroups",
                                systemImage: "folder.badge.gearshape"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                    .padding(.bottom, 16)
                }

                Divider()

                SidebarItemRow(
                    title: "settings.title",
                    systemImage: "gearshape"
                )
                .padding(.vertical, 10)
            }
            .navigationBarHidden(true)
            .background(Color(.systemGray6))
            .task {
                guard let repository else {
                    return
                }
                groups = (try? await repository.fetchGroups()) ?? []
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
        .padding(.top, 24)
        .padding(.bottom, 16)
        .background(Color(.systemGray6))
    }
}

struct SidebarItemRow: View {
    let title: String
    let systemImage: String
    var isLocalized = true

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
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleText: some View {
        if isLocalized {
            Text(title)
        } else {
            Text(verbatim: title)
        }
    }
}

private struct GroupManagementPlaceholderView: View {
    var body: some View {
        Text("groups.placeholder.message")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding()
            .navigationTitle("sidebar.manageGroups")
            .navigationBarHidden(false)
    }
}
