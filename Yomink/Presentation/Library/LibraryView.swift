import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel = LibraryViewModel()
    @State private var activeDrawer: LibraryDrawerSide?
    @State private var activeReaderBook: Book?
    @State private var isImportPickerPresented = false
    @State private var isDrawerOpen = false
    @State private var selectedScope: LibraryScope = .ungrouped
    @State private var activeRoute: LibraryRoute?
    @State private var exportPayload: ExportPayload?
    @State private var pendingBookDeletion: PendingBookDeletion?
    @State private var isReaderStatusBarHidden = false
    @State private var pendingReaderBook: Book?
    @State private var pendingReaderOpenID = UUID()
    @State private var readerNavigationGuardUntil: Date?

    init() {
        Self.configureNavigationBarAppearance()
    }

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
        .ignoresSafeArea(.all)
        .statusBar(hidden: activeReaderBook != nil && isReaderStatusBarHidden)
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
                        .background(SidebarStyle.background)
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
                        .background(SidebarStyle.background)
                        .offset(x: isDrawerOpen ? 0 : width * 0.18)
                        .allowsHitTesting(isDrawerOpen)
                }
            }
        }
        .background(SidebarStyle.background)
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
                Color(.systemGray6)
                    .ignoresSafeArea()

                contentView
                    .padding(24)

                routeLinks

                if viewModel.isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("app.title")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isImporting)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("app.title")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    libraryLeadingToolbarContent
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    libraryTrailingToolbarContent
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
                        importService: services.importService
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
                viewModel.importErrorTitle,
                isPresented: Binding(
                    get: { viewModel.importErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.clearError()
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    viewModel.clearError()
                }
            } message: {
                Text(viewModel.importErrorMessage ?? "")
            }
            .alert(item: $pendingBookDeletion) { deletion in
                Alert(
                    title: Text("library.delete.confirm.title"),
                    message: Text(verbatim: deletion.message),
                    primaryButton: .destructive(Text("library.delete.confirm.action")) {
                        performDeleteBooks(deletion.ids)
                    },
                    secondaryButton: .cancel(Text("common.cancel"))
                )
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
            .onChange(of: viewModel.importPreview?.sourceURL.absoluteString) { previewID in
                if previewID != nil {
                    activeRoute = .importBook
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelecting {
                    selectionActionBar
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var libraryLeadingToolbarContent: some View {
        if viewModel.isSelecting {
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
        } else {
            Button {
                openDrawer(.left)
            } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel(Text("library.sidebar.open"))
        }
    }

    @ViewBuilder
    private var libraryTrailingToolbarContent: some View {
        if viewModel.isSelecting {
            Text(viewModel.selectionCountText)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        } else {
            HStack(spacing: 16) {
                Button {
                    activeRoute = .search
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
                    groups: viewModel.groups,
                    books: viewModel.allBooks,
                    selectedScope: selectedScope,
                    settings: viewModel.settings
                ) { scope in
                    selectedScope = scope
                    viewModel.exitSelection()
                    closeDrawer()
                    reloadBooks(for: scope)
                } onSettingsChanged: { settings in
                    viewModel.applyLibrarySettings(settings)
                    reloadBooksIfReady()
                } onDisplayOptionChanged: {
                    closeDrawer()
                } onOpenGroupsPage: {
                    openRouteFromDrawer(.groups)
                } onOpenSettingsPage: {
                    openRouteFromDrawer(.settings)
                }
            } else {
                LibrarySidebarView(
                    groups: viewModel.groups,
                    books: viewModel.allBooks,
                    selectedScope: selectedScope,
                    settings: viewModel.settings
                )
            }
        case .right:
            AddBookSidebarView(
                onImportFromFile: {
                    requestImportFromDrawer()
                },
                onOpenHistoryPage: {
                    openRouteFromDrawer(.history)
                },
                onOpenRandomPickerPage: {
                    openRouteFromDrawer(.randomPicker)
                }
            )
        }
    }

    @ViewBuilder
    private var routeLinks: some View {
        if case let .ready(services) = environment.bootstrapState {
            NavigationLink(
                tag: LibraryRoute.groups,
                selection: $activeRoute
            ) {
                LibraryGroupsPage(
                    repository: services.libraryRepository,
                    onGroupsChanged: { deletedGroupID in
                        if let deletedGroupID,
                           selectedScope == .group(deletedGroupID) {
                            selectedScope = .ungrouped
                        }
                        reloadBooksIfReady()
                    }
                )
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                tag: LibraryRoute.history,
                selection: $activeRoute
            ) {
                ReadingHistoryPage(
                    repository: services.libraryRepository,
                    onOpenBook: { book in
                        openBookAfterRouteDismissal(book)
                    }
                )
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                tag: LibraryRoute.randomPicker,
                selection: $activeRoute
            ) {
                RandomBookPickerPage(
                    repository: services.libraryRepository,
                    onOpenBook: { book in
                        openBookAfterRouteDismissal(book)
                    }
                )
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                tag: LibraryRoute.search,
                selection: $activeRoute
            ) {
                GlobalBookSearchView(
                    repository: services.libraryRepository,
                    sortOrder: viewModel.settings.sortOrder,
                    onOpenBook: { book in
                        openBookAfterRouteDismissal(book)
                    }
                )
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                tag: LibraryRoute.settings,
                selection: $activeRoute
            ) {
                LibrarySettingsPage(
                    repository: services.libraryRepository,
                    fileStore: services.fileStore,
                    settings: viewModel.settings,
                    onOpenBook: { book in
                        openBookAfterRouteDismissal(book)
                    },
                    onLibraryChanged: {
                        reloadBooksIfReady()
                    },
                    onChange: { settings in
                        viewModel.applyLibrarySettings(settings)
                        reloadBooksIfReady()
                    }
                )
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                tag: LibraryRoute.importBook,
                selection: $activeRoute
            ) {
                if let preview = viewModel.importPreview {
                    ImportBookEditPage(
                        preview: preview,
                        importService: services.importService,
                        onImported: {
                            closeImportRoute()
                            reloadBooksIfReady()
                        },
                        onOpenExistingBook: { book in
                            viewModel.clearImportPreview()
                            openBookAfterRouteDismissal(book)
                        },
                        onCancel: {
                            closeImportRoute()
                        }
                    )
                } else {
                    EmptyView()
                }
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)

            NavigationLink(
                isActive: readerNavigationBinding
            ) {
                if let book = activeReaderBook {
                    ReaderHostView(
                        book: book,
                        fileStore: services.fileStore,
                        repository: services.libraryRepository,
                        onStatusBarHiddenChange: { isHidden in
                            isReaderStatusBarHidden = isHidden
                        }
                    )
                    .ignoresSafeArea()
                    .navigationBarHidden(true)
                } else {
                    EmptyView()
                }
            } label: {
                EmptyView()
            }
            .hidden()
            .frame(width: 0, height: 0)
        }
    }

    private var readerNavigationBinding: Binding<Bool> {
        Binding(
            get: {
                activeReaderBook != nil
            },
            set: { isActive in
                guard !isActive else {
                    return
                }
                if let guardUntil = readerNavigationGuardUntil,
                   Date() < guardUntil {
                    return
                }
                readerNavigationGuardUntil = nil
                isReaderStatusBarHidden = false
                activeReaderBook = nil
                reloadBooksIfReady()
            }
        )
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
                shelfContentView
            }
        }
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
                    requestDeleteBooks([book.id])
                } label: {
                    Label {
                        Text("library.delete")
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Color(.systemGray6))
            .listRowInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
            )
        }
        .listStyle(.plain)
        .background(Color(.systemGray6))
        .padding(.horizontal, -24)
        .padding(.vertical, -24)
    }

    private var bookGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: Self.bookGridColumns,
                spacing: BookGridStyle.rowSpacing
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
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .padding(-24)
        .background(Color(.systemGray6))
    }

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            Button(role: .destructive) {
                requestDeleteBooks(viewModel.selectedBookIDs)
            } label: {
                Text("library.delete")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .foregroundColor(
                viewModel.selectedBookIDs.isEmpty ? Color(.tertiaryLabel) : .red.opacity(0.82)
            )
            .disabled(viewModel.selectedBookIDs.isEmpty)

            Menu {
                Button {
                    moveSelectedBooks(to: nil)
                } label: {
                    Text("sidebar.ungrouped")
                }

                ForEach(viewModel.groups) { group in
                    Button {
                        moveSelectedBooks(to: group.id)
                    } label: {
                        Text(verbatim: group.name)
                    }
                }
            } label: {
                Text("library.selection.move")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .foregroundColor(
                viewModel.selectedBookIDs.isEmpty ? Color(.tertiaryLabel) : .accentColor
            )
            .disabled(viewModel.selectedBookIDs.isEmpty)

            Button {
                viewModel.invertSelection()
            } label: {
                Text("library.selection.invert")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .foregroundColor(.accentColor)

            Button {
                exportSelectedBooks()
            } label: {
                Text("library.selection.export")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .foregroundColor(
                viewModel.selectedBookIDs.isEmpty ? Color(.tertiaryLabel) : .accentColor
            )
            .disabled(viewModel.selectedBookIDs.isEmpty)
        }
        .font(.body)
        .buttonStyle(.plain)
        .tint(.accentColor)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
        }
        .ignoresSafeArea(.container, edges: .bottom)
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

    private func requestDeleteBooks(_ ids: Set<UUID>) {
        let visibleIDs = Set(viewModel.books.map(\.id))
        let deletableIDs = ids.intersection(visibleIDs)
        guard !deletableIDs.isEmpty else {
            return
        }
        pendingBookDeletion = PendingBookDeletion(ids: deletableIDs)
    }

    private func performDeleteBooks(_ ids: Set<UUID>) {
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
            viewModel.showError(error, title: "library.export.error.title")
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

    private func openRouteFromDrawer(_ route: LibraryRoute) {
        activeRoute = route
        closeDrawer()
    }

    private func openBookAfterRouteDismissal(_ book: Book) {
        pendingReaderBook = book
        let openID = UUID()
        pendingReaderOpenID = openID
        activeRoute = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.routeReaderOpenDelay) {
            guard pendingReaderOpenID == openID,
                  let bookToOpen = pendingReaderBook,
                  bookToOpen.id == book.id
            else {
                return
            }

            readerNavigationGuardUntil = Date().addingTimeInterval(Self.readerNavigationGuardDuration)
            activeReaderBook = bookToOpen
            self.pendingReaderBook = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.readerNavigationGuardDuration) {
                if let guardUntil = readerNavigationGuardUntil,
                   Date() >= guardUntil {
                    readerNavigationGuardUntil = nil
                }
            }
        }
    }

    private func closeImportRoute() {
        viewModel.clearImportPreview()
        activeRoute = nil
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
    private static let routeReaderOpenDelay = 0.56
    private static let readerNavigationGuardDuration = 0.72

    private static let drawerAnimation = Animation.spring(
        response: 0.28,
        dampingFraction: 0.9,
        blendDuration: 0.02
    )

    private static let bookGridColumns = Array(
        repeating: GridItem(
            .flexible(),
            spacing: BookGridStyle.columnSpacing,
            alignment: .top
        ),
        count: 3
    )

    // Use the system type directly. A dynamic "txt" UTType can make Files keep
    // .txt documents disabled on some iOS versions.
    private static let txtContentType = UTType.plainText

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .separator
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.prefersLargeTitles = false
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }
}

