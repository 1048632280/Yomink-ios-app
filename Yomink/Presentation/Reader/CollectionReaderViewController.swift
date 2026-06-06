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

    private enum TapPageDirection {
        case previous
        case next
    }

    private let fileStore: AppFileStore
    private let repository: any LibraryRepository
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
    private let settingsPanelStack = UIStackView()
    private let settingsFontDecreaseButton = UIButton(type: .system)
    private let settingsFontValueButton = UIButton(type: .system)
    private let settingsFontIncreaseButton = UIButton(type: .system)
    private var layoutValueLabels: [LayoutAdjustment: UILabel] = [:]
    let fixedWidgetOverlay = ReaderPageWidgetOverlayView()
    private let widgetChapterTitleSwitch = UISwitch()
    private let widgetBatteryPercentageSwitch = UISwitch()
    private let widgetBatteryIconSwitch = UISwitch()
    private let widgetTimeSwitch = UISwitch()
    private let widgetChapterPageProgressSwitch = UISwitch()
    private let widgetGlobalProgressSwitch = UISwitch()
    var settingsControlPanRecognizers: [UIPanGestureRecognizer] = []
    private var settingsControlDragLastY: CGFloat = 0
    private let keepScreenAwakeSwitch = UISwitch()
    private let autoHideHomeIndicatorSwitch = UISwitch()
    private let autoHideStatusBarSwitch = UISwitch()
    private let edgeSwipeBackSwitch = UISwitch()
    private lazy var settingsPageModeControl = UISegmentedControl(
        items: [
            NSLocalizedString("reader.settings.pageTurn.slide", comment: ""),
            NSLocalizedString("reader.settings.pageTurn.curl", comment: ""),
            NSLocalizedString("reader.settings.pageTurn.scroll", comment: "")
        ]
    )
    private lazy var settingsThemeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.localizedTitle)
    )
    private lazy var settingsLayoutPresetControl = UISegmentedControl(
        items: ReaderSettings.LayoutPreset.allCases.map(\.localizedTitle)
    )
    private lazy var settingsQuickControl = UISegmentedControl(
        items: [
            NSLocalizedString("reader.settings.quick.page", comment: ""),
            NSLocalizedString("reader.settings.quick.layout", comment: ""),
            NSLocalizedString("reader.settings.quick.more", comment: "")
        ]
    )
    let loadingIndicator = UIActivityIndicatorView(style: .large)

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

    private static let widgetTimeFormatter: DateFormatter = {
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

    private enum SettingsQuickMode: Int {
        case page
        case layout
        case more
    }

    private enum LayoutAdjustment: CaseIterable, Hashable {
        case bodyKern
        case bodyLineSpacing
        case bodyParagraphSpacing
        case bodyTopMargin
        case bodyBottomMargin
        case bodyLeftMargin
        case bodyRightMargin
        case bodyFontWeight
        case firstLineIndent
        case titleKern
        case titleLineSpacing
        case titleParagraphSpacing
        case titleFontWeight
        case titleFontSizeDelta
        case widgetHorizontalMargin
        case widgetBottomMargin
        case widgetTitleTopMargin
        case widgetTitleLeftMargin

        var titleKey: String {
            switch self {
            case .bodyKern:
                return "reader.settings.layout.bodyKern"
            case .bodyLineSpacing:
                return "reader.settings.layout.bodyLineSpacing"
            case .bodyParagraphSpacing:
                return "reader.settings.layout.bodyParagraphSpacing"
            case .bodyTopMargin:
                return "reader.settings.layout.bodyTopMargin"
            case .bodyBottomMargin:
                return "reader.settings.layout.bodyBottomMargin"
            case .bodyLeftMargin:
                return "reader.settings.layout.bodyLeftMargin"
            case .bodyRightMargin:
                return "reader.settings.layout.bodyRightMargin"
            case .bodyFontWeight:
                return "reader.settings.layout.bodyFontWeight"
            case .firstLineIndent:
                return "reader.settings.layout.firstLineIndent"
            case .titleKern:
                return "reader.settings.layout.titleKern"
            case .titleLineSpacing:
                return "reader.settings.layout.titleLineSpacing"
            case .titleParagraphSpacing:
                return "reader.settings.layout.titleParagraphSpacing"
            case .titleFontWeight:
                return "reader.settings.layout.titleFontWeight"
            case .titleFontSizeDelta:
                return "reader.settings.layout.titleFontSizeDelta"
            case .widgetHorizontalMargin:
                return "reader.settings.layout.widgetHorizontalMargin"
            case .widgetBottomMargin:
                return "reader.settings.layout.widgetBottomMargin"
            case .widgetTitleTopMargin:
                return "reader.settings.layout.widgetTitleTopMargin"
            case .widgetTitleLeftMargin:
                return "reader.settings.layout.widgetTitleLeftMargin"
            }
        }

        var step: Double {
            switch self {
            case .bodyKern, .titleKern:
                return 0.5
            case .firstLineIndent:
                return 0.5
            case .bodyFontWeight, .titleFontWeight:
                return 1
            default:
                return 1
            }
        }

        func value(in values: ReaderSettings.LayoutValues) -> Double {
            switch self {
            case .bodyKern:
                return values.bodyKern
            case .bodyLineSpacing:
                return values.bodyLineSpacing
            case .bodyParagraphSpacing:
                return values.bodyParagraphSpacing
            case .bodyTopMargin:
                return values.bodyTopMargin
            case .bodyBottomMargin:
                return values.bodyBottomMargin
            case .bodyLeftMargin:
                return values.bodyLeftMargin
            case .bodyRightMargin:
                return values.bodyRightMargin
            case .bodyFontWeight:
                return values.bodyFontWeightValue
            case .firstLineIndent:
                return values.firstLineIndentEms
            case .titleKern:
                return values.titleKern
            case .titleLineSpacing:
                return values.titleLineSpacing
            case .titleParagraphSpacing:
                return values.titleParagraphSpacing
            case .titleFontWeight:
                return values.titleFontWeightValue
            case .titleFontSizeDelta:
                return values.titleFontSizeDelta
            case .widgetHorizontalMargin:
                return values.widgetHorizontalMargin
            case .widgetBottomMargin:
                return values.widgetBottomMargin
            case .widgetTitleTopMargin:
                return values.widgetTitleTopMargin
            case .widgetTitleLeftMargin:
                return values.widgetTitleLeftMargin
            }
        }

        func apply(delta: Double, to values: inout ReaderSettings.LayoutValues) {
            switch self {
            case .bodyKern:
                values.bodyKern += delta
            case .bodyLineSpacing:
                values.bodyLineSpacing += delta
            case .bodyParagraphSpacing:
                values.bodyParagraphSpacing += delta
            case .bodyTopMargin:
                values.bodyTopMargin += delta
            case .bodyBottomMargin:
                values.bodyBottomMargin += delta
            case .bodyLeftMargin:
                values.bodyLeftMargin += delta
            case .bodyRightMargin:
                values.bodyRightMargin += delta
            case .bodyFontWeight:
                values.bodyFontWeightValue += delta
            case .firstLineIndent:
                values.firstLineIndentEms += delta
            case .titleKern:
                values.titleKern += delta
            case .titleLineSpacing:
                values.titleLineSpacing += delta
            case .titleParagraphSpacing:
                values.titleParagraphSpacing += delta
            case .titleFontWeight:
                values.titleFontWeightValue += delta
            case .titleFontSizeDelta:
                values.titleFontSizeDelta += delta
            case .widgetHorizontalMargin:
                values.widgetHorizontalMargin += delta
            case .widgetBottomMargin:
                values.widgetBottomMargin += delta
            case .widgetTitleTopMargin:
                values.widgetTitleTopMargin += delta
            case .widgetTitleLeftMargin:
                values.widgetTitleLeftMargin += delta
            }
            values = values.normalized
        }

        func formattedValue(_ value: Double) -> String {
            switch self {
            case .bodyKern, .firstLineIndent, .titleKern:
                return String(format: "%.1f", value)
            case .bodyFontWeight, .titleFontWeight:
                return String(format: "%.0f", value)
            default:
                return String(format: "%.0f", value)
            }
        }
    }

    private final class LayoutAdjustmentButton: UIButton {
        var adjustment: LayoutAdjustment = .bodyLineSpacing
        var delta: Double = 0
    }

    private struct PagingLayoutSnapshot: @unchecked Sendable {
        let viewportSize: CGSize
        let safeAreaInsets: UIEdgeInsets
        let widgetInsets: UIEdgeInsets
        let isVerticalViewport: Bool

        func isMeaningfullyDifferent(from other: PagingLayoutSnapshot) -> Bool {
            isVerticalViewport != other.isVerticalViewport
                || Self.differs(viewportSize.width, other.viewportSize.width, tolerance: 1)
                || Self.differs(viewportSize.height, other.viewportSize.height, tolerance: 1)
                || Self.insetsDiffer(safeAreaInsets, other.safeAreaInsets, tolerance: 0.5)
                || Self.insetsDiffer(widgetInsets, other.widgetInsets, tolerance: 0.5)
        }

        func canProvideHorizontalFallback(for current: PagingLayoutSnapshot) -> Bool {
            !isVerticalViewport
                && !current.isVerticalViewport
                && !Self.differs(viewportSize.width, current.viewportSize.width, tolerance: 1)
                && !Self.differs(viewportSize.height, current.viewportSize.height, tolerance: 1)
                && !Self.insetsDiffer(widgetInsets, current.widgetInsets, tolerance: 0.5)
        }

        private static func differs(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat) -> Bool {
            abs(lhs - rhs) > tolerance
        }

        private static func insetsDiffer(
            _ lhs: UIEdgeInsets,
            _ rhs: UIEdgeInsets,
            tolerance: CGFloat
        ) -> Bool {
            differs(lhs.top, rhs.top, tolerance: tolerance)
                || differs(lhs.left, rhs.left, tolerance: tolerance)
                || differs(lhs.bottom, rhs.bottom, tolerance: tolerance)
                || differs(lhs.right, rhs.right, tolerance: tolerance)
        }
    }

    var book: Book
    var chapters: [Chapter] = []
    private var bookmarks: [Bookmark] = []
    private var filterRules: [TextFilterRule] = []
    var pages: [CollectionReaderPage] = []
    var currentPage: CollectionReaderPage?
    private var currentProgress: ReadingProgress?
    private var currentBookmark: Bookmark?
    var readerSettings = ReaderSettings.default
    private var settingsQuickMode: SettingsQuickMode = .page
    private var loadTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var bookmarkTask: Task<Void, Never>?
    private var openHistoryTask: Task<Void, Never>?
    private var pagingGeneration = 0
    private var saveGeneration = 0
    private var settingsSaveGeneration = 0
    private var openHistoryGeneration = 0
    private var didRecordOpenHistory = false
    private var openedAt = Date()
    private var didShowProgressSaveError = false
    private var didShowSettingsSaveError = false
    // 拖动 / paging 减速期间,把"头部 prepend"暂存到这里,等 scrollView 静止后再提交。
    // 尾部 append 直接走 insertItems 立即提交(不平移 contentOffset、不改已有 cell 的 indexPath),
    // 这样滑动期间 pages 可以持续增长,不会撞到 contentSize 边界翻不动。
    // 头部修剪(trimResidentPagesIfNeeded)在 defer 窗口里被跳过,由 flush 统一补做。
    private var pendingPagePrepends: [CollectionReaderPage] = []
    var isMenuVisible = false
    var isSettingsPanelVisible = false
    var isAutoReading = false
    var isAutoReadingPausedForBackground = false
    var isAutoReadingPausedForInteractiveReturn = false
    var isAutoReadPanelVisible = false
    private var isTrackingProgressSlider = false
    var isApplyingProgrammaticScroll = false
    private var didStartOpening = false
    var didReachEndOfBook = false
    private var isLoadingNextPage = false
    var pendingTapTargetPageIndex: Int?
    private var pendingRestoreAbsoluteOffset: Int?
    private var previousBatteryMonitoringEnabled = false
    var autoReadDisplayLink: CADisplayLink?
    var lastAutoReadTimestamp: CFTimeInterval?
    var lastAutoReadProgressUpdateTimestamp: CFTimeInterval = 0
    var autoReadVelocity: CGFloat = 0
    var shouldSuppressNextAutoReadTap = false
    weak var autoReadTouchResetGesture: UIGestureRecognizer?
    private weak var edgeBackGesture: UIScreenEdgePanGestureRecognizer?
    private weak var configuredInteractivePopGesture: UIGestureRecognizer?
    static let autoReadForwardInertiaDecayConstant: CGFloat = 2.5
    static let autoReadReverseInertiaDecayConstant: CGFloat = 2.5
    private var lastPagingLayoutSnapshot: PagingLayoutSnapshot?
    private var stableHorizontalPagingLayoutSnapshot: PagingLayoutSnapshot?
    private weak var settingsPageModeSection: UIView?
    private weak var settingsLayoutSection: UIView?
    private weak var settingsMoreSection: UIView?

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

        let offset = currentDisplayByteOffset()
        reopen(atAbsoluteOffset: offset, enforceChapterBoundary: true)
    }

    private var isReaderActiveTopController: Bool {
        guard let navigationController else {
            return view.window != nil && presentedViewController == nil
        }
        guard let readerStackController = navigationStackControllerForReader() else {
            return false
        }
        return navigationController.topViewController === readerStackController
    }

    private func currentPagingLayoutSnapshot() -> PagingLayoutSnapshot? {
        let viewportSize = collectionView.bounds.size
        guard viewportSize.width > 1,
              viewportSize.height > 1 else {
            return nil
        }
        return PagingLayoutSnapshot(
            viewportSize: viewportSize,
            safeAreaInsets: view.safeAreaInsets,
            widgetInsets: widgetContentInsets(),
            isVerticalViewport: usesVerticalScrolling
        )
    }

    private func pagingLayoutSnapshotForPageLoad() -> PagingLayoutSnapshot? {
        guard let currentSnapshot = currentPagingLayoutSnapshot() else {
            return nil
        }
        if !isReaderActiveTopController,
           let stableSnapshot = stableHorizontalPagingLayoutSnapshot,
           stableSnapshot.canProvideHorizontalFallback(for: currentSnapshot) {
            return stableSnapshot
        }
        return currentSnapshot
    }

    private func rememberPagingLayoutSnapshot(_ snapshot: PagingLayoutSnapshot) {
        guard !isMenuVisible else {
            return
        }
        lastPagingLayoutSnapshot = snapshot
        if !snapshot.isVerticalViewport {
            stableHorizontalPagingLayoutSnapshot = snapshot
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
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

    func configureSettingsPanel() {
        settingsPanel.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.effect = nil
        settingsPanel.backgroundColor = MenuStyle.barBackgroundColor
        settingsPanel.contentView.backgroundColor = MenuStyle.barBackgroundColor
        settingsPanel.transform = CGAffineTransform(
            translationX: 0,
            y: Layout.settingsPanelContentHeight + 1
        )
        settingsPanel.isUserInteractionEnabled = false
        settingsPanel.layer.cornerRadius = 0
        settingsPanel.layer.maskedCorners = []
        settingsPanel.clipsToBounds = true
        view.addSubview(settingsPanel)

        settingsPanelScrollView.alwaysBounceVertical = true
        settingsPanelScrollView.canCancelContentTouches = true
        settingsPanelScrollView.contentInsetAdjustmentBehavior = .never
        settingsPanelScrollView.delaysContentTouches = false
        settingsPanelScrollView.showsVerticalScrollIndicator = true
        settingsPanelScrollView.translatesAutoresizingMaskIntoConstraints = false
        settingsPanel.contentView.addSubview(settingsPanelScrollView)

        settingsPanelStack.axis = .vertical
        settingsPanelStack.alignment = .fill
        settingsPanelStack.spacing = 16
        settingsPanelStack.translatesAutoresizingMaskIntoConstraints = false
        settingsPanelScrollView.addSubview(settingsPanelStack)

        settingsQuickControl.selectedSegmentIndex = SettingsQuickMode.page.rawValue
        settingsQuickControl.addTarget(self, action: #selector(settingsQuickModeChanged), for: .valueChanged)
        styleSettingsControl(settingsQuickControl)

        settingsPageModeControl.addTarget(self, action: #selector(settingsPageModeChanged), for: .valueChanged)
        settingsThemeControl.addTarget(self, action: #selector(settingsThemeChanged), for: .valueChanged)
        settingsLayoutPresetControl.addTarget(self, action: #selector(settingsLayoutPresetChanged), for: .valueChanged)
        styleSettingsControl(settingsPageModeControl)
        styleSettingsControl(settingsThemeControl)
        styleSettingsControl(settingsLayoutPresetControl)

        settingsPanelStack.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.fontSize", comment: ""),
            control: fontSizeControl()
        ))
        settingsPanelStack.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.theme", comment: ""),
            control: settingsThemeControl
        ))
        settingsPanelStack.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.quick", comment: ""),
            control: settingsQuickControl
        ))
        let pageModeSection = settingsSection(
            title: NSLocalizedString("reader.settings.pageTurn", comment: ""),
            control: settingsPageModeControl
        )
        settingsPageModeSection = pageModeSection
        settingsPanelStack.addArrangedSubview(pageModeSection)
        let layoutSection = settingsSection(
            title: NSLocalizedString("reader.settings.layoutPreset", comment: ""),
            control: layoutSettingsControl()
        )
        settingsLayoutSection = layoutSection
        settingsPanelStack.addArrangedSubview(layoutSection)
        let moreSection = settingsMoreControls()
        settingsMoreSection = moreSection
        settingsPanelStack.addArrangedSubview(moreSection)

        NSLayoutConstraint.activate([
            settingsPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            settingsPanel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.settingsPanelContentHeight
            ),

            settingsPanelScrollView.leadingAnchor.constraint(equalTo: settingsPanel.contentView.leadingAnchor),
            settingsPanelScrollView.trailingAnchor.constraint(equalTo: settingsPanel.contentView.trailingAnchor),
            settingsPanelScrollView.topAnchor.constraint(equalTo: settingsPanel.contentView.topAnchor),
            settingsPanelScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            settingsPanelStack.leadingAnchor.constraint(
                equalTo: settingsPanelScrollView.contentLayoutGuide.leadingAnchor,
                constant: Layout.settingsPanelHorizontalInset
            ),
            settingsPanelStack.trailingAnchor.constraint(
                equalTo: settingsPanelScrollView.contentLayoutGuide.trailingAnchor,
                constant: -Layout.settingsPanelHorizontalInset
            ),
            settingsPanelStack.topAnchor.constraint(
                equalTo: settingsPanelScrollView.contentLayoutGuide.topAnchor,
                constant: Layout.settingsPanelTopInset
            ),
            settingsPanelStack.bottomAnchor.constraint(equalTo: settingsPanelScrollView.contentLayoutGuide.bottomAnchor),
            settingsPanelStack.widthAnchor.constraint(
                equalTo: settingsPanelScrollView.frameLayoutGuide.widthAnchor,
                constant: -Layout.settingsPanelHorizontalInset * 2
            )
        ])
        updateSettingsQuickSection()
    }

    private func styleSettingsControl(_ control: UISegmentedControl) {
        control.selectedSegmentTintColor = MenuStyle.settingsControlSelectedColor
        control.backgroundColor = MenuStyle.settingsControlBackgroundColor
        control.setTitleTextAttributes(
            [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: MenuStyle.secondaryTextColor
            ],
            for: .normal
        )
        control.setTitleTextAttributes(
            [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: MenuStyle.primaryTextColor
            ],
            for: .selected
        )
        control.setTitleTextAttributes(
            [
                .font: UIFont.preferredFont(forTextStyle: .footnote),
                .foregroundColor: UIColor(red: 0.39, green: 0.39, blue: 0.39, alpha: 1)
            ],
            for: .disabled
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.heightAnchor.constraint(equalToConstant: Layout.settingsControlHeight).isActive = true
        enableSettingsControlDrag(control)
    }

    private func settingsSection(title: String, control: UIView) -> UIView {
        let label = settingsSectionTitleLabel(title)

        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 9
        return stack
    }

    private func settingsSectionTitleLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = MenuStyle.secondaryTextColor
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func fontSizeControl() -> UIView {
        configureFontButton(settingsFontDecreaseButton, title: "-")
        configureFontButton(settingsFontIncreaseButton, title: "+")
        configureFontButton(settingsFontValueButton, title: "\(Int(readerSettings.normalized.fontSize))")
        settingsFontDecreaseButton.addTarget(self, action: #selector(settingsFontDecreaseTapped), for: .touchUpInside)
        settingsFontIncreaseButton.addTarget(self, action: #selector(settingsFontIncreaseTapped), for: .touchUpInside)
        settingsFontValueButton.addTarget(self, action: #selector(settingsFontResetTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            settingsFontDecreaseButton,
            settingsFontValueButton,
            settingsFontIncreaseButton
        ])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    private func layoutSettingsControl() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            settingsLayoutPresetControl,
            layoutAdjustmentGroup(
                titleKey: "reader.settings.layout.bodyGroup",
                adjustments: [
                    .bodyKern,
                    .bodyLineSpacing,
                    .bodyParagraphSpacing,
                    .bodyTopMargin,
                    .bodyBottomMargin,
                    .bodyLeftMargin,
                    .bodyRightMargin,
                    .bodyFontWeight,
                    .firstLineIndent
                ]
            ),
            layoutAdjustmentGroup(
                titleKey: "reader.settings.layout.titleGroup",
                adjustments: [
                    .titleKern,
                    .titleLineSpacing,
                    .titleParagraphSpacing,
                    .titleFontWeight,
                    .titleFontSizeDelta
                ]
            ),
            layoutAdjustmentGroup(
                titleKey: "reader.settings.layout.widgetGroup",
                adjustments: [
                    .widgetHorizontalMargin,
                    .widgetBottomMargin,
                    .widgetTitleTopMargin,
                    .widgetTitleLeftMargin
                ]
            )
        ])
        stack.axis = .vertical
        stack.spacing = 14
        return stack
    }

    private func layoutAdjustmentGroup(titleKey: String, adjustments: [LayoutAdjustment]) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString(titleKey, comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = MenuStyle.secondaryTextColor

        let rows = adjustments.map(layoutAdjustmentRow)
        let rowStack = UIStackView(arrangedSubviews: rows)
        rowStack.axis = .vertical
        rowStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [titleLabel, rowStack])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func layoutAdjustmentRow(_ adjustment: LayoutAdjustment) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString(adjustment.titleKey, comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = MenuStyle.primaryTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.textColor = MenuStyle.secondaryTextColor
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        layoutValueLabels[adjustment] = valueLabel

        let decreaseButton = layoutAdjustmentButton(systemName: "minus", adjustment: adjustment, delta: -adjustment.step)
        let increaseButton = layoutAdjustmentButton(systemName: "plus", adjustment: adjustment, delta: adjustment.step)

        let controlStack = UIStackView(arrangedSubviews: [decreaseButton, valueLabel, increaseButton])
        controlStack.axis = .horizontal
        controlStack.alignment = .center
        controlStack.spacing = 8
        controlStack.setContentHuggingPriority(.required, for: .horizontal)
        controlStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [titleLabel, controlStack])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 16
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)
        return row
    }

    private func layoutAdjustmentButton(
        systemName: String,
        adjustment: LayoutAdjustment,
        delta: Double
    ) -> LayoutAdjustmentButton {
        let button = LayoutAdjustmentButton(type: .system)
        button.adjustment = adjustment
        button.delta = delta
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = MenuStyle.primaryTextColor
        button.backgroundColor = MenuStyle.settingsControlSelectedColor
        button.layer.cornerRadius = Layout.settingsFontButtonHeight / 2
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(layoutAdjustmentButtonTapped(_:)), for: .touchUpInside)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            forImageIn: .normal
        )
        enableSettingsControlDrag(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.settingsFontButtonHeight),
            button.heightAnchor.constraint(equalToConstant: Layout.settingsFontButtonHeight)
        ])
        return button
    }

    private func configureFontButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
        button.backgroundColor = MenuStyle.settingsControlSelectedColor
        button.layer.cornerRadius = Layout.settingsFontButtonHeight / 2
        button.layer.masksToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: Layout.settingsFontButtonHeight).isActive = true
        enableSettingsControlDrag(button)
    }

    private func settingsMoreControls() -> UIView {
        let widgetStack = UIStackView(arrangedSubviews: [
            settingsGroupTitle("reader.settings.widgets.group"),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.chapterTitle", comment: ""),
                toggle: widgetChapterTitleSwitch,
                action: #selector(widgetChapterTitleChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.batteryPercentage", comment: ""),
                toggle: widgetBatteryPercentageSwitch,
                action: #selector(widgetBatteryPercentageChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.batteryIcon", comment: ""),
                toggle: widgetBatteryIconSwitch,
                action: #selector(widgetBatteryIconChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.time", comment: ""),
                toggle: widgetTimeSwitch,
                action: #selector(widgetTimeChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.chapterPageProgress", comment: ""),
                toggle: widgetChapterPageProgressSwitch,
                action: #selector(widgetChapterPageProgressChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.globalProgress", comment: ""),
                toggle: widgetGlobalProgressSwitch,
                action: #selector(widgetGlobalProgressChanged)
            )
        ])
        widgetStack.axis = .vertical
        widgetStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [
            switchRow(
                title: NSLocalizedString("reader.settings.keepScreenAwake", comment: ""),
                toggle: keepScreenAwakeSwitch,
                action: #selector(keepScreenAwakeChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.autoHideHomeIndicator", comment: ""),
                toggle: autoHideHomeIndicatorSwitch,
                action: #selector(autoHideHomeIndicatorChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.autoHideStatusBar", comment: ""),
                toggle: autoHideStatusBarSwitch,
                action: #selector(autoHideStatusBarChanged)
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.edgeSwipeBack", comment: ""),
                toggle: edgeSwipeBackSwitch,
                action: #selector(edgeSwipeBackChanged)
            ),
            widgetStack
        ])
        stack.axis = .vertical
        stack.spacing = 16
        return stack
    }

    private func settingsGroupTitle(_ key: String) -> UILabel {
        let label = UILabel()
        label.text = NSLocalizedString(key, comment: "")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = MenuStyle.secondaryTextColor
        return label
    }

    private func switchRow(title: String, toggle: UISwitch, action: Selector) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = MenuStyle.primaryTextColor
        label.adjustsFontForContentSizeCategory = true
        toggle.onTintColor = .systemGreen
        toggle.addTarget(self, action: action, for: .valueChanged)
        enableSettingsControlDrag(toggle)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 16
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: 0,
            bottom: 8,
            trailing: 0
        )
        return row
    }

    private func enableSettingsControlDrag(_ control: UIControl) {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(settingsControlPanChanged(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        control.addGestureRecognizer(panGesture)
        settingsControlPanRecognizers.append(panGesture)
    }

    @objc private func settingsControlPanChanged(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: settingsPanelScrollView)
        switch gesture.state {
        case .began:
            settingsControlDragLastY = translation.y
            settingsPanelScrollView.panGestureRecognizer.isEnabled = false
        case .changed:
            let deltaY = translation.y - settingsControlDragLastY
            settingsControlDragLastY = translation.y
            scrollSettingsPanel(by: deltaY)
        default:
            settingsControlDragLastY = 0
            settingsPanelScrollView.panGestureRecognizer.isEnabled = true
        }
    }

    private func scrollSettingsPanel(by deltaY: CGFloat) {
        guard settingsPanelScrollView.contentSize.height > settingsPanelScrollView.bounds.height else {
            return
        }
        let minOffset = -settingsPanelScrollView.adjustedContentInset.top
        let maxOffset = max(
            minOffset,
            settingsPanelScrollView.contentSize.height
                - settingsPanelScrollView.bounds.height
                + settingsPanelScrollView.adjustedContentInset.bottom
        )
        let targetY = min(max(settingsPanelScrollView.contentOffset.y - deltaY, minOffset), maxOffset)
        settingsPanelScrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
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

    private func openPage(
        absoluteOffset: Int,
        generation: Int? = nil,
        fileStore: AppFileStore? = nil,
        showsLoadingIndicator: Bool = true
    ) {
        guard !chapters.isEmpty else {
            showLoading(false)
            return
        }
        guard let layoutSnapshot = pagingLayoutSnapshotForPageLoad() else {
            pendingRestoreAbsoluteOffset = absoluteOffset
            if showsLoadingIndicator {
                showLoading(true)
            }
            return
        }

        pendingRestoreAbsoluteOffset = nil
        pageTask?.cancel()
        pendingPagePrepends.removeAll()
        pendingTapTargetPageIndex = nil
        let activeGeneration = generation ?? {
            pagingGeneration += 1
            return pagingGeneration
        }()
        let requestOffset = min(max(absoluteOffset, 0), max(chapters.last?.endOffset ?? 1, 1) - 1)
        let targetBook = book
        let loadedChapters = chapters
        let activeRules = filterRules
        let settings = readerSettings.normalized
        let viewportSize = layoutSnapshot.viewportSize
        let safeAreaInsets = layoutSnapshot.safeAreaInsets
        let widgetInsets = layoutSnapshot.widgetInsets
        let isVerticalViewport = layoutSnapshot.isVerticalViewport
        let appFileStore = fileStore ?? self.fileStore
        didReachEndOfBook = false
        isLoadingNextPage = true
        if showsLoadingIndicator {
            showLoading(true)
        }

        pageTask = Task { [weak self] in
            do {
                let page = try await CollectionReaderPaginator.makePage(
                    book: targetBook,
                    chapters: loadedChapters,
                    absoluteOffset: requestOffset,
                    settings: settings,
                    filterRules: activeRules,
                    viewportSize: viewportSize,
                    safeAreaInsets: safeAreaInsets,
                    widgetInsets: widgetInsets,
                    isVerticalViewport: isVerticalViewport,
                    fileStore: appFileStore
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.pages = [page]
                    self.currentPage = page
                    self.collectionView.reloadData()
                    self.collectionView.layoutIfNeeded()
                    self.collectionView.setContentOffset(self.contentOffset(forPageAt: 0), animated: false)
                    if self.isReaderActiveTopController {
                        self.rememberPagingLayoutSnapshot(layoutSnapshot)
                    }
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                    self.recordBookOpenedIfNeeded()
                    self.prefetchPagesNearCurrent()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                    self.showError(error)
                }
            }
        }
    }

    private func reopen(atAbsoluteOffset offset: Int, enforceChapterBoundary _: Bool) {
        guard didStartOpening else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: offset, generation: pagingGeneration)
    }

    func loadNextPageIfNeeded(scrollAfterLoading: Bool = false) {
        guard pageTask == nil,
              !didReachEndOfBook,
              let lastPage = pages.last else {
            return
        }
        guard lastPage.endAbsoluteOffset < (chapters.last?.endOffset ?? 0) else {
            didReachEndOfBook = true
            updateSessionState(isLoadingNextPage: false)
            return
        }
        if scrollAfterLoading {
            pendingTapTargetPageIndex = lastPage.pageIndex + 1
        }
        let targetLocalPageIndex = lastPage.localPageIndex + 1 < lastPage.chapterPageCount
            ? lastPage.localPageIndex + 1
            : nil
        loadPage(
            absoluteOffset: lastPage.endAbsoluteOffset,
            pageIndex: lastPage.pageIndex + 1,
            insertingAtEnd: true,
            targetLocalPageIndex: targetLocalPageIndex
        )
    }

    func loadPreviousPageIfNeeded(scrollAfterLoading: Bool = false) {
        guard pageTask == nil,
              let firstPage = leadingBoundaryPage(),
              firstPage.startAbsoluteOffset > 0 else {
            return
        }

        if scrollAfterLoading {
            pendingTapTargetPageIndex = firstPage.pageIndex - 1
        }
        let targetLocalPageIndex = firstPage.localPageIndex > 0
            ? firstPage.localPageIndex - 1
            : nil
        let targetOffset = previousPageStartOffset(before: firstPage.startAbsoluteOffset)
        loadPage(
            absoluteOffset: targetOffset,
            pageIndex: firstPage.pageIndex - 1,
            insertingAtEnd: false,
            targetLocalPageIndex: targetLocalPageIndex
        )
    }

    private func loadPage(
        absoluteOffset: Int,
        pageIndex: Int,
        insertingAtEnd: Bool,
        targetLocalPageIndex: Int? = nil
    ) {
        let requestOffset = min(max(absoluteOffset, 0), max(chapters.last?.endOffset ?? 1, 1) - 1)
        let generation = pagingGeneration
        let targetBook = book
        let loadedChapters = chapters
        let activeRules = filterRules
        let settings = readerSettings.normalized
        guard let layoutSnapshot = pagingLayoutSnapshotForPageLoad() else {
            return
        }
        let viewportSize = layoutSnapshot.viewportSize
        let safeAreaInsets = layoutSnapshot.safeAreaInsets
        let widgetInsets = layoutSnapshot.widgetInsets
        let isVerticalViewport = layoutSnapshot.isVerticalViewport
        let appFileStore = fileStore
        isLoadingNextPage = insertingAtEnd
        updateSessionState(isLoadingNextPage: insertingAtEnd)

        pageTask = Task { [weak self] in
            do {
                let page = try await CollectionReaderPaginator.makePage(
                    book: targetBook,
                    chapters: loadedChapters,
                    absoluteOffset: requestOffset,
                    forcedPageIndex: pageIndex,
                    settings: settings,
                    filterRules: activeRules,
                    viewportSize: viewportSize,
                    safeAreaInsets: safeAreaInsets,
                    widgetInsets: widgetInsets,
                    isVerticalViewport: isVerticalViewport,
                    targetLocalPageIndex: targetLocalPageIndex,
                    fileStore: appFileStore
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == generation else {
                        return
                    }
                    self.pageTask = nil
                    if self.isReaderActiveTopController {
                        self.rememberPagingLayoutSnapshot(layoutSnapshot)
                    }
                    if insertingAtEnd {
                        self.appendPage(page)
                    } else {
                        self.prependPage(page)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == generation else {
                        return
                    }
                    self.pageTask = nil
                    if !(error is CancellationError) {
                        self.showError(error)
                    }
                    self.updateSessionState(isLoadingNextPage: false)
                }
            }
        }
    }

    private func appendPage(_ page: CollectionReaderPage) {
        if pages.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset })
            || pendingPagePrepends.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset }) {
            updateSessionState(isLoadingNextPage: false)
            return
        }
        // 尾部 append 立即提交,但用 performWithoutAnimation 关闭默认渐入,
        // 避免快速滑动时刚追到新 cell 还没 fade 完就被瞄到半透明状态。
        // insertItems 只为新增的 indexPath 生成布局属性,不动 contentOffset、不改已有 cell 的 indexPath,
        // paging snap 锚点保持不变,pages 在滑动期间可连续增长。
        let newIndexPath = IndexPath(item: pages.count, section: 0)
        UIView.performWithoutAnimation {
            self.pages.append(page)
            self.collectionView.insertItems(at: [newIndexPath])
        }
        // 头部修剪在 defer 窗口里跳过(它会平移 contentOffset 并改 cell indexPath,
        // 是"前一页瞬变 + 卡半页"的直接元凶)。flush 时统一补做。
        if !shouldDeferPageMutationForActivePaging,
           let plan = planPrefixTrim() {
            applyPrefixTrim(plan)
        }
        updateSessionState(isLoadingNextPage: false)
        if pendingTapTargetPageIndex == page.pageIndex,
           let index = pages.firstIndex(of: page) {
            pendingTapTargetPageIndex = nil
            turnToPage(at: index, direction: .next)
        }
        // 静止状态下显式接力预取:scrollViewDidScroll 此刻不会被触发,
        // 必须主动延伸链条,否则目录跳转 / 点击翻页后只会装载单张邻页。
        if !shouldDeferPageMutationForActivePaging {
            prefetchPagesNearCurrent()
        }
    }

    private func prependPage(_ page: CollectionReaderPage) {
        if pages.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset })
            || pendingPagePrepends.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset }) {
            updateSessionState(isLoadingNextPage: false)
            return
        }
        // 头部 prepend 必然要平移 contentOffset(把所有已有 cell 往后挪一页),
        // 拖动中做这件事一定会破坏 paging snap;挂起到静止时再做。
        if shouldDeferPageMutationForActivePaging {
            pendingPagePrepends.append(page)
            updateSessionState(isLoadingNextPage: false)
            prefetchPagesNearCurrent()
            return
        }
        let extent = usesVerticalScrolling
            ? verticalExtent(for: page)
            : pageExtentForCurrentMode()
        let preservedCurrentPage = currentPage
        // 用 insertItems + 同帧 setContentOffset 替代 reloadData:
        // 不销毁已有可见 cell,杜绝快速点击 / 横滑回弹时的瞬白闪烁。
        // performWithoutAnimation 同时关闭默认插入动画和 contentOffset 平移动画,保证视觉上原页面不动。
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.insert(page, at: 0)
                self.collectionView.insertItems(at: [IndexPath(item: 0, section: 0)])
                if let plan = self.planSuffixTrim() {
                    self.applySuffixTrim(plan)
                }
                if extent > 0 {
                    let adjusted = self.usesVerticalScrolling
                        ? CGPoint(
                            x: self.collectionView.contentOffset.x,
                            y: self.collectionView.contentOffset.y + extent
                        )
                        : CGPoint(
                            x: self.collectionView.contentOffset.x + extent,
                            y: self.collectionView.contentOffset.y
                        )
                    self.collectionView.setContentOffset(adjusted, animated: false)
                }
            }
        }
        restoreCurrentPageAfterProgrammaticMutation(preservedCurrentPage)
        updateSessionState(isLoadingNextPage: false)
        if pendingTapTargetPageIndex == page.pageIndex,
           let index = pages.firstIndex(of: page) {
            pendingTapTargetPageIndex = nil
            turnToPage(at: index, direction: .previous)
        }
        // 同 appendPage:静止状态下接力预取另一方向(或同方向再装一张),
        // 是修复目录跳转后链条断裂的关键。
        prefetchPagesNearCurrent()
    }

    /// 仅当处于 paged / curl 且 scrollView 正在拖动或 paging 减速时返回 true。
    /// 自动阅读走垂直布局且有自己的 displayLink 节奏,scroll 模式没有 paging snap,都不需要挂起。
    private var shouldDeferPageMutationForActivePaging: Bool {
        guard !isAutoReading,
              readerSettings.pageMode == .paged || readerSettings.pageMode == .curl else {
            return false
        }
        return collectionView.isDragging
            || collectionView.isTracking
            || collectionView.isDecelerating
    }

    /// scrollView 静止后统一补做被推迟的两件事:
    /// 1. 头部修剪(append 路径里被跳过的);2. 提交挂起的 prepend。
    func flushPendingPageInsertions() {
        if !pages.isEmpty,
           let plan = planPrefixTrim() {
            applyPrefixTrim(plan)
        }
        guard !pendingPagePrepends.isEmpty else {
            return
        }
        let pending = Array(pendingPagePrepends.reversed())
        pendingPagePrepends.removeAll()

        let extent = pending.reduce(CGFloat(0)) { result, page in
            result + (
                usesVerticalScrolling
                    ? verticalExtent(for: page)
                    : pageExtentForCurrentMode()
            )
        }
        let insertedIndexPaths = pending.indices.map { IndexPath(item: $0, section: 0) }
        let preservedCurrentPage = currentPage
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.insert(contentsOf: pending, at: 0)
                self.collectionView.insertItems(at: insertedIndexPaths)
                if let plan = self.planSuffixTrim() {
                    self.applySuffixTrim(plan)
                }
                if extent > 0 {
                    let adjusted = self.usesVerticalScrolling
                        ? CGPoint(
                            x: self.collectionView.contentOffset.x,
                            y: self.collectionView.contentOffset.y + extent
                        )
                        : CGPoint(
                            x: self.collectionView.contentOffset.x + extent,
                            y: self.collectionView.contentOffset.y
                        )
                    self.collectionView.setContentOffset(adjusted, animated: false)
                }
            }
        }
        restoreCurrentPageAfterProgrammaticMutation(preservedCurrentPage)
        updateSessionState(isLoadingNextPage: false)
    }

    private func previousPageStartOffset(before absoluteOffset: Int) -> Int {
        max(0, absoluteOffset - 1)
    }

    /// 头部修剪计划:确认是否需要裁、裁多少、裁掉多少视觉距离。不修改任何状态。
    private struct PrefixTrimPlan {
        let removeCount: Int
        let removedDistance: CGFloat
    }

    private func planPrefixTrim() -> PrefixTrimPlan? {
        guard pages.count > Layout.maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage),
              currentIndex > 3 else {
            return nil
        }
        let overflow = pages.count - Layout.maximumResidentPages
        let removableBeforeCurrent = max(0, currentIndex - 3)
        let removeCount = min(overflow, removableBeforeCurrent)
        guard removeCount > 0 else {
            return nil
        }
        let removedDistance = usesVerticalScrolling
            ? pages.prefix(removeCount).reduce(CGFloat(0)) { result, page in
                result + verticalExtent(for: page)
            }
            : CGFloat(removeCount) * pageExtentForCurrentMode()
        return PrefixTrimPlan(removeCount: removeCount, removedDistance: removedDistance)
    }

    /// 用 deleteItems + 同帧 setContentOffset 落盘修剪计划。
    /// 不再 reloadData,因此当前可见 cell 不会经历"prepareForReuse 清空 → 重 configure"的瞬白。
    /// 关闭隐式动画,避免被裁的 cell(本就在视口外)的默认 fade-out 在边缘被瞄到。
    private func applyPrefixTrim(_ plan: PrefixTrimPlan) {
        let removedIndexPaths = (0..<plan.removeCount).map { IndexPath(item: $0, section: 0) }
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.removeFirst(plan.removeCount)
                self.collectionView.deleteItems(at: removedIndexPaths)
                self.adjustContentOffsetAfterRemovingPrefix(distance: plan.removedDistance)
            }
        }
    }

    private struct SuffixTrimPlan {
        let removeCount: Int
    }

    private func planSuffixTrim() -> SuffixTrimPlan? {
        guard pages.count > Layout.maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return nil
        }
        let overflow = pages.count - Layout.maximumResidentPages
        let removableAfterCurrent = max(0, pages.count - currentIndex - 4)
        let removeCount = min(overflow, removableAfterCurrent)
        guard removeCount > 0 else {
            return nil
        }
        return SuffixTrimPlan(removeCount: removeCount)
    }

    /// 尾部修剪同样走 deleteItems。被裁的都在视口后方,不影响 contentOffset。
    private func applySuffixTrim(_ plan: SuffixTrimPlan) {
        let startIndex = pages.count - plan.removeCount
        let removedIndexPaths = (startIndex..<pages.count).map { IndexPath(item: $0, section: 0) }
        UIView.performWithoutAnimation {
            self.pages.removeLast(plan.removeCount)
            self.collectionView.deleteItems(at: removedIndexPaths)
        }
    }

    private func adjustContentOffsetAfterRemovingPrefix(distance: CGFloat) {
        guard distance > 0 else {
            return
        }
        let minimumY = -collectionView.contentInset.top
        let adjusted = usesVerticalScrolling
            ? CGPoint(x: collectionView.contentOffset.x, y: max(minimumY, collectionView.contentOffset.y - distance))
            : CGPoint(x: max(0, collectionView.contentOffset.x - distance), y: collectionView.contentOffset.y)
        collectionView.setContentOffset(adjusted, animated: false)
    }

    private func performProgrammaticPageMutation(_ mutation: () -> Void) {
        let wasApplyingProgrammaticScroll = isApplyingProgrammaticScroll
        isApplyingProgrammaticScroll = true
        defer {
            isApplyingProgrammaticScroll = wasApplyingProgrammaticScroll
        }
        mutation()
    }

    private func restoreCurrentPageAfterProgrammaticMutation(_ page: CollectionReaderPage?) {
        guard let page,
              pages.contains(page) else {
            updateCurrentPageFromVisiblePage()
            return
        }
        currentPage = page
    }

    func prefetchPagesNearCurrent() {
        guard let currentPage,
              let index = pages.firstIndex(of: currentPage) else {
            return
        }
        let leadingCount = index + pendingPagePrepends.count
        let trailingCount = pages.count - index - 1

        let needsLeading = leadingCount <= Layout.horizontalPrefetchDistance
        let needsTrailing = trailingCount <= Layout.horizontalPrefetchDistance

        if needsLeading && needsTrailing {
            if trailingCount <= leadingCount {
                loadNextPageIfNeeded()
                if pageTask != nil {
                    return
                }
                loadPreviousPageIfNeeded()
            } else {
                loadPreviousPageIfNeeded()
                if pageTask != nil {
                    return
                }
                loadNextPageIfNeeded()
            }
            return
        }

        if needsLeading {
            loadPreviousPageIfNeeded()
            if pageTask != nil {
                return
            }
        }
        if needsTrailing {
            loadNextPageIfNeeded()
        }
    }

    private func leadingBoundaryPage() -> CollectionReaderPage? {
        pendingPagePrepends.last ?? pages.first
    }

    func configureCollectionViewForActiveSettings() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        if isAutoReading {
            configureCollectionViewForAutoReading()
            updateFixedWidgetOverlay()
            return
        }
        let contentInsets: UIEdgeInsets
        switch readerSettings.pageMode {
        case .paged:
            layout.scrollDirection = .horizontal
            collectionView.isScrollEnabled = true
            collectionView.isPagingEnabled = true
            collectionView.alwaysBounceVertical = false
            contentInsets = .zero
        case .curl:
            layout.scrollDirection = .horizontal
            collectionView.isScrollEnabled = false
            collectionView.isPagingEnabled = true
            collectionView.alwaysBounceVertical = false
            contentInsets = .zero
        case .scroll:
            layout.scrollDirection = .vertical
            collectionView.isScrollEnabled = true
            collectionView.isPagingEnabled = false
            collectionView.alwaysBounceVertical = true
            contentInsets = verticalContinuousInsets()
        }
        collectionView.contentInset = contentInsets
        collectionView.scrollIndicatorInsets = contentInsets
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        updateVerticalContentCovers()
        updateFixedWidgetOverlay()
    }

    func configureCollectionViewForAutoReading() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        layout.scrollDirection = .vertical
        collectionView.isScrollEnabled = true
        collectionView.isPagingEnabled = false
        collectionView.alwaysBounceVertical = true
        let contentInsets = verticalContinuousInsets()
        collectionView.contentInset = contentInsets
        collectionView.scrollIndicatorInsets = contentInsets
        collectionView.showsVerticalScrollIndicator = false
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        updateVerticalContentCovers()
        updateFixedWidgetOverlay()
    }

    private func effectiveReaderLayout() -> ReaderLayoutConfiguration {
        var layout = readerSettings.normalized.effectiveLayoutConfiguration
        let safeAreaInsets = view.safeAreaInsets
        let widgetInsets = widgetContentInsets()
        if safeAreaInsets.top > 0 {
            layout.topMargin = max(layout.topMargin, safeAreaInsets.top + 12)
        }
        if safeAreaInsets.bottom > 0 {
            layout.bottomMargin = max(layout.bottomMargin, safeAreaInsets.bottom + 2)
        }
        if safeAreaInsets.left > 0 {
            layout.leftMargin = max(layout.leftMargin, safeAreaInsets.left + 12)
        }
        if safeAreaInsets.right > 0 {
            layout.rightMargin = max(layout.rightMargin, safeAreaInsets.right + 12)
        }
        layout.topMargin = max(layout.topMargin, widgetInsets.top)
        layout.bottomMargin = max(layout.bottomMargin, widgetInsets.bottom)
        return layout
    }

    func displayLayoutForCurrentMode() -> ReaderLayoutConfiguration {
        var layout = effectiveReaderLayout()
        if usesVerticalScrolling {
            layout.topMargin = 0
            layout.bottomMargin = 0
        }
        return layout
    }

    func verticalContinuousInsets() -> UIEdgeInsets {
        let widgetInsets = widgetContentInsets()
        return UIEdgeInsets(
            top: widgetInsets.top,
            left: 0,
            bottom: widgetInsets.bottom,
            right: 0
        )
    }

    private func verticalContinuousPageHeight() -> CGFloat {
        let insets = verticalContinuousInsets()
        return max(1, collectionView.bounds.height - insets.top - insets.bottom)
    }

    private func widgetContentInsets() -> UIEdgeInsets {
        let values = readerSettings.normalized.effectiveLayoutValues
        let visibility = readerSettings.normalized.widgetVisibility
        let hasTopWidget = visibility.chapterTitle
        let hasBottomWidget = visibility.batteryPercentage
            || visibility.batteryIcon
            || visibility.time
            || visibility.chapterPageProgress
            || visibility.globalProgress
        let widgetFont = UIFont.preferredFont(forTextStyle: .caption1)
        let topWidgetHeight = ceil(widgetFont.lineHeight)
        let hasBottomTextWidget = visibility.batteryPercentage
            || visibility.time
            || visibility.chapterPageProgress
            || visibility.globalProgress
        let bottomTextHeight = hasBottomTextWidget ? widgetFont.lineHeight : 0
        let bottomIconHeight: CGFloat = visibility.batteryIcon ? 12 : 0
        let bottomWidgetHeight = ceil(max(bottomTextHeight, bottomIconHeight))
        return UIEdgeInsets(
            top: hasTopWidget ? CGFloat(values.widgetTitleTopMargin) + topWidgetHeight : 0,
            left: 0,
            bottom: hasBottomWidget ? CGFloat(values.widgetBottomMargin) + bottomWidgetHeight : 0,
            right: 0
        )
    }

    func updateReaderChromePreferences() {
        let normalized = readerSettings.normalized
        UIApplication.shared.isIdleTimerDisabled = normalized.keepScreenAwake
        refreshSystemStatusBarVisibility()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        settingsPageModeControl.selectedSegmentIndex = normalized.pageMode.settingsPageTurnIndex
        settingsThemeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases.firstIndex(of: normalized.theme) ?? 0
        settingsLayoutPresetControl.selectedSegmentIndex = ReaderSettings.LayoutPreset.allCases.firstIndex(of: normalized.layoutPreset) ?? 0
        settingsFontValueButton.setTitle("\(Int(normalized.fontSize))", for: .normal)
        settingsQuickControl.selectedSegmentIndex = settingsQuickMode.rawValue
        keepScreenAwakeSwitch.isOn = normalized.keepScreenAwake
        autoHideHomeIndicatorSwitch.isOn = normalized.autoHideHomeIndicator
        autoHideStatusBarSwitch.isOn = normalized.autoHideStatusBar
        edgeSwipeBackSwitch.isOn = normalized.edgeSwipeBackEnabled
        widgetChapterTitleSwitch.isOn = normalized.widgetVisibility.chapterTitle
        widgetBatteryPercentageSwitch.isOn = normalized.widgetVisibility.batteryPercentage
        widgetBatteryIconSwitch.isOn = normalized.widgetVisibility.batteryIcon
        widgetTimeSwitch.isOn = normalized.widgetVisibility.time
        widgetChapterPageProgressSwitch.isOn = normalized.widgetVisibility.chapterPageProgress
        widgetGlobalProgressSwitch.isOn = normalized.widgetVisibility.globalProgress
        autoReadSpeedSlider.value = Float(normalized.autoReadSpeed)
        updateLayoutValueLabels()
        updateSettingsQuickSection()
        updateFixedWidgetOverlay()
    }

    private func updateSettingsQuickSection() {
        settingsPageModeSection?.isHidden = settingsQuickMode != .page
        settingsLayoutSection?.isHidden = settingsQuickMode != .layout
        settingsMoreSection?.isHidden = settingsQuickMode != .more
    }

    private func updateLayoutValueLabels() {
        let values = readerSettings.normalized.effectiveLayoutValues
        for adjustment in LayoutAdjustment.allCases {
            layoutValueLabels[adjustment]?.text = adjustment.formattedValue(adjustment.value(in: values))
        }
    }

    func setSettingsPanelVisible(_ visible: Bool, animated: Bool) {
        isSettingsPanelVisible = visible
        settingsPanel.isUserInteractionEnabled = visible
        refreshSystemStatusBarVisibility()
        view.layoutIfNeeded()
        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    self.applySettingsPanelPosition(animated: true)
                }
            )
        } else {
            applySettingsPanelPosition(animated: false)
        }
    }

    private func applySettingsPanelPosition(animated _: Bool) {
        let hiddenOffset = settingsPanel.bounds.height + 1
        settingsPanel.transform = isSettingsPanelVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: hiddenOffset)
    }

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

    private func updateSessionState(isLoadingNextPage: Bool) {
        self.isLoadingNextPage = isLoadingNextPage
        updateCurrentProgress()
        refreshBookmarkState()
    }

    private func updateCurrentProgress() {
        guard let currentPage,
              let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset) else {
            currentProgress = nil
            return
        }

        let chapterOffset = currentPage.startAbsoluteOffset - chapter.startOffset
        let total = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let globalProgress = min(max(Double(currentPage.startAbsoluteOffset) / Double(total), 0), 1)
        currentProgress = ReadingProgress(
            bookID: book.id,
            chapterID: chapter.id,
            chapterOffset: Int64(max(chapterOffset, 0)),
            globalProgress: globalProgress
        )
        progressLabel.text = progressText(
            chapter: chapter,
            chapterProgress: chapter.byteLength > 0 ? Double(max(chapterOffset, 0)) / Double(chapter.byteLength) : 0,
            globalProgress: globalProgress
        )
        if !isTrackingProgressSlider {
            progressSlider.value = Float(chapterProgress(for: currentPage, in: chapter))
        }
        updateFixedWidgetOverlay()
    }

    private func chapterProgress(
        for page: CollectionReaderPage,
        in chapter: Chapter
    ) -> Double {
        guard chapter.byteLength > 0 else {
            return 0
        }
        let offset = max(page.startAbsoluteOffset - chapter.startOffset, 0)
        return min(max(Double(offset) / Double(chapter.byteLength), 0), 1)
    }

    private func progressText(
        chapter: Chapter,
        chapterProgress: Double,
        globalProgress: Double
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.format", comment: ""),
            chapter.title,
            ReadingProgressFormatter.percentString(from: chapterProgress),
            ReadingProgressFormatter.percentString(from: globalProgress)
        )
    }

    private func progressTooltipText(
        chapterProgress: Double,
        pageIndex: Int
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.tooltip.format", comment: ""),
            ReadingProgressFormatter.tooltipPercentString(from: chapterProgress),
            pageIndex + 1
        )
    }

    private func updateProgressTooltip() {
        if let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) {
            updateProgressTooltip(target: target)
        } else if let currentPage,
                  let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset) {
            updateProgressTooltip(
                target: (
                    chapter: chapter,
                    chapterOffset: max(currentPage.startAbsoluteOffset - chapter.startOffset, 0),
                    chapterProgress: chapterProgress(for: currentPage, in: chapter),
                    pageIndex: currentPage.localPageIndex
                )
            )
        }
    }

    private func updateProgressTooltip(
        target: (chapter: Chapter, chapterOffset: Int, chapterProgress: Double, pageIndex: Int)
    ) {
        progressTooltipLabel.text = progressTooltipText(
            chapterProgress: target.chapterProgress,
            pageIndex: target.pageIndex
        )
    }

    private func setProgressTooltipVisible(_ visible: Bool) {
        if visible {
            progressTooltipView.isHidden = false
        }
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            self.progressTooltipView.alpha = visible ? 1 : 0
        } completion: { _ in
            if !visible {
                self.progressTooltipView.isHidden = true
            }
        }
    }

    func pageWidgetSnapshot(for page: CollectionReaderPage) -> ReaderPageWidgetSnapshot {
        ReaderPageWidgetSnapshot(
            chapterTitle: page.containsChapterTitle ? book.title : page.chapterTitle,
            batteryLevel: UIDevice.current.batteryLevel,
            batteryState: UIDevice.current.batteryState,
            timeText: Self.widgetTimeFormatter.string(from: Date()),
            pageProgressText: "\(page.localPageIndex + 1)/\(max(page.chapterPageCount, 1))",
            globalProgressText: ReadingProgressFormatter.percentString(from: page.globalProgress)
        )
    }

    func widgetLayoutConfiguration() -> ReaderWidgetLayoutConfiguration {
        let values = readerSettings.normalized.effectiveLayoutValues
        return ReaderWidgetLayoutConfiguration(
            horizontalMargin: CGFloat(values.widgetHorizontalMargin),
            bottomMargin: CGFloat(values.widgetBottomMargin),
            titleTopMargin: CGFloat(values.widgetTitleTopMargin),
            titleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
        )
    }

    func updateFixedWidgetOverlay() {
        guard usesVerticalScrolling,
              let currentPage else {
            fixedWidgetOverlay.isHidden = true
            return
        }

        fixedWidgetOverlay.isHidden = false
        fixedWidgetOverlay.configure(
            snapshot: pageWidgetSnapshot(for: currentPage),
            settings: readerSettings.normalized,
            layout: widgetLayoutConfiguration()
        )
    }

    private func refreshBookmarkState() {
        guard let currentProgress else {
            currentBookmark = nil
            updateBookmarkButton()
            return
        }
        currentBookmark = bookmarks.first { bookmark in
            bookmark.chapterID == currentProgress.chapterID
                && abs(bookmark.offset - Int(currentProgress.chapterOffset)) < 12
        }
        updateBookmarkButton()
    }

    private func updateBookmarkButton() {
        let imageName = currentBookmark == nil ? "bookmark" : "bookmark.fill"
        bookmarkButton.setImage(UIImage(systemName: imageName), for: .normal)
        bookmarkButton.accessibilityLabel = NSLocalizedString(
            currentBookmark == nil ? "reader.bookmark.add" : "reader.bookmark.remove",
            comment: ""
        )
    }

    func scheduleProgressSave() {
        guard let progress = currentProgress else {
            return
        }
        saveGeneration += 1
        let generation = saveGeneration
        saveTask?.cancel()
        let repository = repository
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                try Task.checkCancellation()
                guard generation == saveGeneration else {
                    return
                }
                try await repository.saveReadingProgress(progress)
                await MainActor.run { [weak self] in
                    self?.didShowProgressSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reading progress: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.showProgressSaveErrorIfNeeded(error)
                }
            }
        }
    }

    func saveProgressImmediately() {
        guard let progress = currentProgress else {
            return
        }
        saveTask?.cancel()
        let repository = repository
        saveTask = Task { [weak self] in
            do {
                try await repository.saveReadingProgress(progress)
                await MainActor.run {
                    self?.didShowProgressSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reading progress immediately: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self?.showProgressSaveErrorIfNeeded(error)
                }
            }
        }
    }

    private func saveSettingsImmediately() {
        settingsSaveTask?.cancel()
        let settings = readerSettings.normalized
        let repository = repository
        settingsSaveTask = Task { [weak self] in
            do {
                try await repository.saveReaderSettings(settings)
                await MainActor.run {
                    self?.didShowSettingsSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reader settings immediately: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self?.showSettingsSaveErrorIfNeeded(error)
                }
            }
        }
    }

    func scheduleSettingsSave() {
        settingsSaveGeneration += 1
        let generation = settingsSaveGeneration
        settingsSaveTask?.cancel()
        let settings = readerSettings.normalized
        let repository = repository
        settingsSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                guard generation == settingsSaveGeneration else {
                    return
                }
                try await repository.saveReaderSettings(settings)
                await MainActor.run { [weak self] in
                    self?.didShowSettingsSaveError = false
                }
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to save reader settings: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.showSettingsSaveErrorIfNeeded(error)
                }
            }
        }
    }

    private func recordBookOpenedIfNeeded() {
        guard !didRecordOpenHistory,
              let progress = currentProgress else {
            return
        }
        didRecordOpenHistory = true
        openHistoryGeneration += 1
        let generation = openHistoryGeneration
        let repository = repository
        let bookID = book.id
        let historyDate = openedAt
        openHistoryTask?.cancel()
        openHistoryTask = Task { [weak self] in
            do {
                try await repository.saveReadingProgress(progress)
                try Task.checkCancellation()
                await MainActor.run {
                    self?.didShowProgressSaveError = false
                }
                try await repository.markBookOpened(id: bookID, at: historyDate)
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to record reading history: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self,
                          self.openHistoryGeneration == generation else {
                        return
                    }
                    self.didRecordOpenHistory = false
                    self.showError(error)
                }
            }
        }
    }

    private func showProgressSaveErrorIfNeeded(_ error: Error) {
        guard !didShowProgressSaveError else {
            return
        }
        didShowProgressSaveError = true
        showError(error)
    }

    private func showSettingsSaveErrorIfNeeded(_ error: Error) {
        guard !didShowSettingsSaveError else {
            return
        }
        didShowSettingsSaveError = true
        showError(error)
    }

    func applyReaderSettings(_ settings: ReaderSettings) {
        let oldSettings = readerSettings.normalized
        let nextSettings = settings.normalized
        let anchor = currentDisplayByteOffset()
        readerSettings = nextSettings
        updateReaderChromePreferences()
        applyTheme()
        configureCollectionViewForActiveSettings()
        collectionView.reloadData()
        scheduleSettingsSave()
        guard oldSettings.pageMode != nextSettings.pageMode
            || oldSettings.fontSize != nextSettings.fontSize
            || oldSettings.layoutPreset != nextSettings.layoutPreset
            || oldSettings.customLayoutValues != nextSettings.customLayoutValues
            || oldSettings.theme != nextSettings.theme
            || oldSettings.widgetVisibility != nextSettings.widgetVisibility else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: anchor, generation: pagingGeneration)
    }

    private func currentDisplayByteOffset() -> Int {
        updateCurrentPageFromVisiblePage()
        return currentPage?.startAbsoluteOffset ?? 0
    }

    func updateCurrentPageFromVisiblePage() {
        guard let visibleIndex = visiblePageIndex(),
              pages.indices.contains(visibleIndex) else {
            return
        }
        let page = pages[visibleIndex]
        guard currentPage != page else {
            return
        }
        currentPage = page
        updateCurrentProgress()
    }

    private func visiblePageIndex() -> Int? {
        guard !pages.isEmpty else {
            return nil
        }
        if usesVerticalScrolling {
            return visibleVerticalPageIndex()
        }
        let extent = pageExtentForCurrentMode()
        guard extent > 1 else {
            return nil
        }
        let rawIndex = collectionView.contentOffset.x / extent
        let visibleIndex = Int(round(rawIndex))
        return min(max(visibleIndex, 0), pages.count - 1)
    }

    private func visibleVerticalPageIndex() -> Int? {
        let y = collectionView.contentOffset.y
            + collectionView.contentInset.top
            + (isAutoReading ? autoReadPageHeight() * 0.5 : 0)
        var accumulatedHeight: CGFloat = 0

        for index in pages.indices {
            let pageHeight = verticalExtentForPage(at: index)
            if y < accumulatedHeight + pageHeight {
                return index
            }
            accumulatedHeight += pageHeight
        }

        return pages.indices.last
    }

    private func pageExtentForCurrentMode() -> CGFloat {
        if isAutoReading {
            return autoReadPageHeight()
        }
        return usesVerticalScrolling
            ? verticalContinuousPageHeight()
            : collectionView.bounds.width
    }

    func autoReadPageHeight() -> CGFloat {
        verticalContinuousPageHeight()
    }

    private func contentOffset(forPageAt index: Int) -> CGPoint {
        if usesVerticalScrolling {
            return CGPoint(
                x: 0,
                y: verticalOffset(forPageAt: index) - collectionView.contentInset.top
            )
        }
        return CGPoint(x: CGFloat(index) * pageExtentForCurrentMode(), y: 0)
    }

    private func verticalOffset(forPageAt index: Int) -> CGFloat {
        let safeIndex = min(max(index, 0), pages.count)
        return pages.prefix(safeIndex).reduce(CGFloat(0)) { result, page in
            result + verticalExtent(for: page)
        }
    }

    func verticalExtentForPage(at index: Int) -> CGFloat {
        guard pages.indices.contains(index) else {
            return verticalContinuousPageHeight()
        }
        return verticalExtent(for: pages[index])
    }

    private func verticalExtent(for page: CollectionReaderPage) -> CGFloat {
        max(1, page.verticalExtent)
    }

    private func scrollToPage(at index: Int, animated _: Bool) {
        guard pages.indices.contains(index) else {
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(contentOffset(forPageAt: index), animated: false)
        currentPage = pages[index]
        updateSessionState(isLoadingNextPage: pageTask != nil)
        prefetchPagesNearCurrent()
        scheduleProgressSave()
    }

    /// 计算当前 viewport 顶部第一个字符对应的绝对字节偏移。
    /// - paged / curl 模式:返回当前逻辑页的 `startAbsoluteOffset`(顶部就是该页第一行)。
    /// - scroll / autoRead 模式:在覆盖 viewport 顶部的那个 page 内按 (y/height) 线性插值。
    func topAnchorAbsoluteOffset() -> Int? {
        guard !pages.isEmpty else {
            return nil
        }
        if usesVerticalScrolling {
            let targetY = collectionView.contentOffset.y + collectionView.contentInset.top
            var accumulatedHeight: CGFloat = 0
            for index in pages.indices {
                let pageHeight = verticalExtentForPage(at: index)
                if targetY < accumulatedHeight + pageHeight {
                    let page = pages[index]
                    let localFrac: CGFloat
                    if pageHeight > 0 {
                        localFrac = max(0, min(1, (targetY - accumulatedHeight) / pageHeight))
                    } else {
                        localFrac = 0
                    }
                    let byteSpan = max(0, page.endAbsoluteOffset - page.startAbsoluteOffset)
                    let delta = Int((CGFloat(byteSpan) * localFrac).rounded(.down))
                    return page.startAbsoluteOffset + delta
                }
                accumulatedHeight += pageHeight
            }
            return pages.last?.startAbsoluteOffset
        } else {
            if let visibleIndex = visiblePageIndex(),
               pages.indices.contains(visibleIndex) {
                return pages[visibleIndex].startAbsoluteOffset
            }
            return pages.first?.startAbsoluteOffset
        }
    }

    /// 把指定的字节偏移对齐到 viewport 顶部。
    /// - paged / curl 模式:落到包含该 offset 的逻辑页(snap 到页边界)。
    /// - scroll / autoRead 模式:在该 page 内按线性比例精确定位。
    func alignViewport(toAbsoluteOffset offset: Int) {
        guard !pages.isEmpty else {
            return
        }
        collectionView.layoutIfNeeded()
        let resolvedIndex = pages.firstIndex(where: { offset >= $0.startAbsoluteOffset && offset < $0.endAbsoluteOffset })
            ?? pages.firstIndex(where: { $0.startAbsoluteOffset >= offset })
            ?? (pages.count - 1)
        let page = pages[resolvedIndex]

        if usesVerticalScrolling {
            let pageStartY = verticalOffset(forPageAt: resolvedIndex)
            let pageHeight = verticalExtent(for: page)
            let byteSpan = max(0, page.endAbsoluteOffset - page.startAbsoluteOffset)
            let localFrac: CGFloat
            if byteSpan > 0 {
                localFrac = max(0, min(1, CGFloat(offset - page.startAbsoluteOffset) / CGFloat(byteSpan)))
            } else {
                localFrac = 0
            }
            let rawY = pageStartY + localFrac * pageHeight - collectionView.contentInset.top
            let maxY = max(
                -collectionView.contentInset.top,
                collectionView.contentSize.height + collectionView.contentInset.bottom - collectionView.bounds.height
            )
            let clampedY = max(-collectionView.contentInset.top, min(rawY, maxY))
            collectionView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        } else {
            collectionView.setContentOffset(contentOffset(forPageAt: resolvedIndex), animated: false)
        }
        currentPage = page
        updateCurrentProgress()
        prefetchPagesNearCurrent()
    }

    func finishPageTurn() {
        flushPendingPageInsertions()
        snapToNearestHorizontalPageIfNeeded()
        updateCurrentPageFromVisiblePage()
        prefetchPagesNearCurrent()
        scheduleProgressSave()
    }

    func snapToNearestHorizontalPageIfNeeded() {
        guard !usesVerticalScrolling,
              !pages.isEmpty,
              let index = visiblePageIndex(),
              pages.indices.contains(index) else {
            return
        }

        let targetOffset = contentOffset(forPageAt: index)
        guard abs(collectionView.contentOffset.x - targetOffset.x) > 0.5
            || abs(collectionView.contentOffset.y - targetOffset.y) > 0.5 else {
            return
        }

        isApplyingProgrammaticScroll = true
        collectionView.setContentOffset(targetOffset, animated: false)
        isApplyingProgrammaticScroll = false
    }

    func moveToNextPage() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }
        let targetIndex = currentIndex + 1
        if pages.indices.contains(targetIndex) {
            turnToPage(at: targetIndex, direction: .next)
            return
        }
        loadNextPageIfNeeded(scrollAfterLoading: true)
    }

    func moveToPreviousPage() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }
        let targetIndex = currentIndex - 1
        if pages.indices.contains(targetIndex) {
            turnToPage(at: targetIndex, direction: .previous)
            return
        }
        loadPreviousPageIfNeeded(scrollAfterLoading: true)
    }

    private func turnToPage(at index: Int, direction: TapPageDirection) {
        guard readerSettings.pageMode == .curl,
              !isAutoReading else {
            scrollToPage(at: index, animated: false)
            return
        }
        curlToPage(at: index, direction: direction)
    }

    private func curlToPage(at index: Int, direction: TapPageDirection) {
        guard pages.indices.contains(index) else {
            return
        }
        let transition: UIView.AnimationOptions = direction == .next
            ? .transitionCurlUp
            : .transitionCurlDown
        UIView.transition(
            with: collectionView,
            duration: 0.42,
            options: [transition, .curveEaseInOut, .allowUserInteraction],
            animations: {
                self.scrollToPage(at: index, animated: false)
            }
        )
    }

    func alignContentOffsetToCurrentPage() {
        guard let currentPage,
              let index = pages.firstIndex(of: currentPage) else {
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(contentOffset(forPageAt: index), animated: false)
    }

    private func targetProgressInCurrentChapter(
        progress: Double
    ) -> (chapter: Chapter, chapterOffset: Int, chapterProgress: Double, pageIndex: Int)? {
        guard let currentPage,
              let chapter = chapter(containingAbsoluteOffset: currentPage.startAbsoluteOffset)
        else {
            return nil
        }

        let chapterProgress = min(max(progress, 0), 1)
        let maxOffset = max(chapter.byteLength - 1, 0)
        let chapterOffset = min(
            max(Int((Double(chapter.byteLength) * chapterProgress).rounded(.down)), 0),
            maxOffset
        )
        let estimatedPageIndex = pageIndex(
            containingChapterOffset: chapterOffset,
            in: currentPage
        )
        return (
            chapter: chapter,
            chapterOffset: chapterOffset,
            chapterProgress: chapterProgress,
            pageIndex: estimatedPageIndex
        )
    }

    private func pageIndex(
        containingChapterOffset offset: Int,
        in page: CollectionReaderPage
    ) -> Int {
        let starts = page.chapterPageStartOffsets
        guard starts.isEmpty == false else {
            return min(max(page.localPageIndex, 0), max(page.chapterPageCount - 1, 0))
        }

        var lowerBound = 0
        var upperBound = starts.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if starts[middle] <= offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return min(max(lowerBound - 1, 0), max(starts.count - 1, 0))
    }

    private func chapter(containingAbsoluteOffset offset: Int) -> Chapter? {
        if let chapter = chapters.first(where: { offset >= $0.startOffset && offset < $0.endOffset }) {
            return chapter
        }
        return chapters.last
    }

    private func indexOfChapter(containingAbsoluteOffset offset: Int) -> Int? {
        chapters.firstIndex { offset >= $0.startOffset && offset < $0.endOffset }
    }

    private func bookmarkPreview(near absoluteOffset: Int) -> String {
        guard let page = currentPage else {
            return NSLocalizedString("reader.bookmark.preview.empty", comment: "")
        }
        return String(page.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    }

    func makeMoreMenu() -> UIMenu {
        UIMenu(
            children: [
                UIAction(
                    title: NSLocalizedString("reader.more.bookDetail", comment: ""),
                    image: UIImage(systemName: "book")
                ) { [weak self] _ in
                    self?.showBookDetail()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.contentSearch", comment: ""),
                    image: UIImage(systemName: "magnifyingglass")
                ) { [weak self] _ in
                    self?.showContentSearch()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.contentFilter", comment: ""),
                    image: UIImage(systemName: "line.3.horizontal.decrease.circle")
                ) { [weak self] _ in
                    self?.showFilterRules()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.pageTouchAreas", comment: ""),
                    image: UIImage(systemName: "square.grid.3x3")
                ) { [weak self] _ in
                    self?.showPageTouchAreas()
                }
            ]
        )
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

    private func showError(_ error: Error) {
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
        stopAutoReading(restoreLayout: false, animated: false)
        saveProgressImmediately()
        saveSettingsImmediately()
        closeReader(animated: true)
    }

    @objc func bookmarkButtonTapped() {
        guard let currentProgress,
              let chapter = chapter(containingAbsoluteOffset: currentDisplayByteOffset()) else {
            return
        }

        if let currentBookmark {
            let removedBookmark = currentBookmark
            let removedBookmarkIndex = bookmarks.firstIndex { $0.id == removedBookmark.id } ?? 0
            bookmarkTask?.cancel()
            self.currentBookmark = nil
            bookmarks.removeAll { $0.id == removedBookmark.id }
            bookmarkButton.isEnabled = false
            updateBookmarkButton()
            let repository = repository
            bookmarkTask = Task { [weak self] in
                do {
                    try await repository.deleteBookmark(id: removedBookmark.id)
                    await MainActor.run {
                        self?.bookmarkButton.isEnabled = true
                        self?.refreshBookmarkState()
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.bookmarkButton.isEnabled = true
                        self?.refreshBookmarkState()
                    }
                } catch {
                    readerLogger.error("Failed to delete bookmark: \(error.localizedDescription, privacy: .public)")
                    await MainActor.run {
                        guard let self else {
                            return
                        }
                        self.bookmarks.removeAll { $0.id == removedBookmark.id }
                        self.bookmarks.insert(
                            removedBookmark,
                            at: min(removedBookmarkIndex, self.bookmarks.count)
                        )
                        self.bookmarkButton.isEnabled = true
                        self.refreshBookmarkState()
                        self.showError(error)
                    }
                }
            }
            return
        }

        let offset = Int(currentProgress.chapterOffset)
        let preview = bookmarkPreview(near: currentDisplayByteOffset())
        let repository = repository
        let bookID = book.id
        bookmarkButton.isEnabled = false
        bookmarkTask?.cancel()
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
                    self.bookmarkButton.isEnabled = true
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarks.insert(bookmark, at: 0)
                    self.refreshBookmarkState()
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.bookmarkButton.isEnabled = true
                }
            } catch {
                readerLogger.error("Failed to create bookmark: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarkButton.isEnabled = true
                    self.refreshBookmarkState()
                    self.showError(error)
                }
            }
        }
    }

    @objc func catalogButtonTapped() {
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

    @objc func settingsButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        setMenuVisible(false, animated: true)
        setSettingsPanelVisible(true, animated: true)
    }

    @objc func previousChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index - 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index - 1].startOffset, generation: pagingGeneration)
    }

    @objc func nextChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index + 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index + 1].startOffset, generation: pagingGeneration)
    }

    @objc func progressSliderTouchBegan() {
        stopAutoReading(restoreLayout: true, animated: true)
        isTrackingProgressSlider = true
    }

    @objc func progressSliderChanged() {
        guard let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) else {
            return
        }
        let total = max(chapters.last?.endOffset ?? target.chapter.endOffset, 1)
        let absoluteOffset = target.chapter.startOffset + target.chapterOffset
        let globalProgress = min(max(Double(absoluteOffset) / Double(total), 0), 1)
        progressLabel.text = progressText(
            chapter: target.chapter,
            chapterProgress: target.chapterProgress,
            globalProgress: globalProgress
        )
        updateProgressTooltip(target: target)
        setProgressTooltipVisible(true)
    }

    @objc func progressSliderTouchFinished() {
        isTrackingProgressSlider = false
        setProgressTooltipVisible(false)
        guard let target = targetProgressInCurrentChapter(progress: Double(progressSlider.value)) else {
            return
        }
        pagingGeneration += 1
        openPage(
            absoluteOffset: target.chapter.startOffset + target.chapterOffset,
            generation: pagingGeneration,
            showsLoadingIndicator: false
        )
    }

    @objc private func settingsQuickModeChanged() {
        settingsQuickMode = SettingsQuickMode(rawValue: settingsQuickControl.selectedSegmentIndex) ?? .page
        updateSettingsQuickSection()
    }

    @objc private func settingsPageModeChanged() {
        guard let pageMode = ReaderSettings.PageMode(settingsPageTurnIndex: settingsPageModeControl.selectedSegmentIndex) else {
            return
        }
        var settings = readerSettings
        settings.pageMode = pageMode
        applyReaderSettings(settings)
    }

    @objc private func settingsThemeChanged() {
        let index = settingsThemeControl.selectedSegmentIndex
        guard ReaderSettings.Theme.allCases.indices.contains(index) else {
            return
        }
        var settings = readerSettings
        settings.theme = ReaderSettings.Theme.allCases[index]
        applyReaderSettings(settings)
    }

    @objc private func settingsLayoutPresetChanged() {
        let index = settingsLayoutPresetControl.selectedSegmentIndex
        guard ReaderSettings.LayoutPreset.allCases.indices.contains(index) else {
            return
        }
        var settings = readerSettings
        settings.layoutPreset = ReaderSettings.LayoutPreset.allCases[index]
        if settings.layoutPreset == .custom,
           settings.customLayoutValues == nil {
            settings.customLayoutValues = readerSettings.normalized.effectiveLayoutValues
        }
        applyReaderSettings(settings)
    }

    @objc private func layoutAdjustmentButtonTapped(_ sender: LayoutAdjustmentButton) {
        var settings = readerSettings.normalized
        var values = settings.effectiveLayoutValues
        sender.adjustment.apply(delta: sender.delta, to: &values)
        settings.layoutPreset = .custom
        settings.customLayoutValues = values
        applyReaderSettings(settings)
    }

    @objc private func keepScreenAwakeChanged() {
        var settings = readerSettings
        settings.keepScreenAwake = keepScreenAwakeSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func autoHideHomeIndicatorChanged() {
        var settings = readerSettings
        settings.autoHideHomeIndicator = autoHideHomeIndicatorSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func autoHideStatusBarChanged() {
        var settings = readerSettings
        settings.autoHideStatusBar = autoHideStatusBarSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func edgeSwipeBackChanged() {
        var settings = readerSettings
        settings.edgeSwipeBackEnabled = edgeSwipeBackSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetChapterTitleChanged() {
        var settings = readerSettings
        settings.widgetVisibility.chapterTitle = widgetChapterTitleSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetBatteryPercentageChanged() {
        var settings = readerSettings
        settings.widgetVisibility.batteryPercentage = widgetBatteryPercentageSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetBatteryIconChanged() {
        var settings = readerSettings
        settings.widgetVisibility.batteryIcon = widgetBatteryIconSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetTimeChanged() {
        var settings = readerSettings
        settings.widgetVisibility.time = widgetTimeSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetChapterPageProgressChanged() {
        var settings = readerSettings
        settings.widgetVisibility.chapterPageProgress = widgetChapterPageProgressSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func widgetGlobalProgressChanged() {
        var settings = readerSettings
        settings.widgetVisibility.globalProgress = widgetGlobalProgressSwitch.isOn
        applyReaderSettings(settings)
    }

    @objc private func settingsFontDecreaseTapped() {
        var settings = readerSettings
        settings.fontSize -= 1
        applyReaderSettings(settings)
    }

    @objc private func settingsFontIncreaseTapped() {
        var settings = readerSettings
        settings.fontSize += 1
        applyReaderSettings(settings)
    }

    @objc private func settingsFontResetTapped() {
        var settings = readerSettings
        settings.fontSize = ReaderSettings.default.fontSize
        applyReaderSettings(settings)
    }

    @objc private func appDidEnterBackground() {
        pauseAutoReadingForBackground()
        saveProgressImmediately()
    }

    @objc private func appDidBecomeActive() {
        resumeAutoReadingAfterBackgroundIfNeeded()
    }

    @objc private func showBookDetail() {
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

    @objc private func showContentSearch() {
        stopAutoReading(restoreLayout: true, animated: false)
        let searchViewController = ReaderContentSearchViewController(
            book: book,
            fileStore: fileStore,
            chapters: chapters,
            filterRules: filterRules
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpTo(target)
            self.popBackToReader(animated: true)
        }
        pushReaderPage(searchViewController)
    }

    @objc private func showFilterRules() {
        stopAutoReading(restoreLayout: true, animated: false)
        let filterViewController = ReaderFilterRulesViewController(
            bookID: book.id,
            repository: repository,
            rules: filterRules
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

    @objc private func showPageTouchAreas() {
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
