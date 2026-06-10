import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel = LibraryViewModel()
    @State private var activeDrawer: LibraryDrawerSide?
    @State private var activeReaderBook: Book?
    @State private var isImportPickerPresented = false
    @State private var isBatchImportPickerPresented = false
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
                    allowedContentTypes: [Self.txtContentType],
                    asCopy: true,
                    allowsMultipleSelection: false
                ) { result in
                    guard case let .ready(services) = environment.bootstrapState else {
                        return
                    }
                    viewModel.handleImportResult(
                        result,
                        importService: services.importService,
                        targetGroupID: currentImportGroupID
                    )
                }
                .frame(width: 0, height: 0)

                DocumentPickerPresenter(
                    isPresented: $isBatchImportPickerPresented,
                    allowedContentTypes: [.folder],
                    asCopy: false,
                    allowsMultipleSelection: false
                ) { result in
                    guard case let .ready(services) = environment.bootstrapState else {
                        return
                    }
                    viewModel.handleBatchImportResult(
                        result,
                        importService: services.importService,
                        targetGroupID: currentImportGroupID,
                        onCompleted: {
                            reloadBooksIfReady()
                        }
                    )
                }
                .frame(width: 0, height: 0)
            }
            .sheet(item: $exportPayload) { payload in
                ActivityPresenter(
                    activityItems: payload.urls.map { $0 as Any },
                    onComplete: {
                        BookExportService.cleanupExportDirectory(payload.directoryURL)
                    }
                )
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
            .onChange(of: isBatchImportPickerPresented) { isPresented in
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
        case .bootstrapping, .failed:
            return nil
        }
    }

    private var currentFileStore: AppFileStore? {
        switch environment.bootstrapState {
        case let .ready(services):
            return services.fileStore
        case .bootstrapping, .failed:
            return nil
        }
    }

    private var currentImportGroupID: UUID? {
        if case let .group(groupID) = selectedScope {
            return groupID
        }
        return nil
    }

    @ViewBuilder
    private func drawerView(for side: LibraryDrawerSide) -> some View {
        switch side {
        case .left:
            if case let .ready(services) = environment.bootstrapState {
                LibrarySidebarView(
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
                    viewModel.updateLibrarySettings(
                        settings,
                        repository: services.libraryRepository,
                        scope: selectedScope
                    )
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
                onImportFromFolder: {
                    requestBatchImportFromDrawer()
                },
                onOpenTagsPage: {
                    openRouteFromDrawer(.tags)
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
                tag: LibraryRoute.tags,
                selection: $activeRoute
            ) {
                LibraryTagsPage(
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
                        viewModel.updateLibrarySettings(
                            settings,
                            repository: services.libraryRepository,
                            scope: selectedScope
                        )
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
                        repository: services.libraryRepository,
                        targetGroupID: viewModel.importTargetGroupID,
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
                    ReaderV2HostView(
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
        case .bootstrapping:
            VStack(spacing: 12) {
                ProgressView()
                Text("bootstrap.loading.message")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
        case let .failed(bootstrapError):
            VStack(spacing: 16) {
                bootstrapErrorView(bootstrapError)
                Button {
                    environment.retryBootstrap()
                } label: {
                    Label {
                        Text("bootstrap.retry")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer(minLength: 0)
            }
        case .ready:
            if !viewModel.hasLoadedInitialData {
                shelfSkeletonView
            } else if viewModel.books.isEmpty {
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

    private var shelfSkeletonView: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 42, height: 58)

                    VStack(alignment: .leading, spacing: 9) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 13)
                            .frame(maxWidth: 180, alignment: .leading)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 10)
                            .frame(maxWidth: 112, alignment: .leading)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.tertiarySystemFill))
                            .frame(height: 10)
                            .frame(maxWidth: 220, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

            Button {
                isBatchImportPickerPresented = true
            } label: {
                Label {
                    Text("add.import.folder")
                } icon: {
                    Image(systemName: "folder.badge.plus")
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 9) {
                Text(verbatim: viewModel.batchImportProgress?.currentFileName ?? " ")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 240, height: 18)

                if let progress = viewModel.batchImportProgress,
                   progress.totalCount > 0 {
                    ProgressView(
                        value: Double(progress.processedCount),
                        total: Double(progress.totalCount)
                    )
                    .frame(width: 210)
                } else {
                    ProgressView()
                        .frame(width: 210, height: 20)
                }

                importProgressStatusRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: 280, height: 112)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var importProgressStatusRow: some View {
        if let countText = viewModel.importProgressCountText {
            HStack(spacing: 4) {
                Text(verbatim: viewModel.importProgressStatusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                FixedWidthImportBatchCountText(text: countText)

                Text("import.batch.count.unit")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 240, height: 22, alignment: .center)
        } else {
            Text(verbatim: viewModel.importProgressStatusText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 240, height: 22)
        }
    }

    private var bootstrapTaskID: String {
        switch environment.bootstrapState {
        case .bootstrapping:
            return "bootstrapping"
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
            let export = try viewModel.exportURLs(fileStore: fileStore)
            guard !export.urls.isEmpty else {
                return
            }
            exportPayload = ExportPayload(
                urls: export.urls,
                directoryURL: export.directoryURL
            )
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
            activeDrawer = nil
            return
        }

        withAnimation(Self.drawerAnimation) {
            isDrawerOpen = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerAnimationDuration) {
            guard !isDrawerOpen else {
                return
            }
            activeDrawer = nil
        }
    }

    private func requestImportFromDrawer() {
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerAnimationDuration + 0.02) {
            isImportPickerPresented = true
        }
    }

    private func requestBatchImportFromDrawer() {
        closeDrawer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.drawerAnimationDuration + 0.02) {
            isBatchImportPickerPresented = true
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