private enum LibraryRoute: Hashable {
    case groups
    case history
    case randomPicker
    case search
    case settings
    case importBook
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
                asCopy: true
            )
            picker.delegate = self
            picker.presentationController?.delegate = self
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
    @Published var allBooks: [Book] = []
    @Published var groups: [BookGroup] = []
    @Published var settings = LibrarySettings.default
    @Published var selectedBookIDs: Set<UUID> = []
    @Published var isSelectionMode = false
    @Published var isImporting = false
    @Published var importErrorTitle: LocalizedStringKey = "library.error.title"
    @Published var importErrorMessage: String?
    @Published var importPreview: ImportBookPreview?
    private var currentImportTask: Task<Void, Never>?

    var isSelecting: Bool {
        isSelectionMode
    }

    var selectionCountText: String {
        String(
            format: NSLocalizedString("library.selection.count", comment: ""),
            selectedBookIDs.count
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
            allBooks = try await repository.fetchBooks(
                scope: .all,
                sortOrder: settings.sortOrder
            )
            books = try await repository.fetchBooks(
                scope: scope,
                sortOrder: settings.sortOrder
            )
            pruneSelection()
        } catch {
            showError(error, title: "library.error.title")
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
            async let fetchedAllBooks = repository.fetchBooks(
                scope: .all,
                sortOrder: settings.sortOrder
            )
            async let fetchedBooks = repository.fetchBooks(
                scope: scope,
                sortOrder: settings.sortOrder
            )
            groups = try await fetchedGroups
            allBooks = try await fetchedAllBooks
            books = try await fetchedBooks
            pruneSelection()
        } catch {
            showError(error, title: "library.error.title")
        }
    }

    func handleImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService
    ) {
        guard !isImporting else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            prepareImportPreview(from: url, importService: importService)
        case let .failure(error):
            showError(error, title: "import.error.title")
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
        isSelectionMode = true
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
        isSelectionMode = true
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs = visibleIDs.subtracting(selectedBookIDs)
    }

    func exitSelection() {
        isSelectionMode = false
        selectedBookIDs.removeAll()
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
                showError(error, title: "library.move.error.title")
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
                exitSelection()
                await loadBooks(repository: repository, scope: scope)
            } catch {
                showError(error, title: "library.delete.error.title")
            }
        }
    }

    func exportURLs(fileStore: AppFileStore) throws -> [URL] {
        cleanupExportDirectory()
        let exportDirectory = exportDirectoryURL()
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        var usedFileNames: Set<String> = []
        return try books
            .filter { selectedBookIDs.contains($0.id) }
            .map { book in
                let contentURL = try fileStore.url(forRelativePath: book.sourcePath)
                let fileName = exportFileName(for: book, contentURL: contentURL, usedFileNames: &usedFileNames)
                let destinationURL = exportDirectory.appendingPathComponent(fileName, isDirectory: false)
                try FileManager.default.copyItem(at: contentURL, to: destinationURL)
                return destinationURL
            }
    }

    func cleanupExportDirectory() {
        try? FileManager.default.removeItem(at: exportDirectoryURL())
    }

    private func exportDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkExports", isDirectory: true)
    }

    private func exportFileName(
        for book: Book,
        contentURL: URL,
        usedFileNames: inout Set<String>
    ) -> String {
        let rawTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedExportFileName(
            rawTitle.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : rawTitle
        )
        let contentExtension = contentURL.pathExtension
        let fileExtension = contentExtension.isEmpty ? "txt" : contentExtension
        var candidate = "\(baseName).\(fileExtension)"
        var suffix = 2
        while usedFileNames.contains(candidate) {
            candidate = "\(baseName) \(suffix).\(fileExtension)"
            suffix += 1
        }
        usedFileNames.insert(candidate)
        return candidate
    }

    private func sanitizedExportFileName(_ fileName: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = fileName
            .components(separatedBy: illegalCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : sanitized
    }

    private func prepareImportPreview(
        from url: URL,
        importService: ImportService
    ) {
        isImporting = true
        currentImportTask = Task {
            do {
                importPreview = try await importService.previewImport(from: url)
                try Task.checkCancellation()
                currentImportTask = nil
            } catch {
                if !Task.isCancelled {
                    showError(error, title: "import.error.title")
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
                showError(error, title: "settings.error.title")
            }
        }
    }

    func showError(_ error: Error, title: LocalizedStringKey) {
        importErrorTitle = title
        importErrorMessage = error.localizedDescription
    }

    func clearError() {
        importErrorMessage = nil
    }

    func clearImportPreview() {
        importPreview = nil
    }

    private func pruneSelection() {
        let visibleIDs = Set(books.map(\.id))
        selectedBookIDs.formIntersection(visibleIDs)
    }
}

private struct BookShelfItemButton<Content: View>: View {
    let isSelected: Bool
    @State private var suppressNextTap = false
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
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                guard !suppressNextTap else {
                    suppressNextTap = false
                    return
                }
                action()
            }
            .onLongPressGesture(minimumDuration: 0.18) {
                suppressNextTap = true
                longPressAction()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    suppressNextTap = false
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BookRowView: View {
    let book: Book
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: BookListStyle.coverTrailingSpacing) {
            thumbnailView

            VStack(alignment: .leading, spacing: 8) {
                Text(displayTitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    PreciseProgressBar(value: clampedProgress)
                        .frame(maxWidth: 120)
                        .frame(height: BookListStyle.progressHeight)

                    Text(progressText)
                        .font(.system(size: 13))
                        .foregroundColor(BookCoverStyle.progressText)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, minHeight: BookListStyle.coverHeight, alignment: .topLeading)
            .padding(.top, BookListStyle.textTopOffset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, BookListStyle.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var thumbnailView: some View {
        BookCoverPlaceholder(
            title: book.title,
            isSelecting: isSelecting,
            isSelected: isSelected,
            initialFontSize: BookListStyle.coverInitialFontSize,
            selectionPadding: 5
        )
        .frame(
            width: BookListStyle.coverWidth,
            height: BookListStyle.coverHeight
        )
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
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
        VStack(alignment: .leading, spacing: 6) {
            coverView

            Text(displayTitle)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Text(progressText)
                .font(.system(size: 12))
                .foregroundColor(BookCoverStyle.progressText)
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
        }
        .padding(.horizontal, BookGridStyle.coverHorizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var coverView: some View {
        BookCoverPlaceholder(
            title: book.title,
            isSelecting: isSelecting,
            isSelected: isSelected,
            initialFontSize: BookGridStyle.coverInitialFontSize,
            selectionPadding: 6
        )
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var clampedProgress: Double {
        min(max(book.progressPercentage, 0), 1)
    }

    private var progressText: String {
        let progress = NumberFormatter.readingProgress.string(from: NSNumber(value: clampedProgress)) ?? "0%"
        return String(
            format: NSLocalizedString("library.grid.progress", comment: ""),
            progress
        )
    }
}

private struct BookCoverPlaceholder: View {
    let title: String
    let isSelecting: Bool
    let isSelected: Bool
    let initialFontSize: CGFloat
    let selectionPadding: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: BookCoverStyle.cornerRadius)
                .fill(BookCoverStyle.background)
                .overlay {
                    Text(verbatim: coverInitial)
                        .font(.system(size: initialFontSize, weight: .semibold))
                        .foregroundColor(BookCoverStyle.coverText)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: BookCoverStyle.cornerRadius)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                }
                .brightness(isSelecting && !isSelected ? -0.18 : 0)

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color(.systemGray),
                        Color.white
                    )
                    .padding(selectionPadding)
            }
        }
    }

    private var coverInitial: String {
        title
            .firstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
    }
}

private struct PreciseProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedValue = min(max(value, 0), 1)
            let fillWidth = proxy.size.width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))

                if fillWidth > 0 {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: fillWidth)
                }
            }
        }
        .accessibilityValue(Text(progressText))
    }

    private var progressText: String {
        NumberFormatter.readingProgress.string(from: NSNumber(value: min(max(value, 0), 1))) ?? "0%"
    }
}

