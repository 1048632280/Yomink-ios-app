import SwiftUI
import UIKit

struct AddBookSidebarView: View {
    let onImportFromFile: () -> Void
    let onImportFromFolder: () -> Void
    let onOpenHistoryPage: () -> Void
    let onOpenRandomPickerPage: () -> Void

    init(
        onImportFromFile: @escaping () -> Void = {},
        onImportFromFolder: @escaping () -> Void = {},
        onOpenHistoryPage: @escaping () -> Void = {},
        onOpenRandomPickerPage: @escaping () -> Void = {}
    ) {
        self.onImportFromFile = onImportFromFile
        self.onImportFromFolder = onImportFromFolder
        self.onOpenHistoryPage = onOpenHistoryPage
        self.onOpenRandomPickerPage = onOpenRandomPickerPage
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
                        onImportFromFolder()
                    } label: {
                        SidebarItemRow(localizedTitle: "add.import.folder")
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenHistoryPage()
                    } label: {
                        SidebarItemRow(localizedTitle: "add.reading.history")
                    }
                    .buttonStyle(.plain)

                    Button {
                        onOpenRandomPickerPage()
                    } label: {
                        SidebarItemRow(localizedTitle: "randomPicker.title")
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
