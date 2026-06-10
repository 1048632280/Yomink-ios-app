import OSLog
import UIKit

private let readerV2Logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
    category: "ReaderV2"
)

private enum ReaderV2Error: LocalizedError {
    case emptyBook
    case layoutUnavailable
    case pageUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyBook:
            return NSLocalizedString("reader.error.bookNotFound", comment: "")
        case .layoutUnavailable:
            return NSLocalizedString("reader.error.layoutUnavailable", comment: "")
        case .pageUnavailable:
            return NSLocalizedString("reader.error.pageUnavailable", comment: "")
        }
    }
}

@MainActor
final class ReaderV2ViewController: UIViewController, UIGestureRecognizerDelegate {
    private let fileStore: AppFileStore
    private let repository: any LibraryRepository
    private let onClose: () -> Void
    private let onStatusBarHiddenChange: (Bool) -> Void

    private let menuView = ReaderV2MenuView()
    private let settingsPanelView = ReaderV2SettingsPanelView()
    private let autoReadPanelView = ReaderV2AutoReadPanelView()
    private let autoReadController = ReaderAutoReadController()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private lazy var systemAppearanceController = ReaderSystemAppearanceController(
        hostViewController: self,
        onStatusBarHiddenChange: onStatusBarHiddenChange
    )

    private var activeContainer: ReaderContainerProtocol?
    private var activeTurnPageType: ReaderTurnPageType = .horizontalScroll
    private var book: Book
    private var chapters: [Chapter] = []
    private var chapterProvider: ReaderChapterProvider?
    private var progressBridge: ReaderProgressBridge?
    private var recordBridge: ReaderRecordBridge?
    private var bookmarks: [Bookmark] = []
    private var currentBookmark: Bookmark?
    private var filterRules: [TextFilterRule] = []
    private var readerSettings = ReaderSettings.default
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var chromeTheme = ReaderChromeTheme.standard
    private var paginationCache: [Int: ReaderDivisionResult] = [:]
    private var loadedScrollChapterIndexes: [Int] = []
    private var currentPageModel: ReaderPageModel?
    private var pendingInitialRecord: ReaderRecord?
    private var lastPaginationSize = CGSize.zero
    private var isViewVisible = false
    private var shouldStartAutoReadAfterOpen = false
    private var autoReadEntryPageMode: ReaderSettings.PageMode?
    private var didRecordOpenHistory = false
    private var openedAt = Date()
    private weak var configuredInteractivePopGesture: UIGestureRecognizer?

    private var loadGeneration = 0
    private var openGeneration = 0
    private var saveGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var bookmarkTask: Task<Void, Never>?
    private var preloadTasks: [Int: Task<Void, Never>] = [:]

