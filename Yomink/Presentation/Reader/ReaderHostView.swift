import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

struct ReaderHostView: UIViewControllerRepresentable {
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

    func makeUIViewController(context: Context) -> CollectionReaderViewController {
        HostingControllerHomeIndicatorBridge.ensureInstalledForCurrentlyRegisteredClasses()
        return CollectionReaderViewController(
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
        _ uiViewController: CollectionReaderViewController,
        context: Context
    ) {
        uiViewController.update(book: book)
    }
}
