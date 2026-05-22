import SwiftUI

struct AddBookSidebarView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Label("add.import.file", systemImage: "square.and.arrow.down")
                    Label("add.reading.history", systemImage: "clock")
                }
            }
            .navigationTitle("add.title")
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
