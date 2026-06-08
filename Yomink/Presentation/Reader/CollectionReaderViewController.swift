import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

let readerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
    category: "Reader"
)

final class ReaderSettingsPanelScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }
}

@MainActor
final class CollectionReaderViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    private enum Section {
        case main
    }

    let fileStore: AppFileStore
    let repository: any LibraryRepository
    private let onClose: () -> Void
    let onStatusBarHiddenChange: (Bool) -> Void
    let collectionView: UICollectionView
    let verticalTopCoverView = UIView()
    let verticalBottomCoverView = UIView()
    let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    let titleLabel = UILabel()
    let bookmarkButton = UIButton(type: .system)
    let moreButton = UIButton(type: .system)
    let moreMenuContainer = UIView()
    let moreMenuStack = UIStackView()
    let progressLabel = UILabel()
    let progressSlider = ReaderProgressSlider()
    let progressTooltipView = UIView()
    let progressTooltipLabel = UILabel()
    let previousChapterButton = UIButton(type: .system)
    let nextChapterButton = UIButton(type: .system)
    let catalogButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let floatingActionStack = UIStackView()
    let autoReadButton = UIButton(type: .system)
    let darkModeButton = UIButton(type: .system)
    let autoReadPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    let autoReadSpeedSlider = UISlider()
    let autoReadExitButton = UIButton(type: .system)
    let settingsPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    let settingsPanelScrollView = ReaderSettingsPanelScrollView()
    let settingsPanelStack = UIStackView()
    let settingsFontDecreaseButton = UIButton(type: .system)
    let settingsFontValueButton = UIButton(type: .system)
    let settingsFontIncreaseButton = UIButton(type: .system)
    var layoutValueLabels: [LayoutAdjustment: UILabel] = [:]
    let fixedWidgetOverlay = ReaderPageWidgetOverlayView()
    let widgetChapterTitleSwitch = UISwitch()
    let widgetBatteryPercentageSwitch = UISwitch()
    let widgetBatteryIconSwitch = UISwitch()
    let widgetTimeSwitch = UISwitch()
    let widgetChapterPageProgressSwitch = UISwitch()
    let widgetGlobalProgressSwitch = UISwitch()
    var settingsControlPanRecognizers: [UIPanGestureRecognizer] = []
    var settingsControlDragLastY: CGFloat = 0
    let keepScreenAwakeSwitch = UISwitch()
    let autoHideHomeIndicatorSwitch = UISwitch()
    let autoHideStatusBarSwitch = UISwitch()
    let edgeSwipeBackSwitch = UISwitch()
    lazy var settingsPageModeControl = UISegmentedControl(
        items: [
            NSLocalizedString("reader.settings.pageTurn.slide", comment: ""),
            NSLocalizedString("reader.settings.pageTurn.curl", comment: ""),
            NSLocalizedString("reader.settings.pageTurn.scroll", comment: "")
        ]
    )
    lazy var settingsThemeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.localizedTitle)
    )
    lazy var settingsLayoutPresetControl = UISegmentedControl(
        items: ReaderSettings.LayoutPreset.allCases.map(\.localizedTitle)
    )
    lazy var settingsQuickControl = UISegmentedControl(
        items: [
            NSLocalizedString("reader.settings.quick.page", comment: ""),
            NSLocalizedString("reader.settings.quick.layout", comment: ""),
            NSLocalizedString("reader.settings.quick.more", comment: "")
        ]
    )
    let loadingIndicator = UIActivityIndicatorView(style: .large)
    let textSelectionOverlay = ReaderTextSelectionOverlayView()

    enum Layout {
        static let topBarContentHeight: CGFloat = 46
        static let topBarButtonBottomInset: CGFloat = 5
        static let bottomBarTopInset: CGFloat = 0
        static let bottomBarSafeAreaInset: CGFloat = 2
        static let progressRowHeight: CGFloat = 46
        static let bottomActionRowHeight: CGFloat = 48
        static let chapterButtonWidth: CGFloat = 74
        static let progressSliderHorizontalInset: CGFloat = 18
        static let progressTooltipBottomSpacing: CGFloat = 20
        static let progressTooltipHorizontalPadding: CGFloat = 12
        static let progressTooltipVerticalPadding: CGFloat = 6
        static let progressTooltipWidth: CGFloat = 140
        static let progressThumbHitboxDiameter: CGFloat = 44
        static let floatingButtonSize: CGFloat = 42
        static let floatingButtonSpacing: CGFloat = 16
        static let floatingButtonTrailingInset: CGFloat = 18
        static let floatingButtonBottomInset: CGFloat = 20
        static let moreMenuWidth: CGFloat = 188
        static let moreMenuRowHeight: CGFloat = 46
        static let moreMenuTopSpacing: CGFloat = 6
        static let moreMenuTrailingInset: CGFloat = 12
        static let moreMenuCornerRadius: CGFloat = 8
        static let moreMenuHorizontalInset: CGFloat = 18
        static let settingsPanelContentHeight: CGFloat = 315
        static let settingsPanelHorizontalInset: CGFloat = 20
        static let settingsPanelTopInset: CGFloat = 22
        static let settingsControlHeight: CGFloat = 34
        static let settingsFontButtonHeight: CGFloat = 32
        static let menuSeparatorThickness: CGFloat = 2
        static let autoReadPanelHeight: CGFloat = 190
        static let autoReadPanelHorizontalInset: CGFloat = 22
        static let autoReadPanelTopInset: CGFloat = 28
        static let autoReadPanelBottomInset: CGFloat = 18
        static let autoReadIconSize: CGFloat = 24
        static let autoReadExitButtonHeight: CGFloat = 42
        static let maximumResidentPages = 14
        static let horizontalPrefetchDistance = 4
    }

    static let widgetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: "Hm",
            options: 0,
            locale: .current
        )
        return formatter
    }()

    enum MenuStyle {
        static let barBackgroundColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let progressRowBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
        static let separatorColor = UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
        static let separatorEdgeColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        static let primaryTextColor = UIColor(white: 0.82, alpha: 1)
        static let secondaryTextColor = UIColor(white: 0.58, alpha: 1)
        static let progressTintColor = UIColor(red: 0.68, green: 0.17, blue: 0.14, alpha: 1)
        static let progressTrackColor = UIColor(red: 0.26, green: 0.26, blue: 0.26, alpha: 1)
        static let progressThumbColor = UIColor(red: 0.353, green: 0.353, blue: 0.365, alpha: 1)
        static let progressThumbBorderColor = UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)
        static let progressThumbEdgeShadowColor = UIColor.black.withAlphaComponent(0.18)
        static let progressTooltipBackgroundColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
        static let settingsControlBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
        static let settingsControlSelectedColor = UIColor(red: 0.314, green: 0.314, blue: 0.314, alpha: 1)
        static let floatingButtonColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let floatingButtonIconColor = UIColor(white: 0.48, alpha: 1)
    }

    var book: Book
    var chapters: [Chapter] = []
    var bookmarks: [Bookmark] = []
    var filterRules: [TextFilterRule] = []
    var pages: [CollectionReaderPage] = []
    var currentPage: CollectionReaderPage?
    var currentProgress: ReadingProgress?
    var currentBookmark: Bookmark?
    var readerSettings = ReaderSettings.default
    var settingsQuickMode: SettingsQuickMode = .page
    private var loadTask: Task<Void, Never>?
    var pageTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?
    var settingsSaveTask: Task<Void, Never>?
    var bookmarkTask: Task<Void, Never>?
    var openHistoryTask: Task<Void, Never>?
    var pagingGeneration = 0
    var saveGeneration = 0
    var settingsSaveGeneration = 0
    var openHistoryGeneration = 0
    var didRecordOpenHistory = false
    var openedAt = Date()
    var didShowProgressSaveError = false
    var didShowSettingsSaveError = false
    // 拖动 / paging 减速期间,把"头部 prepend"暂存到这里,等 scrollView 静止后再提交。
    // 尾部 append 直接走 insertItems 立即提交(不平移 contentOffset、不改已有 cell 的 indexPath),
    // 这样滑动期间 pages 可以持续增长,不会撞到 contentSize 边界翻不动。
    // 头部修剪(trimResidentPagesIfNeeded)在 defer 窗口里被跳过,由 flush 统一补做。
    var pendingPagePrepends: [CollectionReaderPage] = []
    var isMenuVisible = false
    var isMoreMenuVisible = false
    var isSettingsPanelVisible = false
    var isAutoReading = false
    var isAutoReadingPausedForBackground = false
    var isAutoReadingPausedForInteractiveReturn = false
    var isAutoReadPanelVisible = false
    var isTrackingProgressSlider = false
    var isApplyingProgrammaticScroll = false
    var didStartOpening = false
    var didReachEndOfBook = false
    var isLoadingNextPage = false
    var pendingTapTargetPageIndex: Int?
    var pendingRestoreAbsoluteOffset: Int?
    private var previousBatteryMonitoringEnabled = false
    var autoReadDisplayLink: CADisplayLink?
    var lastAutoReadTimestamp: CFTimeInterval?
    var lastAutoReadProgressUpdateTimestamp: CFTimeInterval = 0
    var autoReadVelocity: CGFloat = 0
    var shouldSuppressNextAutoReadTap = false
    var shouldSuppressNextTapForTextSelection = false
    weak var autoReadTouchResetGesture: UIGestureRecognizer?
    weak var moreMenuDismissTapGesture: UIGestureRecognizer?
    weak var textSelectionLongPressGesture: UILongPressGestureRecognizer?
    private weak var edgeBackGesture: UIScreenEdgePanGestureRecognizer?
    private weak var configuredInteractivePopGesture: UIGestureRecognizer?
    static let autoReadForwardInertiaDecayConstant: CGFloat = 2.5
    static let autoReadReverseInertiaDecayConstant: CGFloat = 2.5
    var lastPagingLayoutSnapshot: PagingLayoutSnapshot?
    var stableHorizontalPagingLayoutSnapshot: PagingLayoutSnapshot?
    weak var settingsPageModeSection: UIView?
    weak var settingsLayoutSection: UIView?
    weak var settingsMoreSection: UIView?

    var usesVerticalScrolling: Bool {
        isAutoReading || readerSettings.pageMode == .scroll
    }

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
        self.onStatusBarHiddenChange = onStatusBarHiddenChange

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let shouldRestoreBatteryMonitoring = previousBatteryMonitoringEnabled
        onStatusBarHiddenChange(false)
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.isBatteryMonitoringEnabled = shouldRestoreBatteryMonitoring
        }
        NotificationCenter.default.removeObserver(self)
        loadTask?.cancel()
        pageTask?.cancel()
        saveTask?.cancel()
        settingsSaveTask?.cancel()
        bookmarkTask?.cancel()
        openHistoryTask?.cancel()
        autoReadDisplayLink?.invalidate()
        autoReadDisplayLink = nil
        UIMenuController.shared.setMenuVisible(false, animated: false)
    }

    override var prefersStatusBarHidden: Bool {
        shouldHideSystemStatusBar
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        readerSettings.theme == .dark ? .lightContent : .darkContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        // 始终返回 false: 我们要的不是隐藏小横条,而是让它进入灰色"未唤醒"状态。
        // 真正的灰色效果由 preferredScreenEdgesDeferringSystemGestures = .bottom 提供。
        false
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        readerSettings.autoHideHomeIndicator ? .bottom : []
    }

    var shouldHideSystemStatusBar: Bool {
        if isAutoReading {
            return true
        }
        guard readerSettings.autoHideStatusBar else {
            return false
        }
        if isMenuVisible,
           !isSettingsPanelVisible,
           !isAutoReadPanelVisible {
            return false
        }
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        previousBatteryMonitoringEnabled = UIDevice.current.isBatteryMonitoringEnabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        configureCollectionView()
        configureVerticalContentCovers()
        configureFixedWidgetOverlay()
        configureTextSelection()
        configureMenus()
        configureLoadingIndicator()
        configureGestures()
        configureLifecycleObservers()
        applyTheme()
        startInitialLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 二次扫描 hosting controller 子类: App 启动时部分 SwiftUI hosting
        // controller 还未实例化,这里兜底覆盖在 reader 显示前才生成的新泛型类。
        HostingControllerHomeIndicatorBridge.ensureInstalledForCurrentlyRegisteredClasses()
        refreshHomeIndicatorDeferralPreferencesOnNextRunLoop()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        HostingControllerHomeIndicatorBridge.ensureInstalledForCurrentlyRegisteredClasses()
        refreshHomeIndicatorDeferralPreferences()
        navigationController?.setNavigationBarHidden(true, animated: animated)
        restoreNativeInteractivePopGesture()
        bindReaderGesturesToEdgeBackIfNeeded()
        updateReaderChromePreferences()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyMenuPosition(animated: false)
        applySettingsPanelPosition(animated: false)
        applyAutoReadPanelPosition()
        updateVerticalContentCovers()

        guard didStartOpening,
              isReaderActiveTopController,
              !isMenuVisible,
              let layoutSnapshot = currentPagingLayoutSnapshot() else {
            return
        }
        let shouldReopen = lastPagingLayoutSnapshot
            .map { layoutSnapshot.isMeaningfullyDifferent(from: $0) }
            ?? true
        rememberPagingLayoutSnapshot(layoutSnapshot)

        guard shouldReopen else {
            return
        }

        if currentPage == nil {
            guard let pendingRestoreAbsoluteOffset else {
                return
            }
            reopen(atAbsoluteOffset: pendingRestoreAbsoluteOffset, enforceChapterBoundary: true)
            return
        }

        let offset = usesVerticalScrolling
            ? (topAnchorAbsoluteOffset() ?? currentDisplayByteOffset())
            : currentDisplayByteOffset()
        reopen(atAbsoluteOffset: offset, enforceChapterBoundary: true)
    }

    var isReaderActiveTopController: Bool {
        guard let navigationController else {
            return view.window != nil && presentedViewController == nil
        }
        guard let readerStackController = navigationStackControllerForReader() else {
            return false
        }
        return navigationController.topViewController === readerStackController
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clearTextSelection()
        let destination = transitionCoordinator?.viewController(forKey: .to)
        let hidesNavigationBar = (destination as? ReaderPageTouchAreasViewController) != nil
        navigationController?.setNavigationBarHidden(
            hidesNavigationBar,
            animated: animated
        )
        if handleInteractiveReaderReturnIfNeeded() {
            return
        }
        switch UIApplication.shared.applicationState {
        case .active:
            UIApplication.shared.isIdleTimerDisabled = false
            stopAutoReading(restoreLayout: false, animated: false)
        case .background:
            UIApplication.shared.isIdleTimerDisabled = false
            pauseAutoReadingForBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
        saveProgressImmediately()
        saveSettingsImmediately()
    }

    func update(book: Book) {
        guard book.id != self.book.id else {
            return
        }

        self.book = book
        startInitialLoad()
    }

    private func configureCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = readerSettings.theme.backgroundColor
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            CollectionReaderPageCell.self,
            forCellWithReuseIdentifier: CollectionReaderPageCell.reuseIdentifier
        )
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureLoadingIndicator() {
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        collectionView.addGestureRecognizer(tapGesture)

        let moreMenuDismissTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleMoreMenuDismissTap(_:))
        )
        moreMenuDismissTapGesture.cancelsTouchesInView = false
        moreMenuDismissTapGesture.delegate = self
        view.addGestureRecognizer(moreMenuDismissTapGesture)
        self.moreMenuDismissTapGesture = moreMenuDismissTapGesture

        let autoReadTouchResetGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleAutoReadTouchReset(_:))
        )
        autoReadTouchResetGesture.minimumPressDuration = 0
        autoReadTouchResetGesture.cancelsTouchesInView = false
        autoReadTouchResetGesture.delaysTouchesBegan = false
        autoReadTouchResetGesture.delaysTouchesEnded = false
        autoReadTouchResetGesture.delegate = self
        collectionView.addGestureRecognizer(autoReadTouchResetGesture)
        self.autoReadTouchResetGesture = autoReadTouchResetGesture

        let nextSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handlePageSwipe(_:)))
        nextSwipe.direction = .left
        nextSwipe.delegate = self
        collectionView.addGestureRecognizer(nextSwipe)

        let previousSwipe = UISwipeGestureRecognizer(target: self, action: #selector(handlePageSwipe(_:)))
        previousSwipe.direction = .right
        previousSwipe.delegate = self
        collectionView.addGestureRecognizer(previousSwipe)

        let edgeBack = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgeBack(_:)))
        edgeBack.edges = .left
        edgeBack.delegate = self
        view.addGestureRecognizer(edgeBack)
        edgeBackGesture = edgeBack
        bindReaderGesturesToEdgeBackIfNeeded()
    }

    private func configureLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func bindReaderGesturesToEdgeBackIfNeeded() {
        let returnGesture = navigationController?.interactivePopGestureRecognizer ?? edgeBackGesture
        guard configuredInteractivePopGesture !== returnGesture else {
            return
        }

        configuredInteractivePopGesture = returnGesture
        guard let returnGesture else {
            return
        }

        collectionView.panGestureRecognizer.require(toFail: returnGesture)
        collectionView.gestureRecognizers?
            .filter { $0 is UISwipeGestureRecognizer }
            .forEach { $0.require(toFail: returnGesture) }
    }

    private func handleInteractiveReaderReturnIfNeeded() -> Bool {
        guard UIApplication.shared.applicationState == .active,
              let transitionCoordinator,
              transitionCoordinator.isInteractive,
              let destination = transitionCoordinator.viewController(forKey: .to),
              !(destination is ReaderPageTouchAreasViewController)
        else {
            return false
        }

        UIApplication.shared.isIdleTimerDisabled = false
        pauseAutoReadingForInteractiveReturn()
        saveProgressImmediately()
        saveSettingsImmediately()
        transitionCoordinator.notifyWhenInteractionChanges { [weak self] context in
            let isCancelled = context.isCancelled
            Task { [weak self] in
                guard let self else {
                    return
                }
                if isCancelled {
                    await self.restoreAfterInteractiveReturnCancellation()
                } else {
                    await self.finishAutoReadingAfterInteractiveReturnCompletion()
                }
            }
        }
        return true
    }

    private func restoreAfterInteractiveReturnCancellation() {
        navigationController?.setNavigationBarHidden(true, animated: true)
        updateReaderChromePreferences()
        refreshSystemStatusBarVisibility()
        resumeAutoReadingAfterInteractiveReturnCancellationIfNeeded()
    }

    private func startInitialLoad() {
        showLoading(true)
        loadTask?.cancel()
        pageTask?.cancel()
        openHistoryTask?.cancel()
        pendingRestoreAbsoluteOffset = nil
        pagingGeneration += 1
        openHistoryGeneration += 1
        let generation = pagingGeneration
        let targetBook = book
        let libraryRepository = repository
        let appFileStore = fileStore
        openedAt = Date()
        didRecordOpenHistory = false
        didShowProgressSaveError = false
        didShowSettingsSaveError = false

        loadTask = Task { [weak self] in
            do {
                async let chaptersTask = libraryRepository.fetchChapters(bookID: targetBook.id)
                async let bookmarksTask = libraryRepository.fetchBookmarks(bookID: targetBook.id)
                async let filterRulesTask = libraryRepository.fetchFilterRules(bookID: targetBook.id)
                async let progressTask = libraryRepository.fetchReadingProgress(bookID: targetBook.id)
                async let settingsTask = libraryRepository.fetchReaderSettings()
                let loadedChapters = try await chaptersTask
                let loadedBookmarks = try await bookmarksTask
                let loadedFilterRules = try await filterRulesTask
                let progress = try await progressTask
                let settings = try await settingsTask
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == generation else {
                        return
                    }
                    self.chapters = loadedChapters
                    self.bookmarks = loadedBookmarks
                    self.filterRules = loadedFilterRules
                    self.readerSettings = settings.normalized
                    self.updateReaderChromePreferences()
                    self.applyTheme()
                    self.configureCollectionViewForActiveSettings()
                    self.didStartOpening = true
                    let selected = Self.selectedChapter(from: loadedChapters, progress: progress)
                    let absoluteOffset = selected
                        .map { $0.chapter.startOffset + $0.offset }
                        ?? 0
                    self.openPage(absoluteOffset: absoluteOffset, generation: generation, fileStore: appFileStore)
                }
            } catch {
                await MainActor.run {
                    self?.showLoading(false)
                    self?.showError(error)
                }
            }
        }
    }

    /// 仅当处于 paged / curl 且 scrollView 正在拖动或 paging 减速时返回 true。
    /// 自动阅读走垂直布局且有自己的 displayLink 节奏,scroll 模式没有 paging snap,都不需要挂起。
    /// scrollView 静止后统一补做被推迟的两件事:
    /// 1. 头部修剪(append 路径里被跳过的);2. 提交挂起的 prepend。
    /// 头部修剪计划:确认是否需要裁、裁多少、裁掉多少视觉距离。不修改任何状态。
    /// 用 deleteItems + 同帧 setContentOffset 落盘修剪计划。
    /// 不再 reloadData,因此当前可见 cell 不会经历"prepareForReuse 清空 → 重 configure"的瞬白。
    /// 关闭隐式动画,避免被裁的 cell(本就在视口外)的默认 fade-out 在边缘被瞄到。
    /// 尾部修剪同样走 deleteItems。被裁的都在视口后方,不影响 contentOffset。
    func setAutoReadPanelVisible(_ visible: Bool, animated: Bool) {
        isAutoReadPanelVisible = visible
        autoReadPanel.isUserInteractionEnabled = visible
        refreshSystemStatusBarVisibility()
        view.layoutIfNeeded()
        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    self.applyAutoReadPanelPosition()
                }
            )
        } else {
            applyAutoReadPanelPosition()
        }
    }

    private func applyAutoReadPanelPosition() {
        let hiddenOffset = max(autoReadPanel.bounds.height, Layout.autoReadPanelHeight) + 1
        autoReadPanel.transform = isAutoReadPanelVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: hiddenOffset)
    }

    private func pushReaderPage(
        _ viewController: UIViewController,
        prefersNavigationBarHidden: Bool = false
    ) {
        viewController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle

        guard let navigationController else {
            let presentedNavigationController = UINavigationController(rootViewController: viewController)
            presentedNavigationController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
            presentedNavigationController.modalPresentationStyle = .fullScreen
            present(presentedNavigationController, animated: true)
            return
        }

        restoreNativeInteractivePopGesture()
        navigationController.setNavigationBarHidden(prefersNavigationBarHidden, animated: false)
        navigationController.pushViewController(viewController, animated: true)
    }

    private func closeReader(animated: Bool) {
        onClose()
    }

    private func popBackToReader(animated: Bool) {
        guard let navigationController else {
            presentedViewController?.dismiss(animated: animated)
            return
        }

        if let readerStackController = navigationStackControllerForReader() {
            navigationController.popToViewController(readerStackController, animated: animated)
        } else {
            navigationController.popViewController(animated: animated)
        }
    }

    func navigationStackControllerForReader() -> UIViewController? {
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

    private func restoreNativeInteractivePopGesture() {
        guard let navigationController,
              let gesture = navigationController.interactivePopGestureRecognizer
        else {
            return
        }

        gesture.delegate = self
        gesture.isEnabled = true
    }

    func showError(_ error: Error) {
        guard presentedViewController == nil else {
            readerLogger.error("Reader error while another controller is presented: \(error.localizedDescription, privacy: .public)")
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

    private func jumpTo(_ target: ReaderContentTarget) {
        stopAutoReading(restoreLayout: true, animated: false)
        setMenuVisible(false, animated: false)
        guard let chapter = chapters.first(where: { $0.id == target.chapterID }) else {
            return
        }
        let absolute = chapter.startOffset + min(max(target.offset, 0), max(chapter.byteLength - 1, 0))
        pagingGeneration += 1
        openPage(absoluteOffset: absolute, generation: pagingGeneration)
    }

    @objc func closeButtonTapped() {
        setMoreMenuVisible(false, animated: false)
        stopAutoReading(restoreLayout: false, animated: false)
        saveProgressImmediately()
        saveSettingsImmediately()
        closeReader(animated: true)
    }

    @objc func catalogButtonTapped() {
        setMoreMenuVisible(false, animated: true)
        stopAutoReading(restoreLayout: true, animated: false)
        saveProgressImmediately()
        let listViewController = ReaderContentsViewController(
            bookID: book.id,
            repository: repository,
            chapters: chapters,
            selectedChapterIndex: indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()) ?? 0,
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.refreshBookmarkState()
            }
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpTo(target)
            self.popBackToReader(animated: true)
        }
        pushReaderPage(listViewController)
    }

    @objc private func appDidEnterBackground() {
        pauseAutoReadingForBackground()
        saveProgressImmediately()
    }

    @objc private func appDidBecomeActive() {
        resumeAutoReadingAfterBackgroundIfNeeded()
        refreshHomeIndicatorDeferralPreferencesOnNextRunLoop()
    }

    @objc func showBookDetail() {
        stopAutoReading(restoreLayout: true, animated: false)
        saveProgressImmediately()
        let detailViewController = ReaderBookDetailViewController(
            book: book,
            repository: repository,
            fileStore: fileStore,
            chapters: chapters,
            selectedChapterIndex: indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()) ?? 0,
            onBookUpdated: { [weak self] updatedBook in
                guard let self else {
                    return
                }
                self.book = updatedBook
                self.titleLabel.text = updatedBook.title
            },
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.refreshBookmarkState()
            },
            onSelectCatalogTarget: { [weak self] target in
                guard let self else {
                    return
                }
                self.jumpTo(target)
                self.popBackToReader(animated: true)
            }
        )
        pushReaderPage(detailViewController)
    }

    @objc func showContentSearch() {
        showContentSearch(initialKeyword: nil)
    }

    func showContentSearch(initialKeyword: String?) {
        stopAutoReading(restoreLayout: true, animated: false)
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
            self.jumpTo(target)
            self.popBackToReader(animated: true)
        }
        pushReaderPage(searchViewController)
    }

    @objc func showFilterRules() {
        showFilterRules(initialSource: nil)
    }

    func showFilterRules(initialSource: String?) {
        stopAutoReading(restoreLayout: true, animated: false)
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
            self.collectionView.reloadData()
            self.reopen(atAbsoluteOffset: self.currentDisplayByteOffset(), enforceChapterBoundary: true)
        }
        pushReaderPage(filterViewController)
    }

    @objc func showPageTouchAreas() {
        stopAutoReading(restoreLayout: true, animated: false)
        let viewController = ReaderPageTouchAreasViewController(settings: readerSettings) { [weak self] settings in
            self?.applyReaderSettings(settings)
        }
        pushReaderPage(viewController, prefersNavigationBarHidden: true)
    }

    private static func selectedChapter(
        from chapters: [Chapter],
        progress: ReadingProgress?
    ) -> (index: Int, chapter: Chapter, offset: Int)? {
        guard !chapters.isEmpty else {
            return nil
        }
        if let progress,
           let chapterID = progress.chapterID,
           let index = chapters.firstIndex(where: { $0.id == chapterID }) {
            let chapter = chapters[index]
            return (
                index,
                chapter,
                min(max(Int(progress.chapterOffset), 0), max(chapter.byteLength - 1, 0))
            )
        }
        let chapter = chapters[0]
        return (0, chapter, 0)
    }
}

extension UIButton {
    func alignImageAboveTitle(spacing: CGFloat) {
        guard let imageView = imageView,
              let titleLabel = titleLabel
        else {
            return
        }

        let imageSize = imageView.intrinsicContentSize
        let titleSize = titleLabel.intrinsicContentSize
        imageEdgeInsets = UIEdgeInsets(
            top: -(titleSize.height + spacing),
            left: 0,
            bottom: 0,
            right: -titleSize.width
        )
        titleEdgeInsets = UIEdgeInsets(
            top: 0,
            left: -imageSize.width,
            bottom: -(imageSize.height + spacing),
            right: 0
        )
    }
}
