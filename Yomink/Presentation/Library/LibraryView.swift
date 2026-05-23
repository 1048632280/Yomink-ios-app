import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel = LibraryViewModel()
    @State private var activeSheet: LibrarySheet?
    @State private var activeDrawer: LibraryDrawerSide?
    @State private var activeReaderBook: Book?
    @State private var isImportPickerPresented = false
    @State private var isDrawerOpen = false
    @State private var closeDragOffset: CGFloat = 0
    @State private var drawerAnimationGeneration = 0

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = drawerWidth(for: proxy.size)

            ZStack {
                drawerRevealLayer(width: drawerWidth)

                mainSurface(width: drawerWidth)
                    .offset(x: mainOffset(width: drawerWidth))
                    .animation(Self.drawerAnimation, value: isDrawerOpen)
            }
            .background(Color(.systemGray6))
            .clipped()
        }
    }

    @ViewBuilder
    private func drawerRevealLayer(width: CGFloat) -> some View {
        ZStack {
            if activeDrawer == .left {
                HStack(spacing: 0) {
                    drawerView(for: .left)
                        .frame(width: width)
                        .offset(x: isDrawerOpen ? 0 : -width * 0.18)
                        .allowsHitTesting(isDrawerOpen)

                    Spacer(minLength: 0)
                }
            }

            if activeDrawer == .right {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    drawerView(for: .right)
                        .frame(width: width)
                        .offset(x: isDrawerOpen ? 0 : width * 0.18)
                        .allowsHitTesting(isDrawerOpen)
                }
            }
        }
        .background(Color(.systemGray6))
        .ignoresSafeArea()
        .animation(Self.drawerAnimation, value: isDrawerOpen)
    }

    private func mainSurface(width: CGFloat) -> some View {
        ZStack {
            libraryNavigationView
                .allowsHitTesting(activeDrawer == nil)

            if activeDrawer != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeDrawer()
                    }
                    .gesture(closeDragGesture(width: width))
                    .accessibilityLabel(Text("library.drawer.close"))
            }
        }
    }

    private var libraryNavigationView: some View {
        NavigationView {
            ZStack {
                contentView
                    .padding(24)

                if viewModel.isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("library.title")
            .disabled(viewModel.isImporting)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        openDrawer(.left)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(Text("library.sidebar.open"))
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .search
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("library.search.open"))

                    Button {
                        openDrawer(.right)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("library.add.open"))
                }
            }
            .sheet(
                item: $activeSheet,
                onDismiss: handleSheetDismiss
            ) { sheet in
                switch sheet {
                case .search:
                    GlobalSearchPlaceholderView()
                }
            }
            .fullScreenCover(
                item: $activeReaderBook,
                onDismiss: reloadBooksIfReady
            ) { book in
                if case let .ready(services) = environment.bootstrapState {
                    ReaderHostView(
                        book: book,
                        fileStore: services.fileStore,
                        repository: services.libraryRepository
                    )
                    .ignoresSafeArea()
                    .statusBar(hidden: true)
                }
            }
            .background {
                DocumentPickerPresenter(
                    isPresented: $isImportPickerPresented,
                    allowedContentTypes: [Self.txtContentType]
                ) { result in
                    guard case let .ready(services) = environment.bootstrapState else {
                        return
                    }
                    viewModel.handleImportResult(
                        result,
                        importService: services.importService,
                        repository: services.libraryRepository
                    )
                }
                .frame(width: 0, height: 0)
            }
            .onChange(of: isImportPickerPresented) { isPresented in
                guard case let .ready(services) = environment.bootstrapState else {
                    return
                }
                if !isPresented {
                    viewModel.loadIfNeededAfterPickerDismissal(repository: services.libraryRepository)
                }
            }
            .alert(
                "import.error.title",
                isPresented: Binding(
                    get: { viewModel.importErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.importErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    viewModel.importErrorMessage = nil
                }
            } message: {
                Text(viewModel.importErrorMessage ?? "")
            }
            .refreshable {
                if case let .ready(services) = environment.bootstrapState {
                    await viewModel.loadBooks(repository: services.libraryRepository)
                }
            }
            .task(id: bootstrapTaskID) {
                if case let .ready(services) = environment.bootstrapState {
                    await viewModel.loadBooks(repository: services.libraryRepository)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func drawerView(for side: LibraryDrawerSide) -> some View {
        switch side {
        case .left:
            if case let .ready(services) = environment.bootstrapState {
                LibrarySidebarView(repository: services.libraryRepository)
            } else {
                LibrarySidebarView()
            }
        case .right:
            AddBookSidebarView {
                requestImportFromDrawer()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch environment.bootstrapState {
        case let .failed(bootstrapError):
            VStack(spacing: 16) {
                bootstrapErrorView(bootstrapError)
                Spacer(minLength: 0)
            }
        case .ready:
            if viewModel.books.isEmpty {
                emptyShelfView
            } else {
                bookListView
            }
        }
    }

    private var bookListView: some View {
        List(viewModel.books) { book in
            Button {
                activeReaderBook = book
            } label: {
                BookRowView(book: book)
            }
            .buttonStyle(.plain)
            .listRowInsets(
                EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            )
        }
        .listStyle(.plain)
        .padding(.horizontal, -24)
        .padding(.vertical, -24)
    }

    private var emptyShelfView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.secondary)

            Text("library.empty.title")
                .font(.headline)

            Text("library.empty.message")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button {
                isImportPickerPresented = true
            } label: {
                Label("add.import.file", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text("import.progress.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    private var bootstrapTaskID: String {
        switch environment.bootstrapState {
        case .ready:
            return "ready"
        case let .failed(message):
            return "failed-\(message)"
        }
    }

    private func bootstrapErrorView(_ message: String) -> some View {
        Text(String(format: NSLocalizedString("bootstrap.error.message", comment: ""), message))
            .font(.footnote)
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
    }

    private func handleSheetDismiss() {
        reloadBooksIfReady()
    }

    private func reloadBooksIfReady() {
        if case let .ready(services) = environment.bootstrapState {
            Task {
                await viewModel.loadBooks(repository: services.libraryRepository)
            }
        }
    }

    private func openDrawer(_ drawer: LibraryDrawerSide) {
        drawerAnimationGeneration += 1
        closeDragOffset = 0
        activeDrawer = drawer
        withAnimation(Self.drawerAnimation) {
            isDrawerOpen = true
        }
    }

    private func closeDrawer() {
        guard activeDrawer != nil else {
            return
        }

        drawerAnimationGeneration += 1
        let generation = drawerAnimationGeneration
        withAnimation(Self.drawerAnimation) {
            isDrawerOpen = false
            closeDragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerCloseDuration) {
            guard generation == drawerAnimationGeneration else {
                return
            }
            activeDrawer = nil
        }
    }

    private func requestImportFromDrawer() {
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerCloseDuration + 0.02) {
            isImportPickerPresented = true
        }
    }

    private func drawerWidth(for size: CGSize) -> CGFloat {
        let visibleMainWidth: CGFloat = size.width >= 700 ? 96 : 64
        let maximumWidth = max(size.width - visibleMainWidth, 0)
        let preferredWidth: CGFloat = size.width >= 700 ? 380 : 320
        return min(preferredWidth, maximumWidth)
    }

    private func closeDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard let activeDrawer,
                      abs(value.translation.width) > abs(value.translation.height)
                else {
                    return
                }
                closeDragOffset = activeDrawer.closeOffset(
                    for: value.translation.width,
                    width: width
                )
            }
            .onEnded { value in
                guard let activeDrawer,
                      abs(value.translation.width) > abs(value.translation.height)
                else {
                    resetCloseDragOffset()
                    return
                }
                let offset = activeDrawer.closeOffset(
                    for: value.translation.width,
                    width: width
                )
                let predictedOffset = activeDrawer.closeOffset(
                    for: value.predictedEndTranslation.width,
                    width: width
                )
                let shouldClose = abs(offset) > width * 0.28
                    || abs(predictedOffset) > width * 0.48

                if shouldClose {
                    closeDrawer()
                } else {
                    resetCloseDragOffset()
                }
            }
    }

    private func resetCloseDragOffset() {
        withAnimation(Self.drawerAnimation) {
            closeDragOffset = 0
        }
    }

    private func mainOffset(width: CGFloat) -> CGFloat {
        guard let activeDrawer,
              isDrawerOpen
        else {
            return 0
        }

        return activeDrawer.openOffset(width: width) + closeDragOffset
    }

    private static let drawerCloseDuration = 0.28

    private static let drawerAnimation = Animation.spring(
        response: 0.28,
        dampingFraction: 0.9,
        blendDuration: 0.02
    )

    // Use the system type directly. A dynamic "txt" UTType can make Files keep
    // .txt documents disabled on some iOS versions.
    private static let txtContentType = UTType.plainText
}

private struct DocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let allowedContentTypes: [UTType]
    let onCompletion: (Result<[URL], Error>) -> Void

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

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
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
                asCopy: true
            )
            picker.delegate = self
            picker.allowsMultipleSelection = false
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

@MainActor
private final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isImporting = false
    @Published var importErrorMessage: String?
    private var currentImportTask: Task<Void, Never>?

    func loadBooks(repository: any LibraryRepository) async {
        guard !isImporting else {
            return
        }

        do {
            books = try await repository.fetchBooks()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func handleImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService,
        repository: any LibraryRepository
    ) {
        guard !isImporting else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            importBook(
                from: url,
                importService: importService,
                repository: repository
            )
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }

    func loadIfNeededAfterPickerDismissal(repository: any LibraryRepository) {
        guard !isImporting else {
            return
        }

        Task {
            await loadBooks(repository: repository)
        }
    }

    private func importBook(
        from url: URL,
        importService: ImportService,
        repository: any LibraryRepository
    ) {
        isImporting = true
        currentImportTask = Task {
            do {
                _ = try await importService.importBook(from: url)
                try Task.checkCancellation()
                books = try await repository.fetchBooks()
                currentImportTask = nil
            } catch {
                if !Task.isCancelled {
                    importErrorMessage = error.localizedDescription
                    currentImportTask = nil
                }
            }
            isImporting = false
            if Task.isCancelled {
                currentImportTask = nil
            }
        }
    }
}

private struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    ProgressView(value: clampedProgress)
                        .frame(maxWidth: 120)

                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var clampedProgress: Double {
        min(max(book.progressPercentage, 0), 1)
    }

    private var progressText: String {
        NumberFormatter.readingProgress.string(from: NSNumber(value: clampedProgress)) ?? "0%"
    }
}

private extension NumberFormatter {
    static let readingProgress: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct GlobalSearchPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("search.title")
                    .font(.headline)
                Text("search.placeholder.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("search.title")
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

private enum LibrarySheet: Identifiable {
    case search

    var id: String {
        switch self {
        case .search:
            return "search"
        }
    }
}

private enum LibraryDrawerSide: Equatable {
    case left
    case right

    func openOffset(width: CGFloat) -> CGFloat {
        switch self {
        case .left:
            return width
        case .right:
            return -width
        }
    }

    func closeOffset(for translation: CGFloat, width: CGFloat) -> CGFloat {
        switch self {
        case .left:
            return min(max(translation, -width), 0)
        case .right:
            return max(min(translation, width), 0)
        }
    }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(AppEnvironment.preview())
    }
}
#endif
