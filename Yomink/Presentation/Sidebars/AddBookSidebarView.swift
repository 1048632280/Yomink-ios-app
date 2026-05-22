import SwiftUI

struct AddBookSidebarView: View {
    @Environment(\.dismiss) private var dismiss
    let onImportFromFile: () -> Void

    init(onImportFromFile: @escaping () -> Void = {}) {
        self.onImportFromFile = onImportFromFile
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        onImportFromFile()
                    } label: {
                        Label("add.import.file", systemImage: "square.and.arrow.down")
                    }
                    .foregroundColor(.primary)
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