private enum BookListStyle {
    static let coverWidth: CGFloat = 60
    static let coverHeight: CGFloat = 84
    static let coverInitialFontSize: CGFloat = 32
    static let coverTrailingSpacing: CGFloat = 14
    static let progressHeight: CGFloat = 4
    static let textTopOffset: CGFloat = 5
    static let verticalPadding: CGFloat = 12
}

private enum BookGridStyle {
    static let columnSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 22
    static let coverHorizontalInset: CGFloat = 6
    static let coverInitialFontSize: CGFloat = 40
}

private enum BookCoverStyle {
    static let cornerRadius: CGFloat = 5
    static let background = Color(.systemGray5)
    static let coverText = Color(.darkGray).opacity(0.62)
    static let progressText = Color(.systemGray)
}

private extension String {
    var firstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
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
    let repository: (any LibraryRepository)?
    let sortOrder: LibrarySettings.SortOrder
    let onOpenBook: (Book) -> Void

    @State private var keyword = ""
    @State private var results: [Book] = []
    @State private var historyItems: [SearchHistoryItem] = []
    @State private var errorMessage: String?
    @State private var searchFocusToken = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var shouldSkipNextLiveSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)

                FocusableSearchTextField(
                    text: $keyword,
                    placeholder: NSLocalizedString("search.field.placeholder", comment: ""),
                    focusToken: searchFocusToken
                ) {
                    performSearch(shouldSaveHistory: true)
                }
                .frame(height: SearchBarStyle.height)

                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        results = []
                        errorMessage = nil
                        searchTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(Text("search.clearInput"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: SearchBarStyle.height)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: SearchBarStyle.cornerRadius, style: .continuous))

            if shouldShowHistory {
                historySection
            }

            resultList
        }
        .padding()
        .navigationTitle("search.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reloadHistory()
        }
        .onChange(of: keyword) { _ in
            guard !shouldSkipNextLiveSearch else {
                shouldSkipNextLiveSearch = false
                return
            }
            scheduleLiveSearch()
        }
        .onAppear {
            focusSearchField()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
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

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowHistory: Bool {
        trimmedKeyword.isEmpty && !historyItems.isEmpty
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
                            shouldSkipNextLiveSearch = item.keyword != keyword
                            keyword = item.keyword
                            performSearch(keyword: item.keyword, shouldSaveHistory: true)
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
        if trimmedKeyword.isEmpty {
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
                .listRowBackground(Color.white)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                )
            }
            .listStyle(.plain)
            .background(Color.white)
            .padding(.horizontal, -16)
        }
    }

    private func scheduleLiveSearch() {
        searchTask?.cancel()
        errorMessage = nil

        let keyword = trimmedKeyword
        guard !keyword.isEmpty else {
            results = []
            searchTask = nil
            return
        }

        searchTask = Task {
            await runSearch(keyword: keyword, shouldSaveHistory: false)
        }
    }

    private func performSearch(shouldSaveHistory: Bool) {
        performSearch(keyword: trimmedKeyword, shouldSaveHistory: shouldSaveHistory)
    }

    private func performSearch(keyword: String, shouldSaveHistory: Bool) {
        searchTask?.cancel()
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            errorMessage = nil
            searchTask = nil
            return
        }

        searchTask = Task {
            await runSearch(keyword: keyword, shouldSaveHistory: shouldSaveHistory)
        }
    }

    @MainActor
    private func runSearch(keyword: String, shouldSaveHistory: Bool) async {
        guard let repository,
              !keyword.isEmpty
        else {
            results = []
            return
        }

        do {
            if shouldSaveHistory {
                try await repository.saveSearchKeyword(keyword)
            }
            let searchResults = try await repository.searchBooks(
                keyword: keyword,
                sortOrder: sortOrder
            )

            guard !Task.isCancelled,
                  keyword == trimmedKeyword
            else {
                return
            }

            results = searchResults

            if shouldSaveHistory {
                await reloadHistory()
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
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

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + SearchBarStyle.focusDelay) {
            searchFocusToken += 1
        }
    }
}

