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
final class ReaderV2ViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let fileStore: AppFileStore
    private let repository: any LibraryRepository
    private let onClose: () -> Void
    private let onStatusBarHiddenChange: (Bool) -> Void

    private let closeButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var pageViewController: UIPageViewController?
    private var activeTurnPageType: ReaderTurnPageType = .horizontalScroll
    private var book: Book
    private var chapters: [Chapter] = []
    private var chapterProvider: ReaderChapterProvider?
    private var progressBridge: ReaderProgressBridge?
    private var readerSettings = ReaderSettings.default
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
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
        configurePageViewController(for: activeTurnPageType)
        configureCloseButton()
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
        resetReaderState()
        startInitialLoad()
    }

    private func configurePageViewController(for turnPageType: ReaderTurnPageType) {
        let effectiveType: ReaderTurnPageType = turnPageType == .pageCurl ? .pageCurl : .horizontalScroll
        guard pageViewController == nil || activeTurnPageType != effectiveType else {
            return
        }

        if let pageViewController {
            pageViewController.willMove(toParent: nil)
            pageViewController.view.removeFromSuperview()
            pageViewController.removeFromParent()
        }

        let transitionStyle: UIPageViewController.TransitionStyle = effectiveType == .pageCurl ? .pageCurl : .scroll
        let controller = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal
        )
        controller.dataSource = self
        controller.delegate = self
        controller.isDoubleSided = effectiveType == .pageCurl
        controller.view.backgroundColor = theme.backgroundColor

        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(controller.view, at: 0)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)

        pageViewController = controller
        activeTurnPageType = effectiveType
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = theme.headerColor
        closeButton.backgroundColor = theme.backgroundColor.withAlphaComponent(0.72)
        closeButton.layer.cornerRadius = 20
        closeButton.accessibilityLabel = NSLocalizedString("common.close", comment: "")
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40)
        ])
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
        layout = Self.layout(from: readerSettings)
        theme = Self.theme(from: readerSettings)
        view.backgroundColor = theme.backgroundColor
        closeButton.tintColor = theme.headerColor
        closeButton.backgroundColor = theme.backgroundColor.withAlphaComponent(0.72)
        pageViewController?.view.backgroundColor = theme.backgroundColor
        paginationCache.removeAll()
        configurePageViewController(for: Self.turnPageType(from: readerSettings))
        updateSystemAppearance()

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
            returnsHeights: false
        )
        paginationCache[index] = result
        return result
    }

    private func display(
        pageModel: ReaderPageModel,
        direction: UIPageViewController.NavigationDirection,
        animated: Bool,
        savesProgress: Bool,
        recordsOpenHistory: Bool
    ) throws {
        guard let pageViewController,
              let pageController = makePageViewController(for: pageModel) else {
            throw ReaderV2Error.pageUnavailable
        }
        pageViewController.setViewControllers(
            [pageController],
            direction: direction,
            animated: animated
        )
        currentPageModel = pageModel
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

    @objc private func pageTapGestureRecognized(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        let location = recognizer.location(in: view)
        if location.x < view.bounds.width / 3 {
            goToAdjacentPage(delta: -1)
        } else if location.x > view.bounds.width * 2 / 3 {
            goToAdjacentPage(delta: 1)
        }
    }

    private func goToAdjacentPage(delta: Int) {
        let direction: UIPageViewController.NavigationDirection = delta > 0 ? .forward : .reverse
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

    @objc private func closeButtonTapped() {
        saveProgressImmediately()
        onClose()
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController,
              let pageModel = pageController.pageModel,
              let previous = adjacentPageModel(from: pageModel, delta: -1) else {
            return nil
        }
        return makePageViewController(for: previous)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController,
              let pageModel = pageController.pageModel,
              let next = adjacentPageModel(from: pageModel, delta: 1) else {
            return nil
        }
        return makePageViewController(for: next)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let pageController = pageViewController.viewControllers?.first as? ReaderPageViewController,
              let pageModel = pageController.pageModel else {
            return
        }
        currentPageModel = pageModel
        preloadAround(chapterIndex: pageModel.chapterIndex)
        saveProgress(
            for: pageModel,
            immediately: false,
            recordsOpenHistory: false
        )
    }

    private static func turnPageType(from settings: ReaderSettings) -> ReaderTurnPageType {
        switch settings.normalized.pageMode {
        case .paged:
            return .horizontalScroll
        case .curl:
            return .pageCurl
        case .scroll:
            return .verticalContinuous
        }
    }

    private static func layout(from settings: ReaderSettings) -> ReaderLayout {
        let normalized = settings.normalized
        let values: ReaderSettings.LayoutValues
        if normalized.layoutPreset == .custom {
            values = normalized.customLayoutValues?.normalized ?? .standard
        } else {
            switch normalized.layoutPreset {
            case .compact:
                values = .compact
            case .standard:
                values = .standard
            case .relaxed:
                values = .relaxed
            case .custom:
                values = .standard
            }
        }

        return ReaderLayout(
            topMargin: CGFloat(values.bodyTopMargin),
            bottomMargin: CGFloat(values.bodyBottomMargin),
            leftMargin: CGFloat(values.bodyLeftMargin),
            rightMargin: CGFloat(values.bodyRightMargin),
            lineSpacing: CGFloat(values.bodyLineSpacing),
            paragraphSpacing: CGFloat(values.bodyParagraphSpacing),
            wordSpacing: CGFloat(values.bodyKern),
            headIndent: CGFloat(values.firstLineIndentEms),
            fontSize: CGFloat(normalized.fontSize),
            fontWeight: CGFloat(values.bodyFontWeightValue),
            titleFontWeight: CGFloat(values.titleFontWeightValue),
            titleFontSizeOffset: CGFloat(values.titleFontSizeDelta),
            titleLineSpacing: CGFloat(values.titleLineSpacing),
            titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
            titleWordSpacing: CGFloat(values.titleKern)
        )
    }

    private static func theme(from settings: ReaderSettings) -> ReaderTheme {
        switch settings.normalized.theme {
        case .white:
            return .standard
        case .eyeCare:
            return ReaderTheme(
                contentColor: UIColor(red: 0.11, green: 0.18, blue: 0.12, alpha: 1),
                headerColor: .secondaryLabel,
                backgroundColor: UIColor(red: 0.92, green: 0.97, blue: 0.90, alpha: 1),
                backgroundImageName: nil,
                backgroundImageStyle: nil
            )
        case .paper:
            return ReaderTheme(
                contentColor: UIColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 1),
                headerColor: .secondaryLabel,
                backgroundColor: UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1),
                backgroundImageName: nil,
                backgroundImageStyle: nil
            )
        case .dark:
            return .dark
        }
    }
}

private extension ReaderTheme {
    var isDark: Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if backgroundColor.getWhite(&white, alpha: &alpha) {
            return white < 0.5
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if backgroundColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return ((red * 0.299) + (green * 0.587) + (blue * 0.114)) < 0.5
        }
        return false
    }
}
