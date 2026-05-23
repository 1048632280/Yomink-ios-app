import SwiftUI
import UIKit

struct AddBookSidebarView: View {
    let onImportFromFile: () -> Void

    init(onImportFromFile: @escaping () -> Void = {}) {
        self.onImportFromFile = onImportFromFile
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                sidebarHeader

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
                .listStyle(.insetGrouped)
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("add.header.placeholder")
                .font(.headline)
            Text("add.header.subtitle")
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