    init(
        book: Book,
        fileStore: AppFileStore,
        repository: any LibraryRepository,
        onClose: @escaping () -> Void,
        onStatusBarHiddenChange: @escaping (Bool) -> Void
    ) {
        self.book = book
        self.fileStore = fileStore
        self.repository = repository
        self.onClose = onClose
        self.onStatusBarHiddenChange = onStatusBarHiddenChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        openTask?.cancel()
        saveTask?.cancel()
        settingsSaveTask?.cancel()
        bookmarkTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        NotificationCenter.default.removeObserver(self)
        let autoReadController = autoReadController
        Task { @MainActor in
            autoReadController.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    override var prefersStatusBarHidden: Bool {
        systemAppearanceController.prefersStatusBarHidden
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        systemAppearanceController.preferredStatusBarStyle
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        Self.homeIndicatorAutoHidden(for: readerSettings)
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        Self.screenEdgesDeferringSystemGestures(for: readerSettings)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.backgroundColor
        configureContainer(for: activeTurnPageType)
        configureMenu()
        configureSettingsPanel()
        configureAutoReadPanel()
        configureAutoReadController()
        configureLoadingIndicator()
        configureTapGesture()
        configureLifecycleObservers()
        startInitialLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isViewVisible = true
        restoreReaderInteractivePopGesture()
        bindReaderGesturesToInteractivePopIfNeeded()
        if deferNavigationBarHidingForAuxiliaryReturn() {
            scheduleNavigationBarHidingAfterAuxiliaryReturn()
        } else {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
        resumeAutoReadingAfterPauseIfNeeded()
        updateSystemAppearance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        restoreReaderInteractivePopGesture()
        bindReaderGesturesToInteractivePopIfNeeded()
        if navigationController?.topViewController === navigationStackControllerForReader() {
            navigationController?.setNavigationBarHidden(true, animated: false)
        }
        updateHomeIndicatorPreferences()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reopenIfPaginationSizeChanged()
        openPendingInitialRecordIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        pauseAutoReadingForBackground()
        saveProgressImmediately()
        updateSystemAppearance()
    }

    func update(book: Book) {
        guard book.id != self.book.id else {
            return
        }
        self.book = book
        menuView.configure(bookTitle: book.title)
        resetReaderState()
        startInitialLoad()
    }

    private func configureContainer(for turnPageType: ReaderTurnPageType) {
        guard activeContainer == nil || activeTurnPageType != turnPageType else {
            activeContainer?.apply(theme: theme)
            return
        }

        if let currentContainer = activeContainer?.viewController {
            currentContainer.willMove(toParent: nil)
            currentContainer.view.removeFromSuperview()
            currentContainer.removeFromParent()
        }

        let container: ReaderContainerProtocol
        switch turnPageType {
        case .horizontalScroll:
            container = ReaderPageContainer()
        case .pageCurl:
            container = ReaderPageCurlContainer()
        case .verticalContinuous:
            container = ReaderScrollContainer()
        }

        container.makePageController = { [weak self] pageModel in
            self?.makePageViewController(for: pageModel)
        }
        container.adjacentPageModel = { [weak self] pageModel, delta in
            self?.adjacentPageModel(from: pageModel, delta: delta)
        }
        container.onPageTurnCompleted = { [weak self] pageModel in
            self?.pageTurnCompleted(to: pageModel)
        }
        container.onTextSelectionAction = { [weak self] action, text in
            self?.handleTextSelectionAction(action, text: text)
        }
        if let scrollContainer = container as? ReaderScrollContainer {
            scrollContainer.onLoadPreviousChapter = { [weak self] in
                self?.loadPreviousScrollChapterIfNeeded()
            }
            scrollContainer.onLoadNextChapter = { [weak self] in
                self?.loadNextScrollChapterIfNeeded()
            }
        }

        let containerViewController = container.viewController
        addChild(containerViewController)
        containerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(containerViewController.view, at: 0)
        NSLayoutConstraint.activate([
            containerViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            containerViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        containerViewController.didMove(toParent: self)

        activeContainer = container
        activeTurnPageType = turnPageType
        container.apply(theme: theme)
        bindReaderGesturesToInteractivePopIfNeeded()
        updateHomeIndicatorPreferences()

        if let currentPageModel,
           paginationCache[currentPageModel.chapterIndex]?.pages.indices.contains(currentPageModel.pageIndex) == true {
            try? display(
                pageModel: currentPageModel,
                direction: .forward,
                animated: false,
                savesProgress: false,
                recordsOpenHistory: false
            )
        }
    }

    private func configureMenu() {
        menuView.translatesAutoresizingMaskIntoConstraints = false
        menuView.configure(bookTitle: book.title)
        menuView.onClose = { [weak self] in
            self?.closeReader()
        }
        menuView.onCatalog = { [weak self] in
            self?.showContents()
        }
        menuView.onBookmark = { [weak self] in
            self?.toggleBookmark()
        }
        menuView.onSettings = { [weak self] in
            self?.showSettingsPanelFromReaderMenu()
        }
        menuView.onPreviousChapter = { [weak self] in
            self?.stopAutoReading(animated: false)
            self?.goToChapter(delta: -1)
        }
        menuView.onAutoRead = { [weak self] in
            self?.autoReadButtonTapped()
        }
        menuView.onNextChapter = { [weak self] in
            self?.stopAutoReading(animated: false)
            self?.goToChapter(delta: 1)
        }
        menuView.onDarkMode = { [weak self] in
            self?.toggleDarkMode()
        }
        menuView.onMoreBookDetail = { [weak self] in
            self?.showBookDetail()
        }
        menuView.onMoreContentSearch = { [weak self] in
            self?.showContentSearch(initialKeyword: nil)
        }
        menuView.onMoreContentFilter = { [weak self] in
            self?.showFilterRules(initialSource: nil)
        }
        menuView.onMorePageTouchAreas = { [weak self] in
            self?.showPageTouchAreas()
        }
        menuView.onProgressSliderBegan = { [weak self] in
            self?.stopAutoReading(animated: false)
        }
        menuView.onProgressSliderChanged = { [weak self] progress in
            self?.updateMenuProgressPreview(chapterProgress: progress)
        }
        menuView.onProgressSliderFinished = { [weak self] progress in
            self?.openProgressInCurrentChapter(progress)
        }
        view.addSubview(menuView)
        NSLayoutConstraint.activate([
            menuView.topAnchor.constraint(equalTo: view.topAnchor),
            menuView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        menuView.apply(chromeTheme: chromeTheme)
        updateMenuState()
    }

    private func configureSettingsPanel() {
        settingsPanelView.translatesAutoresizingMaskIntoConstraints = false
        settingsPanelView.onChange = { [weak self] settings in
            self?.applyReaderSettings(settings)
        }
        view.addSubview(settingsPanelView)
        NSLayoutConstraint.activate([
            settingsPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsPanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            settingsPanelView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -315
            )
        ])
        settingsPanelView.setSettings(readerSettings)
        settingsPanelView.apply(chromeTheme: chromeTheme)
    }

    private func configureAutoReadPanel() {
        autoReadPanelView.translatesAutoresizingMaskIntoConstraints = false
        autoReadPanelView.onSpeedChange = { [weak self] speed in
            self?.autoReadSpeedChanged(speed)
        }
        autoReadPanelView.onSpeedChangeFinished = { [weak self] speed in
            self?.autoReadSpeedChangeFinished(speed)
        }
        autoReadPanelView.onExit = { [weak self] in
            self?.stopAutoReading(animated: true)
        }
        autoReadPanelView.onIdleTimeout = { [weak self] in
            self?.setAutoReadPanelVisible(false, animated: true)
        }
        view.addSubview(autoReadPanelView)
        NSLayoutConstraint.activate([
            autoReadPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            autoReadPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            autoReadPanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            autoReadPanelView.heightAnchor.constraint(equalToConstant: 190)
        ])
        autoReadPanelView.setSpeed(readerSettings.normalized.autoReadSpeed)
        autoReadPanelView.apply(chromeTheme: chromeTheme)
    }

    private func configureAutoReadController() {
        autoReadController.onScrollTick = { [weak self] in
            self?.autoReadDidScroll()
        }
        autoReadController.onProgressSaveNeeded = { [weak self] in
            self?.saveProgressImmediately()
        }
        autoReadController.onReachedEnd = { [weak self] in
            self?.autoReadReachedLoadedContentEnd() ?? false
        }
    }

    private func configureLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func refreshSettingsProjection() {
        layout = ReaderThemeManager.layout(from: readerSettings)
        theme = ReaderThemeManager.theme(from: readerSettings)
        chromeTheme = ReaderThemeManager.chromeTheme(from: readerSettings)
        view.backgroundColor = theme.backgroundColor
        overrideUserInterfaceStyle = theme.isDark ? .dark : .light
        activeContainer?.apply(theme: theme)
        menuView.apply(chromeTheme: chromeTheme)
        settingsPanelView.setSettings(readerSettings)
        settingsPanelView.apply(chromeTheme: chromeTheme)
        autoReadPanelView.setSpeed(readerSettings.normalized.autoReadSpeed)
        autoReadPanelView.apply(chromeTheme: chromeTheme)
        autoReadController.updateSpeed(readerSettings.normalized.autoReadSpeed)
        updateSystemAppearance()
    }

    private func applyReaderSettings(_ nextSettings: ReaderSettings) {
        let previousSettings = readerSettings
        let normalizedSettings = nextSettings.normalized
        guard normalizedSettings != previousSettings else {
            return
        }

        readerSettings = normalizedSettings
        updateHomeIndicatorPreferences()
        if autoReadController.isReading,
           normalizedSettings.pageMode != .scroll {
            stopAutoReading(animated: false, restoresEntryPageMode: false)
        }
        let needsRepagination = ReaderThemeManager.needsRepagination(
            from: previousSettings,
            to: normalizedSettings
        )
        refreshSettingsProjection()
        configureContainer(for: ReaderThemeManager.turnPageType(from: normalizedSettings))
        updateSystemAppearance()
        updateMenuState()
        saveReaderSettings(normalizedSettings)

        if needsRepagination {
            reopenCurrentPageAfterSettingsChange()
        } else if let currentPageModel {
            try? display(
                pageModel: currentPageModel,
                direction: .forward,
                animated: false,
                savesProgress: false,
                recordsOpenHistory: false
            )
        }
    }

    private func saveReaderSettings(_ settings: ReaderSettings) {
        settingsSaveTask?.cancel()
        let repository = repository
        settingsSaveTask = Task {
            do {
                try await repository.saveReaderSettings(settings.normalized)
            } catch is CancellationError {
            } catch {
                readerV2Logger.error("ReaderV2 save settings failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func reopenCurrentPageAfterSettingsChange() {
        guard let record = recordForCurrentPage() else {
            paginationCache.removeAll()
            loadedScrollChapterIndexes.removeAll()
            return
        }
        openTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
        paginationCache.removeAll()
        loadedScrollChapterIndexes.removeAll()
        if currentPaginationSize() == nil {
            pendingInitialRecord = record
            return
        }
        open(record: record, animated: false)
    }

    private func recordForCurrentPage() -> ReaderRecord? {
        guard let currentPageModel else {
            return pendingInitialRecord
        }
        let progress = ReaderPageCalculator.pageProgress(
            pageCount: currentPageModel.pageCount,
            pageIndex: currentPageModel.pageIndex,
            progress: currentPageModel.chapterProgress,
            usesPageIndex: true
        )
        return ReaderRecord(
            chapterIndex: currentPageModel.chapterIndex,
            progress: progress,
            chapterTitle: chapterTitle(at: currentPageModel.chapterIndex)
        )
    }

    private func configureLoadingIndicator() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureTapGesture() {
        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(pageTapGestureRecognized(_:))
        )
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    private func startInitialLoad() {
        loadGeneration += 1
        let generation = loadGeneration
        let repository = repository
        let bookID = book.id
        showLoading(true)

        loadTask?.cancel()
        loadTask = Task { [weak self] in
            do {
                async let chapters = repository.fetchChapters(bookID: bookID)
                async let progress = repository.fetchReadingProgress(bookID: bookID)
                async let settings = repository.fetchReaderSettings()
                async let bookmarks = repository.fetchBookmarks(bookID: bookID)
                async let filterRules = repository.fetchFilterRules(bookID: bookID)
                let loadedChapters = try await chapters
                let loadedProgress = try await progress
                let loadedSettings = try await settings
                let loadedBookmarks = try await bookmarks
                let loadedFilterRules = try await filterRules
                try Task.checkCancellation()

                guard let self,
                      self.loadGeneration == generation else {
                    return
                }
                self.finishInitialLoad(
                    chapters: loadedChapters,
                    progress: loadedProgress,
                    settings: loadedSettings,
                    bookmarks: loadedBookmarks,
                    filterRules: loadedFilterRules
                )
            } catch is CancellationError {
            } catch {
                guard let self,
                      self.loadGeneration == generation else {
                    return
                }
                self.showLoading(false)
                self.showError(error)
            }
        }
    }

    private func finishInitialLoad(
        chapters: [Chapter],
        progress: ReadingProgress?,
        settings: ReaderSettings,
        bookmarks: [Bookmark],
        filterRules: [TextFilterRule]
    ) {
        guard chapters.isEmpty == false else {
            showLoading(false)
            showError(ReaderV2Error.emptyBook)
            return
        }

        self.chapters = chapters
        self.bookmarks = bookmarks
        self.filterRules = filterRules
        currentBookmark = nil
        readerSettings = settings.normalized
        refreshSettingsProjection()
        paginationCache.removeAll()
        loadedScrollChapterIndexes.removeAll()
        configureContainer(for: ReaderThemeManager.turnPageType(from: readerSettings))
        updateSystemAppearance()
        updateMenuState()

        let adapter = ReaderBookAdapter(
            book: book,
            chapters: chapters,
            fileStore: fileStore
        )
        chapterProvider = adapter.chapterProvider
        progressBridge = adapter.progressBridge
        recordBridge = adapter.recordBridge
        pendingInitialRecord = adapter.progressBridge.record(from: progress)
        openPendingInitialRecordIfPossible()
    }

    private func resetReaderState() {
        loadTask?.cancel()
        openTask?.cancel()
        saveTask?.cancel()
        bookmarkTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
        stopAutoReading(animated: false)
        shouldStartAutoReadAfterOpen = false
        chapters = []
        chapterProvider = nil
        progressBridge = nil
        recordBridge = nil
        bookmarks = []
        currentBookmark = nil
        filterRules = []
        bookmarkTask = nil
        paginationCache.removeAll()
        loadedScrollChapterIndexes.removeAll()
        currentPageModel = nil
        pendingInitialRecord = nil
        didRecordOpenHistory = false
        openedAt = Date()
        lastPaginationSize = .zero
    }

    private func currentPaginationSize() -> CGSize? {
        guard view.bounds.width > 2,
              view.bounds.height > 2 else {
            return nil
        }
        if activeTurnPageType == .verticalContinuous {
            return CGSize(
                width: max(1, view.bounds.width - layout.leftMargin - layout.rightMargin),
                height: max(1, view.bounds.height)
            )
        }
        return layout.contentRect(in: view.bounds).size
    }

    private func reopenIfPaginationSizeChanged() {
        guard let size = currentPaginationSize() else {
            return
        }
        let changed = abs(size.width - lastPaginationSize.width) > 1
            || abs(size.height - lastPaginationSize.height) > 1
        guard changed else {
            return
        }
        lastPaginationSize = size
        paginationCache.removeAll()
        loadedScrollChapterIndexes.removeAll()

        if let currentPageModel,
           pendingInitialRecord == nil {
            let progress = ReaderPageCalculator.pageProgress(
                pageCount: currentPageModel.pageCount,
                pageIndex: currentPageModel.pageIndex,
                progress: currentPageModel.chapterProgress,
                usesPageIndex: true
            )
            let record = ReaderRecord(
                chapterIndex: currentPageModel.chapterIndex,
                progress: progress,
                chapterTitle: chapterTitle(at: currentPageModel.chapterIndex)
            )
            open(record: record, animated: false)
        }
    }

    private func openPendingInitialRecordIfPossible() {
        guard let record = pendingInitialRecord,
              currentPaginationSize() != nil else {
            return
        }
        pendingInitialRecord = nil
        open(record: record, animated: false)
    }

    private func open(
        record: ReaderRecord,
        animated: Bool,
        showsLoading: Bool = true,
        closesMenuOnSuccess: Bool = false,
        onSuccess: (() -> Void)? = nil
    ) {
        openGeneration += 1
        let generation = openGeneration
        if showsLoading {
            showLoading(true)
        }
        openTask?.cancel()
        if activeTurnPageType == .verticalContinuous {
            preloadTasks.values.forEach { $0.cancel() }
            preloadTasks.removeAll()
            loadedScrollChapterIndexes.removeAll()
        }
        openTask = Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let model = try await self.pageModel(from: record)
                try Task.checkCancellation()
                guard self.openGeneration == generation else {
                    return
                }
                try self.display(
                    pageModel: model,
                    direction: .forward,
                    animated: animated,
                    savesProgress: true,
                    recordsOpenHistory: true
                )
                if closesMenuOnSuccess {
                    self.closeReaderMenuOverlays(animated: false)
                }
                onSuccess?()
                if showsLoading {
                    self.showLoading(false)
                }
            } catch is CancellationError {
            } catch {
                guard let self,
                      self.openGeneration == generation else {
                    return
                }
                if showsLoading {
                    self.showLoading(false)
                }
                self.showError(error)
            }
        }
    }

    private func pageModel(from record: ReaderRecord) async throws -> ReaderPageModel {
        guard let chapterProvider,
              chapterProvider.chapterCount > 0 else {
            throw ReaderV2Error.emptyBook
        }
        let chapterIndex = min(max(record.chapterIndex, 0), chapterProvider.chapterCount - 1)
        let result = try await divisionResult(forChapterAt: chapterIndex)
        let pageIndex = ReaderPageCalculator.pageIndex(
            pageCount: result.pageCount,
            pageIndex: 0,
            progress: record.progress,
            usesPageIndex: false
        )
        return ReaderPageModel(
            chapterCount: chapterProvider.chapterCount,
            chapterIndex: chapterIndex,
            pageCount: result.pageCount,
            pageIndex: pageIndex,
            chapterProgress: record.progress,
            usesPageIndex: true
        )
    }

    private func divisionResult(forChapterAt index: Int) async throws -> ReaderDivisionResult {
        if let cached = paginationCache[index] {
            return cached
        }
        guard let chapterProvider,
              let chapter = chapterProvider.chapter(at: index) else {
            throw ReaderChapterProviderError.missingChapter
        }
        guard let pageSize = currentPaginationSize() else {
            throw ReaderV2Error.layoutUnavailable
        }

        let rawText = try await chapterProvider.textAsync(forChapterAt: index)
        let text = ReaderTextFilter.readingFilteredText(
            rules: filterRules,
            to: rawText
        ).displayText
        let manager = PaibanManager(layout: layout, theme: theme)
        let result = manager.divideText(
            text,
            chapterTitle: chapter.title,
            chapterIndex: index,
            pageSize: pageSize,
            doubleColumn: false,
            returnsHeights: activeTurnPageType == .verticalContinuous
        )
        paginationCache[index] = result
        return result
    }

    private func display(
        pageModel: ReaderPageModel,
        direction: ReaderPageTurnDirection,
        animated: Bool,
        savesProgress: Bool,
        recordsOpenHistory: Bool
    ) throws {
        guard let activeContainer,
              let pageController = makePageViewController(for: pageModel) else {
            throw ReaderV2Error.pageUnavailable
        }
        if let scrollContainer = activeContainer as? ReaderScrollContainer {
            ensureScrollChapterLoaded(pageModel.chapterIndex)
            scrollContainer.reload(
                sections: scrollSections(),
                layout: layout,
                theme: theme,
                widgetVisibility: readerSettings.normalized.widgetVisibility
            )
        }
        activeContainer.display(
            pageModel: pageModel,
            pageController: pageController,
            direction: direction,
            animated: animated
        )
        currentPageModel = pageModel
        updateMenuState()
        if activeTurnPageType != .verticalContinuous {
            preloadAround(chapterIndex: pageModel.chapterIndex)
        }
        if shouldStartAutoReadAfterOpen {
            shouldStartAutoReadAfterOpen = false
            startAutoReadingIfPossible()
        }
        if savesProgress {
            saveProgress(
                for: pageModel,
                immediately: recordsOpenHistory,
                recordsOpenHistory: recordsOpenHistory
            )
        }
    }

    private func makePageViewController(for pageModel: ReaderPageModel) -> ReaderPageViewController? {
        guard let result = paginationCache[pageModel.chapterIndex],
              result.pages.indices.contains(pageModel.pageIndex) else {
            return nil
        }
        let controller = ReaderPageViewController()
        let fullProgress = globalProgress(
            chapterIndex: pageModel.chapterIndex,
            chapterProgress: ReaderPageCalculator.pageProgress(
                pageCount: pageModel.pageCount,
                pageIndex: pageModel.pageIndex,
                progress: pageModel.chapterProgress,
                usesPageIndex: pageModel.usesPageIndex
            )
        )
        controller.onTextSelectionAction = { [weak self] action, text in
            self?.handleTextSelectionAction(action, text: text)
        }
        controller.configure(
            page: result.pages[pageModel.pageIndex],
            pageModel: pageModel,
            layout: layout,
            theme: theme,
            chapterTitle: chapterTitle(at: pageModel.chapterIndex),
            bookTitle: book.title,
            fullProgress: fullProgress,
            widgetVisibility: readerSettings.normalized.widgetVisibility
        )
        return controller
    }

    private func adjacentPageModel(
        from pageModel: ReaderPageModel,
        delta: Int
    ) -> ReaderPageModel? {
        let targetPageIndex = pageModel.pageIndex + delta
        if targetPageIndex >= 0,
           targetPageIndex < pageModel.pageCount {
            return makePageModel(
                chapterIndex: pageModel.chapterIndex,
                pageIndex: targetPageIndex,
                pageCount: pageModel.pageCount
            )
        }

        let targetChapterIndex = pageModel.chapterIndex + delta
        guard chapters.indices.contains(targetChapterIndex),
              let result = paginationCache[targetChapterIndex],
              result.pageCount > 0 else {
            return nil
        }
        return makePageModel(
            chapterIndex: targetChapterIndex,
            pageIndex: delta > 0 ? 0 : result.pageCount - 1,
            pageCount: result.pageCount
        )
    }

    private func loadAdjacentPageModel(delta: Int) async throws -> ReaderPageModel? {
        guard let currentPageModel else {
            return nil
        }
        if let adjacent = adjacentPageModel(from: currentPageModel, delta: delta) {
            return adjacent
        }

        let targetChapterIndex = currentPageModel.chapterIndex + delta
        guard chapters.indices.contains(targetChapterIndex) else {
            return nil
        }
        let result = try await divisionResult(forChapterAt: targetChapterIndex)
        guard result.pageCount > 0 else {
            return nil
        }
        return makePageModel(
            chapterIndex: targetChapterIndex,
            pageIndex: delta > 0 ? 0 : result.pageCount - 1,
            pageCount: result.pageCount
        )
    }

    private func makePageModel(
        chapterIndex: Int,
        pageIndex: Int,
        pageCount: Int
    ) -> ReaderPageModel {
        ReaderPageModel(
            chapterCount: chapters.count,
            chapterIndex: chapterIndex,
            pageCount: pageCount,
            pageIndex: pageIndex,
            chapterProgress: ReaderPageCalculator.pageProgress(
                pageCount: pageCount,
                pageIndex: pageIndex,
                progress: 0,
                usesPageIndex: true
            ),
            usesPageIndex: true
        )
    }

    private func scrollSections() -> [ReaderScrollSection] {
        let chapterIndexes = activeTurnPageType == .verticalContinuous
            ? loadedScrollChapterIndexes
            : paginationCache.keys.sorted()
        return chapterIndexes.compactMap(scrollSection)
    }

    private func scrollSection(forChapterAt chapterIndex: Int) -> ReaderScrollSection? {
        guard let result = paginationCache[chapterIndex],
              result.pageCount > 0 else {
            return nil
        }

        let pageModels = result.pages.indices.map { pageIndex in
            makePageModel(
                chapterIndex: chapterIndex,
                pageIndex: pageIndex,
                pageCount: result.pageCount
            )
        }
        let fallbackHeight = max(lastPaginationSize.height, view.bounds.height, 1)
        let heights = result.pageHeights.count == result.pages.count
            ? result.pageHeights
            : Array(repeating: fallbackHeight, count: result.pages.count)
        return ReaderScrollSection(
            chapterIndex: chapterIndex,
            title: chapterTitle(at: chapterIndex),
            timestamp: Date(timeIntervalSince1970: Double(chapterIndex)),
            items: result.pages.map(\.attributedText),
            heights: heights,
            pageModels: pageModels,
            fullProgresses: pageModels.map { pageModel in
                globalProgress(
                    chapterIndex: pageModel.chapterIndex,
                    chapterProgress: pageModel.chapterProgress
                )
            },
            bookTitle: book.title
        )
    }

    private func insertLoadedScrollChapter(
        _ chapterIndex: Int,
        atBeginning: Bool
    ) -> Bool {
        guard chapters.indices.contains(chapterIndex),
              !loadedScrollChapterIndexes.contains(chapterIndex) else {
            return false
        }
        if atBeginning {
            loadedScrollChapterIndexes.insert(chapterIndex, at: 0)
        } else {
            loadedScrollChapterIndexes.append(chapterIndex)
        }
        return true
    }

    private func ensureScrollChapterLoaded(_ chapterIndex: Int) {
        let insertsAtBeginning = loadedScrollChapterIndexes.first.map {
            chapterIndex < $0
        } ?? false
        _ = insertLoadedScrollChapter(
            chapterIndex,
            atBeginning: insertsAtBeginning
        )
    }

    private func loadPreviousScrollChapterIfNeeded() {
        guard activeTurnPageType == .verticalContinuous,
              let first = loadedScrollChapterIndexes.first,
              chapters.indices.contains(first - 1),
              preloadTasks[first - 1] == nil else {
            return
        }
        let previousChapterIndex = first - 1
        if paginationCache[previousChapterIndex] != nil {
            let inserted = insertLoadedScrollChapter(
                previousChapterIndex,
                atBeginning: true
            )
            if let scrollContainer = activeContainer as? ReaderScrollContainer {
                if inserted,
                   let section = scrollSection(forChapterAt: previousChapterIndex) {
                    scrollContainer.prependSections([section])
                }
            }
            return
        }
        loadScrollChapter(previousChapterIndex, insertsAtBeginning: true)
    }

    @discardableResult
    private func loadNextScrollChapterIfNeeded(
        resumesAutoReadAfterLoad: Bool = false
    ) -> Bool {
        guard activeTurnPageType == .verticalContinuous,
              let last = loadedScrollChapterIndexes.last ?? currentPageModel?.chapterIndex else {
            return false
        }
        let nextChapterIndex = last + 1
        guard chapters.indices.contains(nextChapterIndex) else {
            return false
        }
        if preloadTasks[nextChapterIndex] != nil {
            return true
        }
        if paginationCache[nextChapterIndex] != nil {
            let inserted = insertLoadedScrollChapter(
                nextChapterIndex,
                atBeginning: false
            )
            if let scrollContainer = activeContainer as? ReaderScrollContainer {
                if inserted,
                   let section = scrollSection(forChapterAt: nextChapterIndex) {
                    scrollContainer.appendSections([section]) { [weak self, weak scrollContainer] in
                        guard let self,
                              let scrollContainer else {
                            return
                        }
                        guard resumesAutoReadAfterLoad
                            || self.autoReadController.isPausedForContentLoad else {
                            return
                        }
                        self.autoReadController.resumeAfterContentLoadIfNeeded(
                            scrollView: scrollContainer.tableView
                        )
                    }
                } else if resumesAutoReadAfterLoad
                    || autoReadController.isPausedForContentLoad {
                    autoReadController.resumeAfterContentLoadIfNeeded(
                        scrollView: scrollContainer.tableView
                    )
                }
            }
            return true
        }
        loadScrollChapter(
            nextChapterIndex,
            insertsAtBeginning: false,
            resumesAutoReadAfterLoad: resumesAutoReadAfterLoad
        )
        return true
    }

    private func loadScrollChapter(
        _ chapterIndex: Int,
        insertsAtBeginning: Bool,
        resumesAutoReadAfterLoad: Bool = false
    ) {
        preloadTasks[chapterIndex] = Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                _ = try await self.divisionResult(forChapterAt: chapterIndex)
                let inserted = self.insertLoadedScrollChapter(
                    chapterIndex,
                    atBeginning: insertsAtBeginning
                )
                if let scrollContainer = self.activeContainer as? ReaderScrollContainer {
                    let shouldResumeAutoRead = resumesAutoReadAfterLoad
                        || self.autoReadController.isPausedForContentLoad
                    if inserted,
                       let section = self.scrollSection(forChapterAt: chapterIndex) {
                        if insertsAtBeginning {
                            scrollContainer.prependSections([section])
                        } else {
                            scrollContainer.appendSections([section]) { [weak self, weak scrollContainer] in
                                guard let self,
                                      let scrollContainer else {
                                    return
                                }
                                guard shouldResumeAutoRead else {
                                    return
                                }
                                self.autoReadController.resumeAfterContentLoadIfNeeded(
                                    scrollView: scrollContainer.tableView
                                )
                            }
                        }
                    } else if !insertsAtBeginning,
                              shouldResumeAutoRead {
                        self.autoReadController.resumeAfterContentLoadIfNeeded(
                            scrollView: scrollContainer.tableView
                        )
                    }
                }
                self.preloadTasks[chapterIndex] = nil
            } catch is CancellationError {
                self?.preloadTasks[chapterIndex] = nil
            } catch {
                readerV2Logger.error("ReaderV2 scroll chapter load failed: \(error.localizedDescription, privacy: .public)")
                if insertsAtBeginning == false,
                   self?.autoReadController.isPausedForContentLoad == true {
                    self?.finishAutoReading(animated: true)
                }
                self?.preloadTasks[chapterIndex] = nil
            }
        }
    }

    private func preloadAround(chapterIndex: Int) {
        for index in [chapterIndex - 1, chapterIndex + 1] {
            guard chapters.indices.contains(index),
                  paginationCache[index] == nil,
                  preloadTasks[index] == nil else {
                continue
            }
            preloadTasks[index] = Task { [weak self] in
                do {
                    guard let self else {
                        return
                    }
                    _ = try await self.divisionResult(forChapterAt: index)
                    self.preloadTasks[index] = nil
                } catch is CancellationError {
                    self?.preloadTasks[index] = nil
                } catch {
                    readerV2Logger.error("ReaderV2 preload failed: \(error.localizedDescription, privacy: .public)")
                    self?.preloadTasks[index] = nil
                }
            }
        }
    }

    private func saveProgress(
        for pageModel: ReaderPageModel,
        immediately: Bool,
        recordsOpenHistory: Bool
    ) {
        guard let progress = progressBridge?.readingProgress(from: pageModel) else {
            return
        }
        saveGeneration += 1
        let generation = saveGeneration
        let repository = repository
        let bookID = book.id
        let openedAt = openedAt
        let shouldRecordOpenHistory = recordsOpenHistory && !didRecordOpenHistory
        if shouldRecordOpenHistory {
            didRecordOpenHistory = true
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                if !immediately {
                    try await Task.sleep(nanoseconds: 700_000_000)
                }
                try Task.checkCancellation()
                guard self?.saveGeneration == generation else {
                    return
                }
                try await repository.saveReadingProgress(progress)
                if shouldRecordOpenHistory {
                    try await repository.markBookOpened(id: bookID, at: openedAt)
                }
            } catch is CancellationError {
            } catch {
                readerV2Logger.error("ReaderV2 save progress failed: \(error.localizedDescription, privacy: .public)")
                if shouldRecordOpenHistory {
                    await MainActor.run {
                        self?.didRecordOpenHistory = false
                    }
                }
            }
        }
    }

    private func saveProgressImmediately() {
        guard let currentPageModel,
              let progress = progressBridge?.readingProgress(from: currentPageModel) else {
            return
        }
        saveGeneration += 1
        saveTask?.cancel()
        let repository = repository
        Task {
            do {
                try await repository.saveReadingProgress(progress)
            } catch {
                readerV2Logger.error("ReaderV2 immediate save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func showLoading(_ visible: Bool) {
        if visible {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func showError(_ error: Error) {
        guard presentedViewController == nil else {
            readerV2Logger.error("ReaderV2 error while another controller is presented: \(error.localizedDescription, privacy: .public)")
            return
        }
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func updateSystemAppearance() {
        systemAppearanceController.update(
            settings: readerSettings,
            theme: theme,
            isViewVisible: isViewVisible,
            isMenuVisible: menuView.isMenuVisible,
            isSettingsPanelVisible: settingsPanelView.isPanelVisible,
            isAutoReadPanelVisible: autoReadPanelView.isPanelVisible,
            isAutoReading: autoReadController.isReading
        )
        updateHomeIndicatorPreferences()
    }

    private func updateHomeIndicatorPreferences() {
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    static func homeIndicatorAutoHidden(for settings: ReaderSettings) -> Bool {
        settings.normalized.autoHideHomeIndicator
    }

    static func screenEdgesDeferringSystemGestures(for settings: ReaderSettings) -> UIRectEdge {
        homeIndicatorAutoHidden(for: settings) ? .bottom : []
    }

    private func chapterTitle(at index: Int) -> String {
        guard chapters.indices.contains(index) else {
            return ""
        }
        return chapters[index].title
    }

    private func updateMenuState() {
        let pageModel = currentPageModel
        menuView.configure(bookTitle: book.title)
        if let pageModel {
            let chapterProgress = ReaderPageCalculator.pageProgress(
                pageCount: pageModel.pageCount,
                pageIndex: pageModel.pageIndex,
                progress: pageModel.chapterProgress,
                usesPageIndex: pageModel.usesPageIndex
            )
            menuView.updateProgress(
                chapterTitle: chapterTitle(at: pageModel.chapterIndex),
                chapterProgress: chapterProgress,
                globalProgress: globalProgress(
                    chapterIndex: pageModel.chapterIndex,
                    chapterProgress: chapterProgress
                ),
                pageIndex: pageModel.pageIndex,
                pageCount: pageModel.pageCount
            )
            menuView.updateChapterNavigation(
                canGoPrevious: chapters.indices.contains(pageModel.chapterIndex - 1),
                canGoNext: chapters.indices.contains(pageModel.chapterIndex + 1)
            )
        } else {
            menuView.updateProgress(
                chapterTitle: "",
                chapterProgress: 0,
                globalProgress: 0,
                pageIndex: 0,
                pageCount: 1
            )
            menuView.updateChapterNavigation(canGoPrevious: false, canGoNext: false)
        }
        menuView.updateAutoRead(isReading: autoReadController.isReading)
        menuView.updateDarkMode(isDark: readerSettings.theme == .dark)
        updateBookmarkState()
    }

    private func selectedChapterIndex() -> Int {
        guard let currentPageModel,
              chapters.indices.contains(currentPageModel.chapterIndex) else {
            return 0
        }
        return currentPageModel.chapterIndex
    }

    private func currentReadingProgress() -> ReadingProgress? {
        guard let currentPageModel else {
            return nil
        }
        return progressBridge?.readingProgress(from: currentPageModel)
    }

    private func globalProgress(
        chapterIndex: Int,
        chapterProgress: Double
    ) -> Double {
        guard chapters.indices.contains(chapterIndex) else {
            return 0
        }
        let chapter = chapters[chapterIndex]
        let chapterOffset = chapterOffset(
            chapterIndex: chapterIndex,
            chapterProgress: chapterProgress
        )
        let total = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let absoluteOffset = chapter.startOffset + chapterOffset
        return min(max(Double(absoluteOffset) / Double(total), 0), 1)
    }

    private func chapterOffset(
        chapterIndex: Int,
        chapterProgress: Double
    ) -> Int {
        guard chapters.indices.contains(chapterIndex) else {
            return 0
        }
        let chapter = chapters[chapterIndex]
        guard chapter.byteLength > 0 else {
            return 0
        }
        let clamped = ReaderPageModel.clampedProgress(chapterProgress)
        return min(
            max(Int((Double(chapter.byteLength) * clamped).rounded(.down)), 0),
            max(chapter.byteLength - 1, 0)
        )
    }

    private func updateMenuProgressPreview(chapterProgress: Double) {
        guard let currentPageModel else {
            return
        }
        let clamped = ReaderPageModel.clampedProgress(chapterProgress)
        let lastPageIndex = max(currentPageModel.pageCount - 1, 0)
        let estimatedPageIndex = lastPageIndex > 0
            ? min(max(Int((Double(lastPageIndex) * clamped).rounded()), 0), lastPageIndex)
            : 0
        menuView.updateProgressPreview(
            chapterProgress: clamped,
            globalProgress: globalProgress(
                chapterIndex: currentPageModel.chapterIndex,
                chapterProgress: clamped
            ),
            pageIndex: estimatedPageIndex
        )
    }

    private func updateBookmarkState() {
        guard let progress = currentReadingProgress() else {
            currentBookmark = nil
            menuView.updateBookmark(isBookmarked: false)
            return
        }

        currentBookmark = bookmarks.first { bookmark in
            bookmark.chapterID == progress.chapterID
                && abs(bookmark.offset - Int(progress.chapterOffset)) < 12
        }
        menuView.updateBookmark(isBookmarked: currentBookmark != nil)
    }

    private func bookmarkPreview() -> String {
        guard let currentPageModel,
              let result = paginationCache[currentPageModel.chapterIndex],
              result.pages.indices.contains(currentPageModel.pageIndex) else {
            return NSLocalizedString("reader.bookmark.preview.empty", comment: "")
        }
        let preview = result.pages[currentPageModel.pageIndex]
            .attributedText
            .string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return preview.isEmpty
            ? NSLocalizedString("reader.bookmark.preview.empty", comment: "")
            : String(preview.prefix(80))
    }

    private func showContents() {
        guard chapters.isEmpty == false else {
            return
        }
        let listViewController = ReaderContentsViewController(
            bookID: book.id,
            repository: repository,
            chapters: chapters,
            selectedChapterIndex: selectedChapterIndex(),
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.updateBookmarkState()
            }
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpToAndReturnToReader(target)
        }
        pushReaderPage(listViewController)
    }

    private func showContentSearch(initialKeyword: String?) {
        guard chapters.isEmpty == false else {
            return
        }
        let searchViewController = ReaderContentSearchViewController(
            book: book,
            fileStore: fileStore,
            chapters: chapters,
            filterRules: filterRules,
            initialKeyword: initialKeyword
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpToAndReturnToReader(target)
        }
        pushReaderPage(searchViewController)
    }

    private func showBookDetail() {
        guard chapters.isEmpty == false else {
            return
        }
        let detailViewController = ReaderBookDetailViewController(
            book: book,
            repository: repository,
            fileStore: fileStore,
            chapters: chapters,
            selectedChapterIndex: selectedChapterIndex(),
            onBookUpdated: { [weak self] updatedBook in
                guard let self else {
                    return
                }
                self.book = updatedBook
                self.menuView.configure(bookTitle: updatedBook.title)
            },
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.updateBookmarkState()
            },
            onSelectCatalogTarget: { [weak self] target in
                guard let self else {
                    return
                }
                self.jumpToAndReturnToReader(target)
            }
        )
        pushReaderPage(detailViewController)
    }

    private func showFilterRules(initialSource: String?) {
        let filterViewController = ReaderFilterRulesViewController(
            bookID: book.id,
            repository: repository,
            rules: filterRules,
            initialSource: initialSource
        ) { [weak self] rules in
            guard let self else {
                return
            }
            self.filterRules = rules
            let record = self.recordForCurrentPage()
            self.paginationCache.removeAll()
            self.loadedScrollChapterIndexes.removeAll()
            self.preloadTasks.values.forEach { $0.cancel() }
            self.preloadTasks.removeAll()
            if let record {
                self.open(record: record, animated: false)
            }
        }
        pushReaderPage(filterViewController)
    }

    private func showPageTouchAreas() {
        let viewController = ReaderPageTouchAreasViewController(settings: readerSettings) { [weak self] settings in
            self?.applyReaderSettings(settings)
        }
        pushReaderPage(viewController, prefersNavigationBarHidden: true)
    }

    private func handleTextSelectionAction(
        _ action: ReaderTextSelectionAction,
        text: String
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }
        switch action {
        case .copy:
            return
        case .search:
            showContentSearch(initialKeyword: trimmed)
        case .filter:
            showFilterRules(initialSource: trimmed)
        }
    }

    private func jumpToAndReturnToReader(_ target: ReaderContentTarget) {
        stopAutoReading(animated: false)
        setMenuVisible(false, animated: false)
        guard let record = recordBridge?.record(from: target) else {
            return
        }
        open(
            record: record,
            animated: false,
            showsLoading: false,
            closesMenuOnSuccess: true
        ) { [weak self] in
            self?.closeAuxiliaryReaderPage(animated: true) {}
        }
    }

    private func restoreReaderInteractivePopGesture() {
        guard let navigationController,
              let gesture = navigationController.interactivePopGestureRecognizer
        else {
            return
        }

        configuredInteractivePopGesture = gesture
        gesture.delegate = self
        gesture.isEnabled = true
    }

    private func bindReaderGesturesToInteractivePopIfNeeded() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer else {
            return
        }

        if let pageContainer = activeContainer as? ReaderPageContainer {
            pageContainer.prioritizeReturnGesture(gesture)
        } else if let scrollContainer = activeContainer as? ReaderScrollContainer {
            scrollContainer.prioritizeReturnGesture(gesture)
        }
    }

    private func deferNavigationBarHidingForAuxiliaryReturn() -> Bool {
        guard transitionCoordinator != nil,
              let navigationController,
              let readerStackController = navigationStackControllerForReader(),
              let topViewController = navigationController.topViewController
        else {
            return false
        }

        return topViewController !== readerStackController
    }

    private func scheduleNavigationBarHidingAfterAuxiliaryReturn() {
        guard let transitionCoordinator else {
            return
        }

        transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
            let shouldHideNavigationBar = !context.isCancelled
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.navigationController?.setNavigationBarHidden(
                    shouldHideNavigationBar,
                    animated: false
                )
            }
        }
    }

    private func pushReaderPage(
        _ viewController: UIViewController,
        prefersNavigationBarHidden: Bool = false
    ) {
        setMenuVisible(false, animated: true)
        stopAutoReading(animated: false)
        saveProgressImmediately()
        restoreReaderInteractivePopGesture()
        bindReaderGesturesToInteractivePopIfNeeded()

        guard let navigationController else {
            let presentedNavigationController = UINavigationController(rootViewController: viewController)
            presentedNavigationController.setNavigationBarHidden(
                prefersNavigationBarHidden,
                animated: false
            )
            present(presentedNavigationController, animated: true)
            return
        }

        navigationController.setNavigationBarHidden(
            prefersNavigationBarHidden,
            animated: false
        )
        navigationController.pushViewController(viewController, animated: true)
    }

    private func closeAuxiliaryReaderPage(
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        if let presentedViewController {
            presentedViewController.dismiss(animated: animated, completion: completion)
            return
        }

        if let navigationController,
           let readerStackController = navigationStackControllerForReader(),
           navigationController.topViewController !== readerStackController {
            navigationController.popToViewController(readerStackController, animated: animated)
            if animated,
               let coordinator = navigationController.transitionCoordinator {
                coordinator.animate(alongsideTransition: nil) { _ in
                    completion()
                }
            } else {
                completion()
            }
            return
        }

        if let presentedViewController = navigationController?.presentedViewController {
            presentedViewController.dismiss(animated: animated, completion: completion)
        } else {
            completion()
        }
    }

    private func navigationStackControllerForReader() -> UIViewController? {
        guard let navigationController else {
            return nil
        }

        var controller: UIViewController? = self
        while let current = controller {
            if navigationController.viewControllers.contains(where: { $0 === current }) {
                return current
            }
            controller = current.parent
        }

        return nil
    }

    private func toggleBookmark() {
        guard let progress = currentReadingProgress(),
              let currentPageModel,
              chapters.indices.contains(currentPageModel.chapterIndex) else {
            return
        }

        if let currentBookmark {
            removeBookmark(currentBookmark)
        } else {
            createBookmark(progress: progress, chapter: chapters[currentPageModel.chapterIndex])
        }
    }

    private func removeBookmark(_ bookmark: Bookmark) {
        let removedBookmarkIndex = bookmarks.firstIndex { $0.id == bookmark.id } ?? 0
        bookmarkTask?.cancel()
        currentBookmark = nil
        bookmarks.removeAll { $0.id == bookmark.id }
        menuView.setBookmarkButtonEnabled(false)
        updateBookmarkState()

        let repository = repository
        bookmarkTask = Task { [weak self] in
            do {
                try await repository.deleteBookmark(id: bookmark.id)
                await MainActor.run {
                    self?.menuView.setBookmarkButtonEnabled(true)
                    self?.updateBookmarkState()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.menuView.setBookmarkButtonEnabled(true)
                    self?.updateBookmarkState()
                }
            } catch {
                readerV2Logger.error("ReaderV2 delete bookmark failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarks.insert(
                        bookmark,
                        at: min(removedBookmarkIndex, self.bookmarks.count)
                    )
                    self.menuView.setBookmarkButtonEnabled(true)
                    self.updateBookmarkState()
                    self.showError(error)
                }
            }
        }
    }

    private func createBookmark(
        progress: ReadingProgress,
        chapter: Chapter
    ) {
        bookmarkTask?.cancel()
        menuView.setBookmarkButtonEnabled(false)

        let repository = repository
        let bookID = book.id
        let offset = Int(progress.chapterOffset)
        let preview = bookmarkPreview()
        bookmarkTask = Task { [weak self] in
            do {
                let bookmark = try await repository.createBookmark(
                    bookID: bookID,
                    chapterID: chapter.id,
                    offset: offset,
                    preview: preview
                )
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.menuView.setBookmarkButtonEnabled(true)
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarks.insert(bookmark, at: 0)
                    self.updateBookmarkState()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.menuView.setBookmarkButtonEnabled(true)
                }
            } catch {
                readerV2Logger.error("ReaderV2 create bookmark failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.menuView.setBookmarkButtonEnabled(true)
                    self.updateBookmarkState()
                    self.showError(error)
                }
            }
        }
    }

    private func setMenuVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        menuView.setMenuVisible(visible, animated: animated)
        if !visible {
            setSettingsPanelVisible(false, animated: animated)
        }
        updateSystemAppearance()
    }

    private func setSettingsPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        if visible {
            menuView.setMenuVisible(true, animated: animated)
            setAutoReadPanelVisible(false, animated: animated)
        }
        settingsPanelView.setPanelVisible(visible, animated: animated)
        updateSystemAppearance()
    }

    private func showSettingsPanelFromReaderMenu() {
        menuView.setBarsVisible(
            top: false,
            bottom: false,
            floatingActions: false,
            animated: true
        )
        setAutoReadPanelVisible(false, animated: true)
        settingsPanelView.setPanelVisible(true, animated: true)
        updateSystemAppearance()
    }

    private func setAutoReadPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        if visible {
            menuView.setMenuVisible(false, animated: animated)
            settingsPanelView.setPanelVisible(false, animated: animated)
        }
        autoReadPanelView.setPanelVisible(visible, animated: animated)
        updateSystemAppearance()
    }

