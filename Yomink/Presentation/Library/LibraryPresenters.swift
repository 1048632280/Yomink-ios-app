import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding fileprivate var isPresented: Bool
    fileprivate let allowedContentTypes: [UTType]
    fileprivate var asCopy = true
    fileprivate var allowsMultipleSelection = false
    fileprivate let onCompletion: (Result<[URL], Error>) -> Void

    init(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        asCopy: Bool = true,
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) {
        self._isPresented = isPresented
        self.allowedContentTypes = allowedContentTypes
        self.asCopy = asCopy
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onCompletion = onCompletion
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        context.coordinator.parent = self

        if isPresented {
            context.coordinator.presentPickerIfNeeded(from: uiViewController)
        } else {
            context.coordinator.dismissPickerIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        var parent: DocumentPickerPresenter
        private weak var picker: UIDocumentPickerViewController?
        private var retryCount = 0

        init(parent: DocumentPickerPresenter) {
            self.parent = parent
        }

        func presentPickerIfNeeded(from viewController: UIViewController) {
            guard picker == nil else {
                return
            }
            guard viewController.presentedViewController == nil,
                  viewController.view.window != nil
            else {
                schedulePresentationRetry(from: viewController)
                return
            }

            retryCount = 0

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: parent.allowedContentTypes,
                asCopy: parent.asCopy
            )
            picker.delegate = self
            picker.presentationController?.delegate = self
            picker.allowsMultipleSelection = parent.allowsMultipleSelection
            self.picker = picker
            viewController.present(picker, animated: true)
        }

        func dismissPickerIfNeeded() {
            retryCount = 0
            picker?.dismiss(animated: true)
            picker = nil
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            picker = nil
            parent.isPresented = false
            parent.onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            picker = nil
            parent.isPresented = false
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            retryCount = 0
            picker = nil
            parent.isPresented = false
        }

        private func schedulePresentationRetry(from viewController: UIViewController) {
            guard retryCount < 10 else {
                retryCount = 0
                parent.isPresented = false
                return
            }

            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak viewController] in
                guard let self,
                      self.parent.isPresented,
                      let viewController
                else {
                    return
                }
                self.presentPickerIfNeeded(from: viewController)
            }
        }
    }
}

struct ActivityPresenter: UIViewControllerRepresentable {
    fileprivate let activityItems: [Any]
    fileprivate var onComplete: () -> Void

    init(activityItems: [Any], onComplete: @escaping () -> Void = {}) {
        self.activityItems = activityItems
        self.onComplete = onComplete
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let viewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        viewController.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
    }
}