private struct FocusableSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> SearchTextField {
        let textField = SearchTextField()
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.returnKeyType = .search
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .never
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: SearchTextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder

        guard focusToken != context.coordinator.lastFocusToken else {
            return
        }
        context.coordinator.lastFocusToken = focusToken
        textField.focusWhenReady()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void
        var lastFocusToken = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return true
        }
    }

    final class SearchTextField: UITextField {
        private var needsFocus = false

        func focusWhenReady() {
            needsFocus = true
            requestFocusIfPossible()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            requestFocusIfPossible()
        }

        private func requestFocusIfPossible() {
            guard needsFocus,
                  window != nil,
                  !isFirstResponder
            else {
                return
            }

            needsFocus = false
            DispatchQueue.main.async { [weak self] in
                self?.becomeFirstResponder()
            }
        }
    }
}

private enum SearchBarStyle {
    static let height: CGFloat = 36
    static let cornerRadius: CGFloat = 10
    static let focusDelay: TimeInterval = 0.65
}

private struct ExportPayload: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]
}

private struct PendingBookDeletion: Identifiable {
    let id: String
    let ids: Set<UUID>

    init(ids: Set<UUID>) {
        self.ids = ids
        self.id = ids.map(\.uuidString).sorted().joined(separator: "-")
    }

    var message: String {
        if ids.count <= 1 {
            return NSLocalizedString("library.delete.confirm.single.message", comment: "")
        }
        return String(
            format: NSLocalizedString("library.delete.confirm.multiple.message", comment: ""),
            ids.count
        )
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