    private func closeReaderMenuOverlays(animated: Bool) {
        guard menuView.isMenuVisible || settingsPanelView.isPanelVisible else {
            return
        }
        setMenuVisible(false, animated: animated)
    }

    private func autoReadButtonTapped() {
        if autoReadController.isReading {
            setAutoReadPanelVisible(!autoReadPanelView.isPanelVisible, animated: true)
            return
        }
        requestStartAutoReading()
    }

    private func requestStartAutoReading() {
        setMenuVisible(false, animated: true)
        setSettingsPanelVisible(false, animated: true)
        autoReadEntryPageMode = readerSettings.normalized.pageMode
        guard activeTurnPageType == .verticalContinuous else {
            shouldStartAutoReadAfterOpen = true
            var settings = readerSettings
            settings.pageMode = .scroll
            applyReaderSettings(settings)
            return
        }
        startAutoReadingIfPossible(showsPanel: false)
    }

    private func startAutoReadingIfPossible(showsPanel: Bool = false) {
        guard let scrollContainer = activeContainer as? ReaderScrollContainer else {
            shouldStartAutoReadAfterOpen = true
            return
        }
        if let currentPageModel {
            ensureScrollChapterLoaded(currentPageModel.chapterIndex)
        }
        let preservesScrollPosition = scrollContainer.tableView.numberOfSections > 0
        scrollContainer.reload(
            sections: scrollSections(),
            layout: layout,
            theme: theme,
            widgetVisibility: readerSettings.normalized.widgetVisibility,
            preservesVisualPosition: preservesScrollPosition
        )
        autoReadPanelView.setSpeed(readerSettings.normalized.autoReadSpeed)
        autoReadController.start(
            scrollView: scrollContainer.tableView,
            speed: readerSettings.normalized.autoReadSpeed
        )
        setAutoReadPanelVisible(showsPanel, animated: showsPanel)
        updateMenuState()
        updateSystemAppearance()
    }

