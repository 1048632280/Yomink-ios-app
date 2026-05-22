import SwiftUI

struct LibrarySidebarView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("sidebar.groups.section") {
                    Label("sidebar.allBooks", systemImage: "book")
                    Label("sidebar.ungrouped", systemImage: "tray")
                }

                Section {
                    NavigationLink {
                        GroupManagementPlaceholderView()
                    } label: {
                        Label("sidebar.manageGroups", systemImage: "folder.badge.gearshape")
                    }
                }

                Section {
                    Label("settings.title", systemImage: "gearshape")
                }
            }
            .navigationTitle("library.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        dismiss()
                    }
                }
            }
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
    }
}
