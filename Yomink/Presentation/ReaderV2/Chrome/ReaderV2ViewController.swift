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
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var activeContainer: ReaderContainerProtocol?
    private var activeTurnPageType: ReaderTurnPageType = .horizontalScroll
    private var book: Book
    private var chapters: [Chapter] = []
    private var chapterProvider: ReaderChapterProvider?
    private var progressBridge: ReaderProgressBridge?
    private var readerSettings = ReaderSettings.default
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var chromeTheme = ReaderChromeTheme.standard
    private var paginationCache: [Int: ReaderDivisionResult] = [:]
    private var currentPageModel: ReaderPageModel?
    private var pendingInitialRecord: ReaderRecord?
    private var lastPaginationSize = CGSize.zero
    private var isViewVisible = false
    private var lastNotifiedStatusBarHidden = false
    private var didRecordOpenHistory = false
    private var openedAt = Date()

    private var loadGeneration = 0
    private var openGeneration = 0
    private var saveGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
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
        preloadTasks.values.forEach { $0.cancel() }
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    override var prefersStatusBarHidden: Bool {
        guard isViewVisible,
              readerSettings.normalized.autoHideStatusBar,
              UIDevice.current.userInterfaceIdiom != .pad,
              view.window?.bounds == UIScreen.main.bounds
        else {
            return false
        }
        return true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        theme.isDark ? .lightContent : .darkContent
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .slide
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        readerSettings.normalized.autoHideHomeIndicator
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        readerSettings.normalized.autoHideHomeIndicator ? .bottom : []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.backgroundColor
        configureContainer(for: activeTurnPageType)
        configureMenu()
        configureSettingsPanel()
        configureLoadingIndicator()
        configureTapGesture()
        startInitialLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isViewVisible = true
        navigationController?.setNavigationBarHidden(true, animated: animated)
        UIApplication.shared.isIdleTimerDisabled = readerSettings.normalized.keepScreenAwake
        updateSystemAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reopenIfPaginationSizeChanged()
        openPendingInitialRecordIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        UIApplication.shared.isIdleTimerDisabled = false
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
        menuView.onSettings = { [weak self] in
            self?.setSettingsPanelVisible(true, animated: true)
        }
        menuView.onPreviousPage = { [weak self] in
            self?.setMenuVisible(false, animated: true)
            self?.goToAdjacentPage(delta: -1)
        }
        menuView.onNextPage = { [weak self] in
            self?.setMenuVisible(false, animated: true)
            self?.goToAdjacentPage(delta: 1)
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
        let panelHeight = settingsPanelView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.58)
        panelHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            settingsPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsPanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panelHeight,
            settingsPanelView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.64),
            settingsPanelView.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
        settingsPanelView.setSettings(readerSettings)
        settingsPanelView.apply(chromeTheme: chromeTheme)
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
        UIApplication.shared.isIdleTimerDisabled = isViewVisible && readerSettings.normalized.keepScreenAwake
    }

    private func applyReaderSettings(_ nextSettings: ReaderSettings) {
        let previousSettings = readerSettings
        let normalizedSettings = nextSettings.normalized
        guard normalizedSettings != previousSettings else {
            return
        }

        readerSettings = normalizedSettings
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
            return
        }
        openTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
        paginationCache.removeAll()
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
                let loadedChapters = try await chapters
                let loadedProgress = try await progress
                let loadedSettings = try await settings
                try Task.checkCancellation()

                guard let self,
                      self.loadGeneration == generation else {
                    return
                }
                self.finishInitialLoad(
                    chapters: loadedChapters,
                    progress: loadedProgress,
                    settings: loadedSettings
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
        settings: ReaderSettings
    ) {
        guard chapters.isEmpty == false else {
            showLoading(false)
            showError(ReaderV2Error.emptyBook)
            return
        }

        self.chapters = chapters
        readerSettings = settings.normalized
        refreshSettingsProjection()
        paginationCache.removeAll()
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
        pendingInitialRecord = adapter.progressBridge.record(from: progress)
        openPendingInitialRecordIfPossible()
    }

    private func resetReaderState() {
        loadTask?.cancel()
        openTask?.cancel()
        saveTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
        chapters = []
        chapterProvider = nil
        progressBridge = nil
        paginationCache.removeAll()
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
        animated: Bool
    ) {
        openGeneration += 1
        let generation = openGeneration
        showLoading(true)
        openTask?.cancel()
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
                self.showLoading(false)
            } catch is CancellationError {
            } catch {
                guard let self,
                      self.openGeneration == generation else {
                    return
                }
                self.showLoading(false)
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

        let text = try await chapterProvider.textAsync(forChapterAt: index)
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
            scrollContainer.reload(
                sections: scrollSections(),
                layout: layout,
                theme: theme
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
        preloadAround(chapterIndex: pageModel.chapterIndex)
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
        controller.configure(
            page: result.pages[pageModel.pageIndex],
            pageModel: pageModel,
            layout: layout,
            theme: theme
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
        paginationCache.keys.sorted().compactMap { chapterIndex in
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
                pageModels: pageModels
            )
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
                    if let scrollContainer = self.activeContainer as? ReaderScrollContainer {
                        scrollContainer.reload(
                            sections: self.scrollSections(),
                            layout: self.layout,
                            theme: self.theme
                        )
                    }
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
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        let isHidden = prefersStatusBarHidden
        guard isHidden != lastNotifiedStatusBarHidden else {
            return
        }
        lastNotifiedStatusBarHidden = isHidden
        onStatusBarHiddenChange(isHidden)
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
        menuView.update(
            pageModel: pageModel,
            chapterTitle: pageModel.map { chapterTitle(at: $0.chapterIndex) } ?? "",
            turnPageType: activeTurnPageType
        )
    }

    private func setMenuVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        menuView.setMenuVisible(visible, animated: animated)
        if !visible {
            setSettingsPanelVisible(false, animated: animated)
        }
    }

    private func setSettingsPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        if visible {
            menuView.setMenuVisible(true, animated: animated)
        }
        settingsPanelView.setPanelVisible(visible, animated: animated)
    }

    @objc private func pageTapGestureRecognized(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        let location = recognizer.location(in: view)
        if settingsPanelView.isPanelVisible {
            if !settingsPanelView.frame.contains(location) {
                setSettingsPanelVisible(false, animated: true)
            }
            return
        }

        if menuView.isMenuVisible {
            if !menuView.containsInteractiveContent(at: location) {
                setMenuVisible(false, animated: true)
            }
            return
        }

        if location.x < view.bounds.width / 3 {
            goToAdjacentPage(delta: -1)
        } else if location.x > view.bounds.width * 2 / 3 {
            goToAdjacentPage(delta: 1)
        } else {
            setMenuVisible(true, animated: true)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView {
            if currentView is UIControl {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    private func goToAdjacentPage(delta: Int) {
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
                    animated: true,
                    savesProgress: true,
                    recordsOpenHistory: false
                )
            } catch is CancellationError {
            } catch {
                self?.showError(error)
            }
        }
    }

    private func closeReader() {
        saveProgressImmediately()
        onClose()
    }

    private func pageTurnCompleted(to pageModel: ReaderPageModel) {
        currentPageModel = pageModel
        updateMenuState()
        preloadAround(chapterIndex: pageModel.chapterIndex)
        saveProgress(
            for: pageModel,
            immediately: false,
            recordsOpenHistory: false
        )
    }
}