    private func stopAutoReading(
        animated: Bool,
        restoresEntryPageMode: Bool = true
    ) {
        guard autoReadController.isReading
            || autoReadController.hasDisplayLink
            || autoReadPanelView.isPanelVisible
            || shouldStartAutoReadAfterOpen
            || autoReadEntryPageMode != nil else {
            return
        }
        finishAutoReading(
            animated: animated,
            restoresEntryPageMode: restoresEntryPageMode
        )
    }

    private func finishAutoReading(
        animated: Bool,
        restoresEntryPageMode: Bool = true
    ) {
        shouldStartAutoReadAfterOpen = false
        let entryPageMode = autoReadEntryPageMode
        autoReadEntryPageMode = nil
        autoReadController.stop()
        setAutoReadPanelVisible(false, animated: animated)
        updateMenuState()
        updateSystemAppearance()
        saveProgressImmediately()
        if restoresEntryPageMode,
           let entryPageMode,
           readerSettings.normalized.pageMode != entryPageMode {
            var settings = readerSettings
            settings.pageMode = entryPageMode
            applyReaderSettings(settings)
        }
    }

    private func pauseAutoReadingForBackground() {
        guard autoReadController.isReading else {
            return
        }
        autoReadController.pauseForBackground()
        setAutoReadPanelVisible(false, animated: false)
        updateMenuState()
        updateSystemAppearance()
    }

