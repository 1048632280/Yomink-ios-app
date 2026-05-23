import SwiftUI
import UIKit

struct AddBookSidebarView: View {
    let onImportFromFile: () -> Void
    let onOpenHistoryPage: () -> Void

    init(
        onImportFromFile: @escaping () -> Void = {},
        onOpenHistoryPage: @escaping () -> Void = {}
    ) {
        self.onImportFromFile = onImportFromFile
        self.onOpenHistoryPage = onOpenHistoryPage
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Button {
                        onImportFromFile()
                    } label: {
                        SidebarItemRow(localizedTitle: "add.import.file")
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenHistoryPage()
                    } label: {
                        SidebarItemRow(localizedTitle: "add.reading.history")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, SidebarStyle.groupHeaderHeight)
                .padding(.bottom, SidebarStyle.groupHeaderHeight)
            }
            .navigationBarHidden(true)
            .background(SidebarStyle.background)
        }
        .navigationViewStyle(.stack)
    }
}
