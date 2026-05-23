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

                List {
                    Section("sidebar.groups.section") {
                        Label("sidebar.allBooks", systemImage: "book")
                        Label("sidebar.ungrouped", systemImage: "tray")

                        ForEach(groups) { group in
                            Label {
                                Text(verbatim: group.name)
                            } icon: {
                                Image(systemName: "folder")
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            GroupManagementPlaceholderView()
                        } label: {
                            Label("sidebar.manageGroups", systemImage: "folder.badge.gearshape")
                        }
                    }
                }
                .listStyle(.insetGrouped)

                Divider()

                Label("settings.title", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
            .navigationBarHidden(true)
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
        .background(Color(UIColor.secondarySystemBackground))
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
