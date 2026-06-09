import SwiftUI
import UIKit

struct ReaderV2HostView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var book: Book
    let fileStore: AppFileStore
    let repository: any LibraryRepository
    let onStatusBarHiddenChange: (Bool) -> Void

    init(
        book: Book,
        fileStore: AppFileStore,
        repository: any LibraryRepository,
        onStatusBarHiddenChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.book = book
        self.fileStore = fileStore
        self.repository = repository
        self.onStatusBarHiddenChange = onStatusBarHiddenChange
    }

    func makeUIViewController(context: Context) -> ReaderV2ViewController {
        HostingControllerHomeIndicatorBridge.ensureInstalledForCurrentlyRegisteredClasses()
        return ReaderV2ViewController(
            book: book,
            fileStore: fileStore,
            repository: repository,
            onClose: {
                dismiss()
            },
            onStatusBarHiddenChange: { isHidden in
                onStatusBarHiddenChange(isHidden)
            }
        )
    }

    func updateUIViewController(
        _ uiViewController: ReaderV2ViewController,
        context: Context
    ) {
        uiViewController.update(book: book)
    }
}
