import Foundation
import SwiftUI
import UIKit

extension View {
    func storageCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}


struct BackTextButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                Text("common.back")
            }
        }
        .accessibilityLabel(Text("common.back"))
    }
}

struct DedicatedPromptOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var text: String
    let placeholder: String
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }
}

struct DedicatedConfirmationOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
    }
}

private struct DedicatedModalBackdrop<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Color.black.opacity(0.28)
            .ignoresSafeArea()
            .overlay {
                content()
                    .frame(width: 270)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
    }
}

struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        DispatchQueue.main.async {
            context.coordinator.restoreGesture(on: controller.navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?

        func restoreGesture(on navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer
            else {
                return
            }

            self.navigationController = navigationController
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    final class Controller: UIViewController {
        var onMoveToNavigationController: ((UINavigationController?) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onMoveToNavigationController?(navigationController)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onMoveToNavigationController?(navigationController)
        }
    }
}

private struct DedicatedListRow: View {
    let title: String
    var showsDeleteControl = false
    var deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
    }
}

struct DedicatedGroupListRow: View {
    let title: String
    var showsDeleteControl = false
    var showsReorderControl = false
    var isPressed = false
    var isDragging = false
    var dragOffset: CGSize = .zero
    var deleteAction: (() -> Void)?
    var reorderDragChanged: ((CGSize) -> Void)?
    var reorderDragEnded: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("library.delete"))
                .zIndex(2)
                .allowsHitTesting(true)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showsReorderControl {
                ReorderHandle(
                    onChanged: { translation in
                        reorderDragChanged?(translation)
                    },
                    onEnded: {
                        reorderDragEnded?()
                    }
                )
                .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                .zIndex(2)
                .accessibilityLabel(Text("groups.reorder"))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(isPressed ? Color(.systemGray5) : Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
        .offset(y: isDragging ? dragOffset.height : 0)
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(
            color: Color.black.opacity(isDragging ? 0.18 : 0),
            radius: isDragging ? 10 : 0,
            x: 0,
            y: isDragging ? 5 : 0
        )
        .zIndex(isDragging ? 1 : 0)
        .animation(DedicatedPageStyle.reorderAnimation, value: isDragging)
    }
}

private struct ReorderHandle: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> HandleView {
        let view = HandleView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let imageView = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        imageView.tintColor = .systemGray2
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        view.panGesture = panGesture
        context.coordinator.view = view

        return view
    }

    func updateUIView(_ view: HandleView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.view = view
    }

    final class HandleView: UIView {
        weak var panGesture: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let panGesture else {
                return
            }
            nearestScrollView()?.panGestureRecognizer.require(toFail: panGesture)
        }

        private func nearestScrollView() -> UIScrollView? {
            var parent = superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void
        weak var view: UIView?

        init(
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .began:
                setParentScrollEnabled(false)
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .changed:
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                setParentScrollEnabled(true)
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func setParentScrollEnabled(_ isEnabled: Bool) {
            nearestScrollView(from: view)?.isScrollEnabled = isEnabled
        }

        private func nearestScrollView(from view: UIView?) -> UIScrollView? {
            var parent = view?.superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }
}


enum DedicatedPageStyle {
    static let rowHeight: CGFloat = 54
    static let compactRowHeight: CGFloat = 44
    static let controlHitWidth: CGFloat = 44
    static let reorderAnimation = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.82,
        blendDuration: 0.12
    )

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
    }
}

extension String {
    var dedicatedFirstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
    }
}


enum SettingsPageStyle {
    static let rowHeight: CGFloat = 50

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}