    private func resumeAutoReadingAfterPauseIfNeeded() {
        guard let scrollContainer = activeContainer as? ReaderScrollContainer else {
            return
        }
        autoReadController.resumeAfterBackgroundIfNeeded(scrollView: scrollContainer.tableView)
        updateMenuState()
        updateSystemAppearance()
    }

    private func autoReadSpeedChanged(_ speed: Double) {
        var settings = readerSettings
        settings.autoReadSpeed = speed
        readerSettings = settings.normalized
        autoReadController.updateSpeed(readerSettings.autoReadSpeed)
        autoReadPanelView.setSpeed(readerSettings.autoReadSpeed)
        settingsPanelView.setSettings(readerSettings)
    }

    private func autoReadSpeedChangeFinished(_ speed: Double) {
        autoReadSpeedChanged(speed)
        saveReaderSettings(readerSettings)
    }

    private func autoReadDidScroll() {
        guard let scrollContainer = activeContainer as? ReaderScrollContainer else {
            return
        }
        scrollContainer.maybeLoadMoreForAutoRead()
        scrollContainer.notifyVisiblePageFromAutoRead()
    }

    private func autoReadReachedLoadedContentEnd() -> Bool {
        guard let currentPageModel else {
            finishAutoReading(animated: true)
            return false
        }
        let nextChapterIndex = (loadedScrollChapterIndexes.last ?? currentPageModel.chapterIndex) + 1
        if chapters.indices.contains(nextChapterIndex) {
            return loadNextScrollChapterIfNeeded(resumesAutoReadAfterLoad: true)
        }
        finishAutoReading(animated: true)
        return false
    }

