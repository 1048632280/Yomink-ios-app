import SwiftUI

struct LibrarySidebarView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("书架分组") {
                    Label("全部书籍", systemImage: "book")
                    Label("未分组", systemImage: "tray")
                }

                Section {
                    NavigationLink {
                        GroupManagementPlaceholderView()
                    } label: {
                        Label("管理分组", systemImage: "folder.badge.gearshape")
                    }
                }

                Section {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct GroupManagementPlaceholderView: View {
    var body: some View {
        Text("Phase 4 将实现新增、编辑、删除分组。")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding()
            .navigationTitle("管理分组")
    }
}

