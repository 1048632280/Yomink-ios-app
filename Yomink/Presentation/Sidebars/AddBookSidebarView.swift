import SwiftUI

struct AddBookSidebarView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Label("从文件导入", systemImage: "square.and.arrow.down")
                    Label("足迹", systemImage: "clock")
                }
            }
            .navigationTitle("添加")
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

