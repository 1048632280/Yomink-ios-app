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

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Button {
                            onImportFromFile()
                        } label: {
                            SidebarItemRow(
                                title: "add.import.file",
                                systemImage: "square.and.arrow.down"
                            )
                        }
                        .buttonStyle(.plain)

                        SidebarItemRow(
                            title: "add.reading.history",
                            systemImage: "clock"
                        )
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarHidden(true)
            .background(Color(.systemGray6))
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
        .background(Color(.systemGray6))
    }
}