    @objc private func applicationDidEnterBackground() {
        pauseAutoReadingForBackground()
        updateSystemAppearance()
    }

    @objc private func applicationDidBecomeActive() {
        guard isViewVisible else {
            return
        }
        resumeAutoReadingAfterPauseIfNeeded()
        updateSystemAppearance()
    }

    @objc private func pageTapGestureRecognized(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        let location = recognizer.location(in: view)
        if autoReadPanelView.isPanelVisible {
            if !autoReadPanelView.frame.contains(location) {
                setAutoReadPanelVisible(false, animated: true)
            }
            return
        }

        if autoReadController.isReading {
            setAutoReadPanelVisible(true, animated: true)
            return
        }

        if menuView.isMenuVisible || settingsPanelView.isPanelVisible {
            closeReaderMenuOverlays(animated: true)
            return
        }

        handleReadingAreaTapAction(tapAction(at: location))
    }

    private func handleReadingAreaTapAction(_ action: ReaderSettings.TouchAreaAction) {
        switch action {
        case .previousPage:
            menuView.setMoreMenuVisible(false, animated: true)
            goToAdjacentPage(delta: -1, animated: false)
        case .menu:
            setMenuVisible(!menuView.isMenuVisible, animated: true)
        case .nextPage:
            menuView.setMoreMenuVisible(false, animated: true)
            goToAdjacentPage(delta: 1, animated: false)
        case .none:
            break
        }
    }

