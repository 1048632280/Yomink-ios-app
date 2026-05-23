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
    @State private var selectedScope: LibraryScope = .all
    @State private var exportPayload: ExportPayload?

    var body: some View {
        GeometryReader { proxy in
            let drawerWidth = drawerWidth(for: proxy.size)
            let safeAreaInsets = proxy.safeAreaInsets

            ZStack {
                drawerRevealLayer(
                    width: drawerWidth,
                    safeAreaInsets: safeAreaInsets
                )

                mainSurface(width: drawerWidth)
                    .offset(x: mainOffset(width: drawerWidth))
                    .animation(Self.drawerAnimation, value: isDrawerOpen)
            }
            .background(Color(.systemGray6))
            .clipped()
        }
    }

    @ViewBuilder
    private func drawerRevealLayer(
        width: CGFloat,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        ZStack {
            if activeDrawer == .left {
                HStack(spacing: 0) {
                    drawerView(for: .left)
                        .frame(width: width)
                        .padding(.top, safeAreaInsets.top)
                        .padding(.bottom, safeAreaInsets.bottom)
                        .background(Color(.systemGray6))
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
                        .padding(.top, safeAreaInsets.top)
                        .padding(.bottom, safeAreaInsets.bottom)
                        .background(Color(.systemGray6))
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
                .allowsHitTesting(!isDrawerOpen)

            if isDrawerOpen {
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
            .navigationTitle(navigationTitleKey)
            .disabled(viewModel.isImporting)
            .toolbar {
                if viewModel.isSelecting {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            viewModel.exitSelection()
                        } label: {
                            Label {
                                Text("library.selection.exit")
                            } icon: {
                                Image(systemName: "xmark")
                            }
                        }
                        .accessibilityLabel(Text("library.selection.exit"))
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Text(viewModel.selectionCountText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                } else {
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
                            viewModel.toggleViewModeIfReady(repository: currentRepository)
                        } label: {
                            Image(systemName: viewModel.settings.viewMode == .list ? "square.grid.2x2" : "list.bullet")
                        }
                        .accessibilityLabel(Text("library.viewMode.toggle"))

                        Button {
                            openDrawer(.right)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("library.add.open"))
                    }
                }
            }
            .sheet(
                item: $activeSheet,
                onDismiss: handleSheetDismiss
            ) { sheet in
                switch sheet {
                case .search:
                    GlobalBookSearchView(repository: currentRepository) { book in
                        activeSheet = nil
                        activeReaderBook = book
                    }
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
                        repository: services.libraryRepository,
                        scope: selectedScope
                    )
                }
                .frame(width: 0, height: 0)
            }
            .sheet(item: $exportPayload) { payload in
                ActivityPresenter(activityItems: payload.urls.map { $0 as Any })
            }
            .onChange(of: isImportPickerPresented) { isPresented in
                guard case let .ready(services) = environment.bootstrapState else {
                    return
                }
                if !isPresented {
                    viewModel.loadIfNeededAfterPickerDismissal(
                        repository: services.libraryRepository,
                        scope: selectedScope
                    )
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
                    await viewModel.loadBooks(
                        repository: services.libraryRepository,
                        scope: selectedScope
                    )
                }
            }
            .task(id: bootstrapTaskID) {
                if case let .ready(services) = environment.bootstrapState {
                    await viewModel.bootstrap(
                        repository: services.libraryRepository,
                        scope: selectedScope
                    )
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var currentRepository: (any LibraryRepository)? {
        switch environment.bootstrapState {
        case let .ready(services):
            return services.libraryRepository
        case .failed:
            return nil
        }
    }

    private var currentFileStore: AppFileStore? {
        switch environment.bootstrapState {
        case let .ready(services):
            return services.fileStore
        case .failed:
            return nil
        }
    }

    @ViewBuilder
    private func drawerView(for side: LibraryDrawerSide) -> some View {
        switch side {
        case .left:
            if case let .ready(services) = environment.bootstrapState {
                LibrarySidebarView(
                    repository: services.libraryRepository,
                    selectedScope: selectedScope,
                    settings: viewModel.settings
                ) { scope in
                    selectedScope = scope
                    viewModel.exitSelection()
                    closeDrawer()
                    reloadBooks(for: scope)
                } onGroupsChanged: {
                    reloadBooksIfReady()
                } onSettingsChanged: { settings in
                    viewModel.applyLibrarySettings(settings)
                    reloadBooksIfReady()
                }
            } else {
                LibrarySidebarView(
                    selectedScope: selectedScope,
                    settings: viewModel.settings
                )
            }
        case .right:
            AddBookSidebarView(
                repository: currentRepository,
                onImportFromFile: {
                    requestImportFromDrawer()
                },
                onOpenBook: { book in
                    closeDrawer()
                    activeReaderBook = book
                }
            )
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
                VStack(spacing: 12) {
                    shelfHeader
                    shelfContentView
                    if viewModel.isSelecting {
                        selectionActionBar
                    }
                }
            }
        }
    }

    private var navigationTitleKey: LocalizedStringKey {
        viewModel.isSelecting ? "library.selection.title" : "library.title"
    }

    @ViewBuilder
    private var shelfContentView: some View {
        switch viewModel.settings.viewMode {
        case .list:
            bookListView
        case .grid:
            bookGridView
        }
    }

    private var shelfHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                scopeTitle
                    .font(.headline)
                Text(viewModel.bookCountText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    viewModel.setSortOrder(.lastReadAt, repository: currentRepository) {
                        reloadBooksIfReady()
                    }
                } label: {
                    Label {
                        Text("library.sort.lastReadAt")
                    } icon: {
                        Image(systemName: "clock")
                    }
                }

                Button {
                    viewModel.setSortOrder(.importedAt, repository: currentRepository) {
                        reloadBooksIfReady()
                    }
                } label: {
                    Label {
                        Text("library.sort.importedAt")
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(Text("library.sort.menu"))
        }
    }

    private var bookListView: some View {
        List(viewModel.books) { book in
            BookShelfItemButton(
                book: book,
                isSelecting: viewModel.isSelecting,
                isSelected: viewModel.selectedBookIDs.contains(book.id),
                content: {
                    BookRowView(
                        book: book,
                        isSelecting: viewModel.isSelecting,
                        isSelected: viewModel.selectedBookIDs.contains(book.id)
                    )
                },
                action: {
                    handleBookTap(book)
                },
                longPressAction: {
                    viewModel.beginSelection(with: book.id)
                }
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    deleteBooks([book.id])
                } label: {
                    Label {
                        Text("library.delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
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

    private var bookGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 142, maximum: 190), spacing: 14)
                ],
                spacing: 14
            ) {
                ForEach(viewModel.books) { book in
                    BookShelfItemButton(
                        book: book,
                        isSelecting: viewModel.isSelecting,
                        isSelected: viewModel.selectedBookIDs.contains(book.id),
                        content: {
                            BookGridItemView(
                                book: book,
                                isSelecting: viewModel.isSelecting,
                                isSelected: viewModel.selectedBookIDs.contains(book.id)
                            )
                        },
                        action: {
                            handleBookTap(book)
                        },
                        longPressAction: {
                            viewModel.beginSelection(with: book.id)
                        }
                    )
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, viewModel.isSelecting ? 80 : 0)
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.invertSelection()
            } label: {
                Label {
                    Text("library.selection.invert")
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }

            Menu {
                Button {
                    moveSelectedBooks(to: nil)
                } label: {
                    Label {
                        Text("sidebar.ungrouped")
                    } icon: {
                        Image(systemName: "tray")
                    }
                }

                ForEach(viewModel.groups) { group in
                    Button {
                        moveSelectedBooks(to: group.id)
                    } label: {
                        Label {
                            Text(verbatim: group.name)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                }
            } label: {
                Label {
                    Text("library.selection.move")
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .disabled(viewModel.selectedBookIDs.isEmpty)

            Button {
                exportSelectedBooks()
            } label: {
                Label {
                    Text("library.selection.export")
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .disabled(viewModel.selectedBookIDs.isEmpty)

            Button(role: .destructive) {
                deleteBooks(viewModel.selectedBookIDs)
            } label: {
                Label {
                    Text("library.delete")
                } icon: {
                    Image(systemName: "trash")
                }
            }
            .disabled(viewModel.selectedBookIDs.isEmpty)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .cornerRadius(8)
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
                Label {
                    Text("add.import.file")
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
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

    private var scopeTitle: Text {
        switch selectedScope {
        case .all:
            return Text("sidebar.allBooks")
        case .ungrouped:
            return Text("sidebar.ungrouped")
        case let .group(groupID):
            if let group = viewModel.groups.first(where: { $0.id == groupID }) {
                return Text(verbatim: group.name)
            }
            return Text("sidebar.allBooks")
        }
    }

    private var bootstrapTaskID: String {
        switch environment.bootstrapState {
        case .ready:
            return "ready-\(selectedScope.settingsKey)"
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
                await viewModel.loadBooks(
                    repository: services.libraryRepository,
                    scope: selectedScope
                )
            }
        }
    }

    private func reloadBooks(for scope: LibraryScope) {
        if case let .ready(services) = environment.bootstrapState {
            Task {
                await viewModel.loadBooks(
                    repository: services.libraryRepository,
                    scope: scope
                )
            }
        }
    }

    private func handleBookTap(_ book: Book) {
        if viewModel.isSelecting {
            viewModel.toggleSelection(for: book.id)
        } else {
            activeReaderBook = book
        }
    }

    private func moveSelectedBooks(to groupID: UUID?) {
        guard let repository = currentRepository else {
            return
        }

        viewModel.moveSelectedBooks(
            to: groupID,
            repository: repository,
            scope: selectedScope
        )
    }

    private func deleteBooks(_ ids: Set<UUID>) {
        guard let repository = currentRepository,
              let fileStore = currentFileStore
        else {
            return
        }

        viewModel.deleteBooks(
            ids: ids,
            repository: repository,
            fileStore: fileStore,
            scope: selectedScope
        )
    }

    private func exportSelectedBooks() {
        guard let fileStore = currentFileStore else {
            return
        }

        do {
            let urls = try viewModel.exportURLs(fileStore: fileStore)
            guard !urls.isEmpty else {
                return
            }
            exportPayload = ExportPayload(urls: urls)
            viewModel.exitSelection()
        } catch {
            viewModel.importErrorMessage = error.localizedDescription
        }
    }

    private func openDrawer(_ drawer: LibraryDrawerSide) {
        activeDrawer = drawer
        withAnimation(Self.drawerAnimation) {
            isDrawerOpen = true
        }
    }

    private func closeDrawer() {
        guard isDrawerOpen else {
            return
        }

        withAnimation(Self.drawerAnimation) {
            isDrawerOpen = false
        }
    }

    private func requestImportFromDrawer() {
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerAnimationDuration + 0.02) {
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
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard let activeDrawer,
                      isDrawerOpen,
                      abs(value.translation.width) > abs(value.translation.height)
                else {
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
                    DispatchQueue.main.async {
                        closeDrawer()
                    }
                }
            }
    }

    private func mainOffset(width: CGFloat) -> CGFloat {
        guard let activeDrawer,
              isDrawerOpen
        else {
            return 0
        }

        return activeDrawer.openOffset(width: width)
    }

    private static let drawerAnimationDuration = 0.28

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

private struct ActivityPresenter: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
    }
}

@MainActor
private final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var groups: [BookGroup] = []
    @Published var settings = LibrarySettings.default
    @Published var selectedBookIDs: Set<UUID> = []
    @Published var isImporting = false
    @Published var importErrorMessage: String?
    private var currentImportTask: Task<Void, Never>?

    var isSelecting: Bool {
        !selectedBookIDs.isEmpty
    }

    var selectionCountText: String {
        String(
            format: NSLocalizedString("library.selection.count", comment: ""),
            selectedBookIDs.count
        )
    }

    var bookCountText: String {
        String(
            format: NSLocalizedString("library.count", comment: ""),
            books.count
        )
    }

    func bootstrap(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) async {
        guard !isImporting else {
            return
        }

        do {
            async let fetchedSettings = repository.fetchLibrarySettings()
            async let fetchedGroups = repository.fetchGroups()
            settings = try await fetchedSettings
            groups = try await fetchedGroups
            books = try await repository.fetchBooks(
                scope: scope,
                sortOrder: settings.sortOrder
            )
            pruneSelection()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func loadBooks(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) async {
        guard !isImporting else {
            return
        }

        do {
            async let fetchedGroups = repository.fetchGroups()
            async let fetchedBooks = repository.fetchBooks(
                scope: scope,
                sortOrder: settings.sortOrder
            )
            groups = try await fetchedGroups
            books = try await fetchedBooks
            pruneSelection()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func handleImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService,
        repository: any LibraryRepository,
        scope: LibraryScope
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
                repository: repository,
                scope: scope
            )
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }

    func loadIfNeededAfterPickerDismissal(
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        guard !isImporting else {
            return
        }

        Task {
            await loadBooks(repository: repository, scope: scope)
        }
    }

    func beginSelection(with bookID: UUID) {
        selectedBookIDs = [bookID]
    }

    func toggleSelection(for bookID: UUID) {
        if selectedBookIDs.contains(bookID) {
            selectedBookIDs.remove(bookID)
        } else {
            selectedBookIDs.insert(bookID)
        }
    }

    func invertSelection() {
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs = visibleIDs.subtracting(selectedBookIDs)
    }

    func exitSelection() {
        selectedBookIDs.removeAll()
    }

    func toggleViewModeIfReady(repository: (any LibraryRepository)?) {
        let nextMode: LibrarySettings.ViewMode = settings.viewMode == .list ? .grid : .list
        settings.viewMode = nextMode
        saveLibrarySettings(repository: repository)
    }

    func setSortOrder(
        _ sortOrder: LibrarySettings.SortOrder,
        repository: (any LibraryRepository)?,
        onChange: @escaping () -> Void
    ) {
        guard settings.sortOrder != sortOrder else {
            return
        }

        settings.sortOrder = sortOrder
        saveLibrarySettings(repository: repository)
        onChange()
    }

    func applyLibrarySettings(_ settings: LibrarySettings) {
        self.settings = settings
    }

    func moveSelectedBooks(
        to groupID: UUID?,
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        let ids = selectedBookIDs
        guard !ids.isEmpty else {
            return
        }

        Task {
            do {
                try await repository.moveBooks(ids: ids, to: groupID)
                await loadBooks(repository: repository, scope: scope)
                exitSelection()
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    func deleteBooks(
        ids: Set<UUID>,
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        scope: LibraryScope
    ) {
        let ids = ids.filter { id in
            books.contains(where: { $0.id == id })
        }
        guard !ids.isEmpty else {
            return
        }

        Task {
            do {
                for id in ids {
                    try fileStore.removeBookFiles(id: id)
                    try await repository.deleteBook(id: id)
                }
                await loadBooks(repository: repository, scope: scope)
                exitSelection()
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    func exportURLs(fileStore: AppFileStore) throws -> [URL] {
        try books
            .filter { selectedBookIDs.contains($0.id) }
            .map { book in
                try fileStore.url(forRelativePath: book.sourcePath)
            }
    }

    private func importBook(
        from url: URL,
        importService: ImportService,
        repository: any LibraryRepository,
        scope: LibraryScope
    ) {
        isImporting = true
        currentImportTask = Task {
            do {
                _ = try await importService.importBook(from: url)
                try Task.checkCancellation()
                groups = try await repository.fetchGroups()
                books = try await repository.fetchBooks(
                    scope: scope,
                    sortOrder: settings.sortOrder
                )
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

    private func saveLibrarySettings(repository: (any LibraryRepository)?) {
        guard let repository else {
            return
        }

        let settings = settings
        Task {
            do {
                try await repository.saveLibrarySettings(settings)
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func pruneSelection() {
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs.formIntersection(visibleIDs)
    }
}

private struct BookShelfItemButton<Content: View>: View {
    let isSelected: Bool
    private let content: () -> Content
    private let action: () -> Void
    private let longPressAction: () -> Void

    init(
        book: Book,
        isSelecting: Bool,
        isSelected: Bool,
        @ViewBuilder content: @escaping () -> Content,
        action: @escaping () -> Void,
        longPressAction: @escaping () -> Void
    ) {
        self.isSelected = isSelected
        self.content = content
        self.action = action
        self.longPressAction = longPressAction
    }

    var body: some View {
        Button(action: action) {
            content()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    longPressAction()
                }
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BookRowView: View {
    let book: Book
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24, height: 44)
            }

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

            if !isSelecting {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
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

private struct BookGridItemView: View {
    let book: Book
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 138)
                    .overlay {
                        Image(systemName: "doc.text")
                            .font(.system(size: 42))
                            .foregroundColor(.accentColor)
                    }

                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .padding(8)
                }
            }

            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(minHeight: 38, alignment: .topLeading)

            ProgressView(value: clampedProgress)

            Text(progressText)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color(.separator), lineWidth: 1)
        )
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

private struct GlobalBookSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let repository: (any LibraryRepository)?
    let onOpenBook: (Book) -> Void

    @State private var keyword = ""
    @State private var results: [Book] = []
    @State private var historyItems: [SearchHistoryItem] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("search.field.placeholder", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.search)
                        .onSubmit {
                            performSearch()
                        }

                    if !keyword.isEmpty {
                        Button {
                            keyword = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .accessibilityLabel(Text("search.clearInput"))
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

                if !historyItems.isEmpty {
                    historySection
                }

                resultList
            }
            .padding()
            .navigationTitle("search.title")
            .task {
                await reloadHistory()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        dismiss()
                    }
                }
            }
            .alert(
                "search.error.title",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("search.history.title")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button("search.history.clear") {
                    clearHistory()
                }
                .font(.footnote)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(historyItems) { item in
                        Button {
                            keyword = item.keyword
                            performSearch()
                        } label: {
                            Text(verbatim: item.keyword)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Spacer(minLength: 0)
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "books.vertical")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary)
                Text("search.empty.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            List(results) { book in
                Button {
                    onOpenBook(book)
                } label: {
                    BookRowView(
                        book: book,
                        isSelecting: false,
                        isSelected: false
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func performSearch() {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let repository,
              !keyword.isEmpty
        else {
            results = []
            return
        }

        Task {
            do {
                try await repository.saveSearchKeyword(keyword)
                results = try await repository.searchBooks(keyword: keyword)
                await reloadHistory()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func reloadHistory() async {
        guard let repository else {
            historyItems = []
            return
        }

        do {
            historyItems = try await repository.fetchSearchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        guard let repository else {
            historyItems = []
            return
        }

        Task {
            do {
                try await repository.clearSearchHistory()
                historyItems = []
            } catch {
                errorMessage = error.localizedDescription
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

private struct ExportPayload: Identifiable {
    let id = UUID()
    let urls: [URL]
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