    private func tapAction(at location: CGPoint) -> ReaderSettings.TouchAreaAction {
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        let column = min(max(Int(location.x / (width / 3)), 0), 2)
        let row = min(max(Int(location.y / (height / 3)), 0), 2)
        let index = row * 3 + column
        let map = readerSettings.normalized.touchAreaMap
        guard map.indices.contains(index) else {
            return ReaderSettings.default.touchAreaMap[index]
        }
        return map[index]
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let interactivePopGesture = configuredInteractivePopGesture,
           gestureRecognizer === interactivePopGesture {
            guard let navigationController,
                  navigationController.viewControllers.count > 1 else {
                return false
            }

            if let readerStackController = navigationStackControllerForReader(),
               navigationController.topViewController !== readerStackController {
                return true
            }

            return readerSettings.normalized.edgeSwipeBackEnabled
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        if let interactivePopGesture = configuredInteractivePopGesture,
           gestureRecognizer === interactivePopGesture {
            return true
        }

        var touchedView = touch.view
        while let currentView = touchedView {
            if currentView is UIControl {
                return false
            }
            if let textReadView = currentView as? TextReadView,
               textReadView.isSelectionActive {
                textReadView.clearSelection()
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    private func goToChapter(delta: Int) {
        guard let currentPageModel else {
            return
        }
        let targetChapterIndex = currentPageModel.chapterIndex + delta
        guard chapters.indices.contains(targetChapterIndex) else {
            return
        }
        let record = ReaderRecord(
            chapterIndex: targetChapterIndex,
            progress: 0,
            chapterTitle: chapterTitle(at: targetChapterIndex)
        )
        menuView.setBarsVisible(
            top: false,
            bottom: true,
            floatingActions: false,
            animated: true
        )
        open(
            record: record,
            animated: false,
            showsLoading: false,
            closesMenuOnSuccess: false
        )
    }

    private func openProgressInCurrentChapter(_ progress: Double) {
        guard let currentPageModel else {
            return
        }
        stopAutoReading(animated: false)
        let record = ReaderRecord(
            chapterIndex: currentPageModel.chapterIndex,
            progress: ReaderPageModel.clampedProgress(progress),
            chapterTitle: chapterTitle(at: currentPageModel.chapterIndex)
        )
        open(record: record, animated: false)
    }

    private func toggleDarkMode() {
        var settings = readerSettings
        settings.theme = settings.theme == .dark ? .white : .dark
        applyReaderSettings(settings)
    }

    private func goToAdjacentPage(
        delta: Int,
        animated: Bool
    ) {
        let direction: ReaderPageTurnDirection = delta > 0 ? .forward : .reverse
        openTask?.cancel()
        openTask = Task { [weak self] in
            do {
                guard let self,
                      let target = try await self.loadAdjacentPageModel(delta: delta) else {
                    return
                }
                try self.display(
                    pageModel: target,
                    direction: direction,
                    animated: animated,
                    savesProgress: true,
                    recordsOpenHistory: false
                )
                self.closeReaderMenuOverlays(animated: true)
            } catch is CancellationError {
            } catch {
                self?.showError(error)
            }
        }
    }

    private func closeReader() {
        stopAutoReading(animated: false, restoresEntryPageMode: false)
        saveProgressImmediately()
        onClose()
    }

    private func pageTurnCompleted(to pageModel: ReaderPageModel) {
        if !autoReadController.isReading {
            closeReaderMenuOverlays(animated: true)
        }
        currentPageModel = pageModel
        updateMenuState()
        if activeTurnPageType == .verticalContinuous {
            ensureScrollChapterLoaded(pageModel.chapterIndex)
            loadNextScrollChapterIfNeeded()
        } else {
            preloadAround(chapterIndex: pageModel.chapterIndex)
        }
        saveProgress(
            for: pageModel,
            immediately: false,
            recordsOpenHistory: false
        )
    }
}
