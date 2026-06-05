import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

private let readerLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
    category: "Reader"
)

private final class ReaderSettingsPanelScrollView: UIScrollView {
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
    private let onStatusBarHiddenChange: (Bool) -> Void
    private let collectionView: UICollectionView
    private let verticalTopCoverView = UIView()
    private let verticalBottomCoverView = UIView()
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleLabel = UILabel()
    private let bookmarkButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let progressLabel = UILabel()
    private let progressSlider = ReaderProgressSlider()
    private let progressTooltipView = UIView()
    private let progressTooltipLabel = UILabel()
    private let previousChapterButton = UIButton(type: .system)
    private let nextChapterButton = UIButton(type: .system)
    private let catalogButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let floatingActionStack = UIStackView()
    private let autoReadButton = UIButton(type: .system)
    private let darkModeButton = UIButton(type: .system)
    private let autoReadPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let autoReadSpeedSlider = UISlider()
    private let autoReadExitButton = UIButton(type: .system)
    private let settingsPanel = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
    private let settingsPanelScrollView = ReaderSettingsPanelScrollView()
    private let settingsPanelStack = UIStackView()
    private let settingsFontDecreaseButton = UIButton(type: .system)
    private let settingsFontValueButton = UIButton(type: .system)
    private let settingsFontIncreaseButton = UIButton(type: .system)
    private var layoutValueLabels: [LayoutAdjustment: UILabel] = [:]
    private let fixedWidgetOverlay = ReaderPageWidgetOverlayView()
    private let widgetChapterTitleSwitch = UISwitch()
    private let widgetBatteryPercentageSwitch = UISwitch()
    private let widgetBatteryIconSwitch = UISwitch()
    private let widgetTimeSwitch = UISwitch()
    private let widgetChapterPageProgressSwitch = UISwitch()
    private let widgetGlobalProgressSwitch = UISwitch()
    private var settingsControlPanRecognizers: [UIPanGestureRecognizer] = []
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
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private enum Layout {
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

    private enum MenuStyle {
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

    private var book: Book
    private var chapters: [Chapter] = []
    private var bookmarks: [Bookmark] = []
    private var filterRules: [TextFilterRule] = []
    private var pages: [CollectionReaderPage] = []
    private var currentPage: CollectionReaderPage?
    private var currentProgress: ReadingProgress?
    private var currentBookmark: Bookmark?
    private var readerSettings = ReaderSettings.default
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
    private var isMenuVisible = false
    private var isSettingsPanelVisible = false
    private var isAutoReading = false
    private var isAutoReadingPausedForBackground = false
    private var isAutoReadingPausedForInteractiveReturn = false
    private var isAutoReadPanelVisible = false
    private var isTrackingProgressSlider = false
    private var isApplyingProgrammaticScroll = false
    private var didStartOpening = false
    private var didReachEndOfBook = false
    private var isLoadingNextPage = false
    private var pendingTapTargetPageIndex: Int?
    private var pendingRestoreAbsoluteOffset: Int?
    private var previousBatteryMonitoringEnabled = false
    private var autoReadDisplayLink: CADisplayLink?
    private var lastAutoReadTimestamp: CFTimeInterval?
    private var lastAutoReadProgressUpdateTimestamp: CFTimeInterval = 0
    private var autoReadVelocity: CGFloat = 0
    private var shouldSuppressNextAutoReadTap = false
    private weak var autoReadTouchResetGesture: UIGestureRecognizer?
    private weak var edgeBackGesture: UIScreenEdgePanGestureRecognizer?
    private weak var configuredInteractivePopGesture: UIGestureRecognizer?
    private static let autoReadForwardInertiaDecayConstant: CGFloat = 2.5
    private static let autoReadReverseInertiaDecayConstant: CGFloat = 2.5
    private var lastViewportSize = CGSize.zero
    private weak var settingsPageModeSection: UIView?
    private weak var settingsLayoutSection: UIView?
    private weak var settingsMoreSection: UIView?

    private var usesVerticalScrolling: Bool {
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

    private var shouldHideSystemStatusBar: Bool {
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

        let size = collectionView.bounds.size
        guard didStartOpening,
              size.width > 1,
              size.height > 1,
              (
                abs(size.width - lastViewportSize.width) > 1
                    || abs(size.height - lastViewportSize.height) > 1
              )
        else {
            return
        }

        lastViewportSize = size
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

    private func configureVerticalContentCovers() {
        [verticalTopCoverView, verticalBottomCoverView].forEach { coverView in
            coverView.isUserInteractionEnabled = false
            coverView.isHidden = true
            view.addSubview(coverView)
        }
    }

    private func configureFixedWidgetOverlay() {
        fixedWidgetOverlay.translatesAutoresizingMaskIntoConstraints = false
        fixedWidgetOverlay.isUserInteractionEnabled = false
        fixedWidgetOverlay.isHidden = true
        view.addSubview(fixedWidgetOverlay)
        NSLayoutConstraint.activate([
            fixedWidgetOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            fixedWidgetOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fixedWidgetOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fixedWidgetOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func refreshReaderOverlayOrdering() {
        [
            verticalTopCoverView,
            verticalBottomCoverView,
            fixedWidgetOverlay,
            progressTooltipView,
            topBar,
            bottomBar,
            floatingActionStack,
            settingsPanel,
            autoReadPanel,
            loadingIndicator
        ].forEach { overlayView in
            guard overlayView.superview === view else {
                return
            }
            view.bringSubviewToFront(overlayView)
        }
    }

    private func configureMenus() {
        topBar.effect = nil
        topBar.backgroundColor = MenuStyle.barBackgroundColor
        topBar.contentView.backgroundColor = MenuStyle.barBackgroundColor
        bottomBar.effect = nil
        bottomBar.backgroundColor = MenuStyle.barBackgroundColor
        bottomBar.contentView.backgroundColor = MenuStyle.barBackgroundColor
        configureTopBar()
        configureBottomBar()
        configureProgressTooltip()
        configureFloatingActionButtons()
        configureSettingsPanel()
        configureAutoReadPanel()
        setMenuVisible(false, animated: false)
        setSettingsPanelVisible(false, animated: false)
        setAutoReadPanelVisible(false, animated: false)
    }

    private func configureTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        addMenuOverlay(to: topBar)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = MenuStyle.primaryTextColor
        closeButton.accessibilityLabel = NSLocalizedString("reader.close", comment: "")
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = MenuStyle.secondaryTextColor
        titleLabel.text = book.title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bookmarkButton.setImage(UIImage(systemName: "bookmark"), for: .normal)
        bookmarkButton.tintColor = MenuStyle.primaryTextColor
        bookmarkButton.accessibilityLabel = NSLocalizedString("reader.bookmark.add", comment: "")
        bookmarkButton.addTarget(self, action: #selector(bookmarkButtonTapped), for: .touchUpInside)
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = MenuStyle.primaryTextColor
        moreButton.accessibilityLabel = NSLocalizedString("reader.more", comment: "")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = UIStackView(arrangedSubviews: [bookmarkButton, moreButton])
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.spacing = 4
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        topBar.contentView.addSubview(closeButton)
        topBar.contentView.addSubview(titleLabel)
        topBar.contentView.addSubview(actionStack)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Layout.topBarContentHeight
            ),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 6),
            closeButton.bottomAnchor.constraint(
                equalTo: topBar.contentView.bottomAnchor,
                constant: -Layout.topBarButtonBottomInset
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),

            actionStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            actionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            bookmarkButton.widthAnchor.constraint(equalToConstant: 44),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        addMenuOverlay(to: bottomBar)

        previousChapterButton.setTitle(NSLocalizedString("reader.previousChapter", comment: ""), for: .normal)
        previousChapterButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        previousChapterButton.tintColor = MenuStyle.secondaryTextColor
        previousChapterButton.setTitleColor(MenuStyle.secondaryTextColor, for: .normal)
        previousChapterButton.setTitleColor(MenuStyle.primaryTextColor, for: .highlighted)
        previousChapterButton.accessibilityLabel = NSLocalizedString("reader.previousChapter", comment: "")
        previousChapterButton.addTarget(self, action: #selector(previousChapterButtonTapped), for: .touchUpInside)
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false

        nextChapterButton.setTitle(NSLocalizedString("reader.nextChapter", comment: ""), for: .normal)
        nextChapterButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        nextChapterButton.tintColor = MenuStyle.secondaryTextColor
        nextChapterButton.setTitleColor(MenuStyle.secondaryTextColor, for: .normal)
        nextChapterButton.setTitleColor(MenuStyle.primaryTextColor, for: .highlighted)
        nextChapterButton.accessibilityLabel = NSLocalizedString("reader.nextChapter", comment: "")
        nextChapterButton.addTarget(self, action: #selector(nextChapterButtonTapped), for: .touchUpInside)
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
        progressSlider.minimumTrackTintColor = MenuStyle.progressTintColor
        progressSlider.maximumTrackTintColor = MenuStyle.progressTrackColor
        progressSlider.thumbTintColor = MenuStyle.progressThumbColor
        progressSlider.setThumbImage(makeSliderThumbImage(diameter: 20), for: .normal)
        progressSlider.setThumbImage(makeSliderThumbImage(diameter: 20), for: .highlighted)
        progressSlider.accessibilityLabel = NSLocalizedString("reader.progress.slider", comment: "")
        progressSlider.addTarget(self, action: #selector(progressSliderTouchBegan), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(progressSliderChanged), for: .valueChanged)
        progressSlider.addTarget(
            self,
            action: #selector(progressSliderTouchFinished),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        progressSlider.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = .preferredFont(forTextStyle: .footnote)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textAlignment = .center
        progressLabel.textColor = MenuStyle.secondaryTextColor
        progressLabel.numberOfLines = 2
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        catalogButton.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        catalogButton.setTitle(NSLocalizedString("reader.catalog", comment: ""), for: .normal)
        configureBottomActionButton(catalogButton)
        catalogButton.accessibilityLabel = NSLocalizedString("reader.catalog", comment: "")
        catalogButton.addTarget(self, action: #selector(catalogButtonTapped), for: .touchUpInside)

        settingsButton.setImage(UIImage(systemName: "textformat"), for: .normal)
        settingsButton.setTitle(NSLocalizedString("reader.settings", comment: ""), for: .normal)
        configureBottomActionButton(settingsButton)
        settingsButton.accessibilityLabel = NSLocalizedString("reader.settings", comment: "")
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)

        let leftProgressSeparator = makeVerticalMenuSeparator()
        let rightProgressSeparator = makeVerticalMenuSeparator()
        let actionRowTopSeparator = makeHorizontalMenuSeparator()
        let progressSliderContainer = UIView()
        progressSliderContainer.translatesAutoresizingMaskIntoConstraints = false
        progressSliderContainer.addSubview(progressSlider)
        let progressRowContainer = UIView()
        progressRowContainer.backgroundColor = MenuStyle.progressRowBackgroundColor
        progressRowContainer.translatesAutoresizingMaskIntoConstraints = false
        let progressRow = UIStackView(arrangedSubviews: [
            previousChapterButton,
            leftProgressSeparator,
            progressSliderContainer,
            rightProgressSeparator,
            nextChapterButton
        ])
        progressRow.axis = .horizontal
        progressRow.alignment = .fill
        progressRow.spacing = 0
        progressRow.translatesAutoresizingMaskIntoConstraints = false

        let actionRow = UIStackView(arrangedSubviews: [catalogButton, settingsButton])
        actionRow.axis = .horizontal
        actionRow.alignment = .fill
        actionRow.distribution = .fillEqually
        actionRow.spacing = 0
        actionRow.backgroundColor = MenuStyle.barBackgroundColor
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.contentView.addSubview(progressRowContainer)
        progressRowContainer.addSubview(progressRow)
        bottomBar.contentView.addSubview(actionRowTopSeparator)
        bottomBar.contentView.addSubview(actionRow)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            progressRowContainer.topAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: Layout.bottomBarTopInset
            ),
            progressRowContainer.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            progressRowContainer.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            progressRowContainer.heightAnchor.constraint(equalToConstant: Layout.progressRowHeight),

            progressRow.leadingAnchor.constraint(equalTo: progressRowContainer.leadingAnchor),
            progressRow.trailingAnchor.constraint(equalTo: progressRowContainer.trailingAnchor),
            progressRow.topAnchor.constraint(equalTo: progressRowContainer.topAnchor),
            progressRow.bottomAnchor.constraint(equalTo: progressRowContainer.bottomAnchor),
            progressRow.heightAnchor.constraint(equalToConstant: Layout.progressRowHeight),

            previousChapterButton.widthAnchor.constraint(equalToConstant: Layout.chapterButtonWidth),
            leftProgressSeparator.widthAnchor.constraint(equalToConstant: 1),
            progressSlider.leadingAnchor.constraint(
                equalTo: progressSliderContainer.leadingAnchor,
                constant: Layout.progressSliderHorizontalInset
            ),
            progressSlider.trailingAnchor.constraint(
                equalTo: progressSliderContainer.trailingAnchor,
                constant: -Layout.progressSliderHorizontalInset
            ),
            progressSlider.centerYAnchor.constraint(equalTo: progressSliderContainer.centerYAnchor),
            rightProgressSeparator.widthAnchor.constraint(equalToConstant: 1),
            nextChapterButton.widthAnchor.constraint(equalToConstant: Layout.chapterButtonWidth),

            actionRowTopSeparator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            actionRowTopSeparator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            actionRowTopSeparator.topAnchor.constraint(equalTo: progressRowContainer.bottomAnchor),
            actionRowTopSeparator.heightAnchor.constraint(equalToConstant: Layout.menuSeparatorThickness),

            actionRow.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            actionRow.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            actionRow.topAnchor.constraint(equalTo: actionRowTopSeparator.bottomAnchor),
            actionRow.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.bottomBarSafeAreaInset
            ),
            actionRow.heightAnchor.constraint(equalToConstant: Layout.bottomActionRowHeight)
        ])
    }

    private func configureProgressTooltip() {
        progressTooltipView.backgroundColor = MenuStyle.progressTooltipBackgroundColor
        progressTooltipView.layer.cornerRadius = 4
        progressTooltipView.layer.masksToBounds = true
        progressTooltipView.alpha = 0
        progressTooltipView.isHidden = true
        progressTooltipView.isUserInteractionEnabled = false
        progressTooltipView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressTooltipView)

        progressTooltipLabel.font = .systemFont(ofSize: 14, weight: .regular)
        progressTooltipLabel.textColor = .white
        progressTooltipLabel.textAlignment = .center
        progressTooltipLabel.numberOfLines = 1
        progressTooltipLabel.adjustsFontSizeToFitWidth = true
        progressTooltipLabel.minimumScaleFactor = 0.86
        progressTooltipLabel.translatesAutoresizingMaskIntoConstraints = false
        progressTooltipView.addSubview(progressTooltipLabel)

        NSLayoutConstraint.activate([
            progressTooltipView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressTooltipView.widthAnchor.constraint(equalToConstant: Layout.progressTooltipWidth),
            progressTooltipView.bottomAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: -Layout.progressTooltipBottomSpacing
            ),
            progressTooltipLabel.leadingAnchor.constraint(
                equalTo: progressTooltipView.leadingAnchor,
                constant: Layout.progressTooltipHorizontalPadding
            ),
            progressTooltipLabel.trailingAnchor.constraint(
                equalTo: progressTooltipView.trailingAnchor,
                constant: -Layout.progressTooltipHorizontalPadding
            ),
            progressTooltipLabel.topAnchor.constraint(
                equalTo: progressTooltipView.topAnchor,
                constant: Layout.progressTooltipVerticalPadding
            ),
            progressTooltipLabel.bottomAnchor.constraint(
                equalTo: progressTooltipView.bottomAnchor,
                constant: -Layout.progressTooltipVerticalPadding
            )
        ])
    }

    private func configureFloatingActionButtons() {
        floatingActionStack.axis = .vertical
        floatingActionStack.alignment = .center
        floatingActionStack.distribution = .fill
        floatingActionStack.spacing = Layout.floatingButtonSpacing
        floatingActionStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingActionStack)

        configureFloatingButton(autoReadButton, systemName: "circle", titleKey: "reader.autoRead.placeholder")
        autoReadButton.addTarget(self, action: #selector(autoReadButtonTapped), for: .touchUpInside)

        configureFloatingButton(darkModeButton, systemName: "moon.stars", titleKey: "reader.darkMode.placeholder")
        darkModeButton.addTarget(self, action: #selector(darkModeButtonTapped), for: .touchUpInside)

        floatingActionStack.addArrangedSubview(autoReadButton)
        floatingActionStack.addArrangedSubview(darkModeButton)

        NSLayoutConstraint.activate([
            floatingActionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Layout.floatingButtonTrailingInset),
            floatingActionStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -Layout.floatingButtonBottomInset),
            autoReadButton.widthAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            autoReadButton.heightAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            darkModeButton.widthAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            darkModeButton.heightAnchor.constraint(equalToConstant: Layout.floatingButtonSize)
        ])
    }

    private func configureFloatingButton(_ button: UIButton, systemName: String, titleKey: String) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        button.tintColor = MenuStyle.floatingButtonIconColor
        button.backgroundColor = MenuStyle.floatingButtonColor
        button.layer.cornerRadius = Layout.floatingButtonSize / 2
        button.layer.masksToBounds = true
        button.accessibilityLabel = NSLocalizedString(titleKey, comment: "")
        button.isUserInteractionEnabled = true
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func addMenuOverlay(to visualEffectView: UIVisualEffectView) {
        let overlayView = UIView()
        overlayView.backgroundColor = MenuStyle.barBackgroundColor
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false
        visualEffectView.contentView.insertSubview(overlayView, at: 0)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: visualEffectView.contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: visualEffectView.contentView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: visualEffectView.contentView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: visualEffectView.contentView.bottomAnchor)
        ])
    }

    private func makeVerticalMenuSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = MenuStyle.separatorColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    private func makeHorizontalMenuSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = MenuStyle.separatorColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        let edgeView = UIView()
        edgeView.backgroundColor = MenuStyle.separatorEdgeColor
        edgeView.translatesAutoresizingMaskIntoConstraints = false
        separator.addSubview(edgeView)
        NSLayoutConstraint.activate([
            edgeView.leadingAnchor.constraint(equalTo: separator.leadingAnchor),
            edgeView.trailingAnchor.constraint(equalTo: separator.trailingAnchor),
            edgeView.bottomAnchor.constraint(equalTo: separator.bottomAnchor),
            edgeView.heightAnchor.constraint(equalToConstant: 1)
        ])
        return separator
    }

    private func configureBottomActionButton(_ button: UIButton) {
        button.tintColor = MenuStyle.secondaryTextColor
        button.setTitleColor(MenuStyle.secondaryTextColor, for: .normal)
        button.setTitleColor(MenuStyle.primaryTextColor, for: .highlighted)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.textAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        button.alignImageAboveTitle(spacing: 4)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeSliderThumbImage(diameter: CGFloat) -> UIImage {
        let size = CGSize(
            width: Layout.progressThumbHitboxDiameter,
            height: Layout.progressThumbHitboxDiameter
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let origin = CGPoint(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2
            )
            let bounds = CGRect(
                x: origin.x,
                y: origin.y,
                width: diameter,
                height: diameter
            )
            let cgContext = context.cgContext

            MenuStyle.progressThumbEdgeShadowColor.setStroke()
            cgContext.setLineWidth(1)
            cgContext.strokeEllipse(in: bounds.offsetBy(dx: 0, dy: 1).insetBy(dx: 0.5, dy: 0.5))
            MenuStyle.progressThumbColor.setFill()
            cgContext.fillEllipse(in: bounds)

            MenuStyle.progressThumbBorderColor.setStroke()
            cgContext.setLineWidth(1)
            cgContext.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func makeAutoReadSliderThumbImage(diameter: CGFloat) -> UIImage {
        let shadowPadding: CGFloat = 4
        let size = CGSize(
            width: diameter + shadowPadding * 2,
            height: diameter + shadowPadding * 2
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(
                x: shadowPadding,
                y: shadowPadding,
                width: diameter,
                height: diameter
            )
            let cgContext = context.cgContext
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.36).cgColor
            )

            UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1).setFill()
            cgContext.fillEllipse(in: bounds)
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            MenuStyle.progressThumbColor.setFill()
            cgContext.fillEllipse(in: bounds.insetBy(dx: 3, dy: 3))

            UIColor(white: 0.64, alpha: 0.36).setFill()
            cgContext.fillEllipse(
                in: CGRect(
                    x: bounds.minX + diameter * 0.31,
                    y: bounds.minY + diameter * 0.24,
                    width: diameter * 0.38,
                    height: diameter * 0.18
                )
            )

            UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1).setStroke()
            cgContext.setLineWidth(1)
            cgContext.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    private func configureSettingsPanel() {
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

    private func configureAutoReadPanel() {
        autoReadPanel.translatesAutoresizingMaskIntoConstraints = false
        autoReadPanel.effect = nil
        autoReadPanel.backgroundColor = MenuStyle.barBackgroundColor
        autoReadPanel.contentView.backgroundColor = MenuStyle.barBackgroundColor
        autoReadPanel.isUserInteractionEnabled = false
        autoReadPanel.transform = CGAffineTransform(
            translationX: 0,
            y: Layout.autoReadPanelHeight + 1
        )
        view.addSubview(autoReadPanel)

        autoReadSpeedSlider.minimumValue = Float(ReaderSettings.minimumAutoReadSpeed)
        autoReadSpeedSlider.maximumValue = Float(ReaderSettings.maximumAutoReadSpeed)
        autoReadSpeedSlider.value = Float(readerSettings.autoReadSpeed)
        autoReadSpeedSlider.minimumTrackTintColor = MenuStyle.progressTintColor
        autoReadSpeedSlider.maximumTrackTintColor = MenuStyle.progressTrackColor
        autoReadSpeedSlider.thumbTintColor = MenuStyle.progressThumbColor
        autoReadSpeedSlider.setThumbImage(makeAutoReadSliderThumbImage(diameter: 24), for: .normal)
        autoReadSpeedSlider.setThumbImage(makeAutoReadSliderThumbImage(diameter: 28), for: .highlighted)
        autoReadSpeedSlider.accessibilityLabel = NSLocalizedString("reader.autoRead.speed", comment: "")
        autoReadSpeedSlider.addTarget(self, action: #selector(autoReadSpeedChanged), for: .valueChanged)
        autoReadSpeedSlider.translatesAutoresizingMaskIntoConstraints = false

        autoReadExitButton.setTitle(NSLocalizedString("reader.autoRead.exit", comment: ""), for: .normal)
        autoReadExitButton.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
        autoReadExitButton.setTitleColor(MenuStyle.secondaryTextColor, for: .highlighted)
        autoReadExitButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        autoReadExitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        autoReadExitButton.backgroundColor = MenuStyle.settingsControlBackgroundColor
        autoReadExitButton.layer.cornerRadius = Layout.autoReadExitButtonHeight / 2
        autoReadExitButton.layer.masksToBounds = true
        autoReadExitButton.addTarget(self, action: #selector(autoReadExitTapped), for: .touchUpInside)

        let speedRow = UIStackView(arrangedSubviews: [
            autoReadIcon(named: "tortoise.fill", fallbackName: "tortoise"),
            autoReadSpeedSlider,
            autoReadIcon(named: "hare.fill", fallbackName: "hare")
        ])
        speedRow.axis = .horizontal
        speedRow.alignment = .center
        speedRow.spacing = 14

        let stack = UIStackView(arrangedSubviews: [
            speedRow,
            autoReadExitButton
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        autoReadPanel.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            autoReadPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            autoReadPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            autoReadPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            autoReadPanel.heightAnchor.constraint(equalToConstant: Layout.autoReadPanelHeight),
            stack.leadingAnchor.constraint(equalTo: autoReadPanel.contentView.leadingAnchor, constant: Layout.autoReadPanelHorizontalInset),
            stack.trailingAnchor.constraint(equalTo: autoReadPanel.contentView.trailingAnchor, constant: -Layout.autoReadPanelHorizontalInset),
            stack.topAnchor.constraint(equalTo: autoReadPanel.contentView.topAnchor, constant: Layout.autoReadPanelTopInset),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.autoReadPanelBottomInset
            ),
            autoReadExitButton.heightAnchor.constraint(equalToConstant: Layout.autoReadExitButtonHeight)
        ])
    }

    private func autoReadIcon(named imageName: String, fallbackName: String) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: imageName) ?? UIImage(systemName: fallbackName))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Layout.autoReadIconSize,
            weight: .regular
        )
        imageView.tintColor = MenuStyle.secondaryTextColor
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Layout.autoReadIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.autoReadIconSize)
        ])
        return imageView
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
        guard collectionView.bounds.width > 1,
              collectionView.bounds.height > 1 else {
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
        let viewportSize = collectionView.bounds.size
        let safeAreaInsets = view.safeAreaInsets
        let widgetInsets = widgetContentInsets()
        let isVerticalViewport = usesVerticalScrolling
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

    private func loadNextPageIfNeeded(scrollAfterLoading: Bool = false) {
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

    private func loadPreviousPageIfNeeded(scrollAfterLoading: Bool = false) {
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
        let viewportSize = collectionView.bounds.size
        let safeAreaInsets = view.safeAreaInsets
        let widgetInsets = widgetContentInsets()
        let isVerticalViewport = usesVerticalScrolling
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
    private func flushPendingPageInsertions() {
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

    private func prefetchPagesNearCurrent() {
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

    private func configureCollectionViewForActiveSettings() {
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

    private func configureCollectionViewForAutoReading() {
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

    private func displayLayoutForCurrentMode() -> ReaderLayoutConfiguration {
        var layout = effectiveReaderLayout()
        if usesVerticalScrolling {
            layout.topMargin = 0
            layout.bottomMargin = 0
        }
        return layout
    }

    private func verticalContinuousInsets() -> UIEdgeInsets {
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

    private func updateVerticalContentCovers() {
        let insets = usesVerticalScrolling ? verticalContinuousInsets() : .zero
        verticalTopCoverView.backgroundColor = readerSettings.theme.backgroundColor
        verticalBottomCoverView.backgroundColor = readerSettings.theme.backgroundColor
        verticalTopCoverView.isHidden = insets.top <= 0
        verticalBottomCoverView.isHidden = insets.bottom <= 0
        verticalTopCoverView.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: max(0, insets.top)
        )
        verticalBottomCoverView.frame = CGRect(
            x: 0,
            y: max(0, view.bounds.height - max(0, insets.bottom)),
            width: view.bounds.width,
            height: max(0, insets.bottom)
        )
        refreshReaderOverlayOrdering()
    }

    private func applyTheme() {
        overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        view.backgroundColor = readerSettings.theme.backgroundColor
        collectionView.backgroundColor = readerSettings.theme.backgroundColor
        verticalTopCoverView.backgroundColor = readerSettings.theme.backgroundColor
        verticalBottomCoverView.backgroundColor = readerSettings.theme.backgroundColor
        fixedWidgetOverlay.backgroundColor = .clear
        loadingIndicator.color = readerSettings.theme.secondaryTextColor
        progressLabel.textColor = readerSettings.theme.secondaryTextColor
        updateDarkModeButton()
        updateAutoReadButton()
        updateFixedWidgetOverlay()
        refreshSystemStatusBarVisibility()
    }

    private func updateDarkModeButton() {
        let imageName = readerSettings.theme == .dark ? "sun.max.fill" : "moon.stars"
        darkModeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    private func updateAutoReadButton() {
        autoReadButton.setImage(UIImage(systemName: "circle"), for: .normal)
    }

    private func refreshSystemStatusBarVisibility() {
        let isHidden = shouldHideSystemStatusBar
        onStatusBarHiddenChange(isHidden)
        setNeedsStatusBarAppearanceUpdate()
        navigationController?.setNeedsStatusBarAppearanceUpdate()

        // 强制系统重新读取小横条隐藏状态和边缘手势延迟设置
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    private func updateReaderChromePreferences() {
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

    private func setMenuVisible(_ visible: Bool, animated: Bool) {
        isMenuVisible = visible
        topBar.isUserInteractionEnabled = visible
        bottomBar.isUserInteractionEnabled = visible
        floatingActionStack.isUserInteractionEnabled = visible
        refreshSystemStatusBarVisibility()
        view.layoutIfNeeded()
        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: {
                    self.applyMenuPosition(animated: true)
                }
            )
        } else {
            applyMenuPosition(animated: false)
        }
    }

    private func applyMenuPosition(animated _: Bool) {
        let topTranslation = -(topBar.bounds.height + 1)
        let bottomTranslation = bottomBar.bounds.height + 1
        let floatingHiddenOffset = floatingActionStack.bounds.width
            + Layout.floatingButtonTrailingInset
            + view.safeAreaInsets.right
            + 1
        topBar.transform = isMenuVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: topTranslation)
        bottomBar.transform = isMenuVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: bottomTranslation)
        floatingActionStack.transform = isMenuVisible
            ? .identity
            : CGAffineTransform(translationX: floatingHiddenOffset, y: 0)
    }

    private func setSettingsPanelVisible(_ visible: Bool, animated: Bool) {
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

    private func setAutoReadPanelVisible(_ visible: Bool, animated: Bool) {
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

    private func showLoading(_ isLoading: Bool) {
        if isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
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

    private func pageWidgetSnapshot(for page: CollectionReaderPage) -> ReaderPageWidgetSnapshot {
        ReaderPageWidgetSnapshot(
            chapterTitle: page.containsChapterTitle ? book.title : page.chapterTitle,
            batteryLevel: UIDevice.current.batteryLevel,
            batteryState: UIDevice.current.batteryState,
            timeText: Self.widgetTimeFormatter.string(from: Date()),
            pageProgressText: "\(page.localPageIndex + 1)/\(max(page.chapterPageCount, 1))",
            globalProgressText: ReadingProgressFormatter.percentString(from: page.globalProgress)
        )
    }

    private func widgetLayoutConfiguration() -> ReaderWidgetLayoutConfiguration {
        let values = readerSettings.normalized.effectiveLayoutValues
        return ReaderWidgetLayoutConfiguration(
            horizontalMargin: CGFloat(values.widgetHorizontalMargin),
            bottomMargin: CGFloat(values.widgetBottomMargin),
            titleTopMargin: CGFloat(values.widgetTitleTopMargin),
            titleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
        )
    }

    private func updateFixedWidgetOverlay() {
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

    private func scheduleProgressSave() {
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

    private func saveProgressImmediately() {
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

    private func scheduleSettingsSave() {
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

    private func applyReaderSettings(_ settings: ReaderSettings) {
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

    private func updateCurrentPageFromVisiblePage() {
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

    private func autoReadPageHeight() -> CGFloat {
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

    private func verticalExtentForPage(at index: Int) -> CGFloat {
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
    private func topAnchorAbsoluteOffset() -> Int? {
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
    private func alignViewport(toAbsoluteOffset offset: Int) {
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

    private func currentAutoReadBaseSpeed() -> CGFloat {
        let value = min(
            max(readerSettings.normalized.autoReadSpeed, ReaderSettings.minimumAutoReadSpeed),
            ReaderSettings.maximumAutoReadSpeed
        )
        return CGFloat(value)
    }

    private func isAutoReadVelocityAtBaseSpeed() -> Bool {
        guard isAutoReading else {
            return false
        }
        let baseSpeed = currentAutoReadBaseSpeed()
        let tolerance = max(baseSpeed * 0.02, 1)
        return abs(autoReadVelocity - baseSpeed) <= tolerance
    }

    private func resetAutoReadVelocityToBaseSpeed() {
        guard isAutoReading else {
            return
        }
        autoReadVelocity = currentAutoReadBaseSpeed()
        lastAutoReadTimestamp = nil
    }

    private func finishPageTurn() {
        flushPendingPageInsertions()
        snapToNearestHorizontalPageIfNeeded()
        updateCurrentPageFromVisiblePage()
        prefetchPagesNearCurrent()
        scheduleProgressSave()
    }

    private func snapToNearestHorizontalPageIfNeeded() {
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

    private func moveToNextPage() {
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

    private func moveToPreviousPage() {
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

    private func startAutoReading() {
        guard !isAutoReading else {
            setAutoReadPanelVisible(true, animated: true)
            return
        }
        guard !pages.isEmpty else {
            return
        }
        // 进入前在当前(paged / curl / scroll)布局下抓取顶部字节锚点;
        // 切到自动阅读垂直布局后用同一个锚点精确还原顶部第一行。
        let anchor = topAnchorAbsoluteOffset() ?? currentPage?.startAbsoluteOffset ?? 0
        setMenuVisible(false, animated: true)
        isAutoReading = true
        refreshSystemStatusBarVisibility()
        configureCollectionViewForAutoReading()
        collectionView.reloadData()
        alignViewport(toAbsoluteOffset: anchor)
        setAutoReadPanelVisible(false, animated: false)
        updateAutoReadButton()
        startAutoReadDisplayLink()
    }

    private func stopAutoReading(restoreLayout: Bool, animated: Bool) {
        guard isAutoReading || autoReadDisplayLink != nil else {
            return
        }
        // 先在自动阅读垂直布局下记录顶部锚点,然后再切回原模式;
        // 这样无论原模式是 paged / curl / scroll,都能落到锚点所在的位置。
        let anchor = topAnchorAbsoluteOffset()
        invalidateAutoReadDisplayLink()
        collectionView.layer.removeAllAnimations()
        isAutoReadingPausedForBackground = false
        isAutoReadingPausedForInteractiveReturn = false
        isAutoReading = false
        refreshSystemStatusBarVisibility()
        setAutoReadPanelVisible(false, animated: animated)
        updateAutoReadButton()
        if restoreLayout {
            configureCollectionViewForActiveSettings()
            collectionView.reloadData()
            if let anchor {
                alignViewport(toAbsoluteOffset: anchor)
            }
        } else {
            updateFixedWidgetOverlay()
        }
        saveProgressImmediately()
    }

    private func pauseAutoReadingForBackground() {
        guard isAutoReading else {
            return
        }
        invalidateAutoReadDisplayLink()
        collectionView.layer.removeAllAnimations()
        updateCurrentPageFromVisiblePage()
        setAutoReadPanelVisible(false, animated: false)
        isAutoReadingPausedForBackground = true
        refreshSystemStatusBarVisibility()
        saveProgressImmediately()
    }

    private func pauseAutoReadingForInteractiveReturn() {
        guard isAutoReading else {
            return
        }
        invalidateAutoReadDisplayLink()
        collectionView.layer.removeAllAnimations()
        updateCurrentPageFromVisiblePage()
        setAutoReadPanelVisible(false, animated: false)
        isAutoReadingPausedForInteractiveReturn = true
        refreshSystemStatusBarVisibility()
    }

    private func resumeAutoReadingAfterBackgroundIfNeeded() {
        guard isAutoReading,
              isAutoReadingPausedForBackground else {
            return
        }
        isAutoReadingPausedForBackground = false
        updateReaderChromePreferences()
        refreshSystemStatusBarVisibility()
        configureCollectionViewForAutoReading()
        collectionView.reloadData()
        alignContentOffsetToCurrentPage()
        updateAutoReadButton()
        startAutoReadDisplayLink()
    }

    private func resumeAutoReadingAfterInteractiveReturnCancellationIfNeeded() {
        guard isAutoReading,
              isAutoReadingPausedForInteractiveReturn else {
            return
        }
        isAutoReadingPausedForInteractiveReturn = false
        updateReaderChromePreferences()
        refreshSystemStatusBarVisibility()
        updateFixedWidgetOverlay()
        updateAutoReadButton()
        startAutoReadDisplayLink()
    }

    private func finishAutoReadingAfterInteractiveReturnCompletion() {
        guard isAutoReading || autoReadDisplayLink != nil || isAutoReadingPausedForInteractiveReturn else {
            return
        }
        invalidateAutoReadDisplayLink()
        collectionView.layer.removeAllAnimations()
        isAutoReadingPausedForInteractiveReturn = false
        isAutoReadingPausedForBackground = false
        isAutoReading = false
        setAutoReadPanelVisible(false, animated: false)
        updateAutoReadButton()
        refreshSystemStatusBarVisibility()
    }

    private func alignContentOffsetToCurrentPage() {
        guard let currentPage,
              let index = pages.firstIndex(of: currentPage) else {
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(contentOffset(forPageAt: index), animated: false)
    }

    private func startAutoReadDisplayLink() {
        invalidateAutoReadDisplayLink()
        lastAutoReadTimestamp = nil
        lastAutoReadProgressUpdateTimestamp = 0
        autoReadVelocity = currentAutoReadBaseSpeed()
        let displayLink = CADisplayLink(target: self, selector: #selector(autoReadDisplayLinkDidTick(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .common)
        autoReadDisplayLink = displayLink
    }

    private func invalidateAutoReadDisplayLink() {
        autoReadDisplayLink?.invalidate()
        autoReadDisplayLink = nil
        lastAutoReadTimestamp = nil
    }

    @objc private func autoReadDisplayLinkDidTick(_ displayLink: CADisplayLink) {
        guard isAutoReading else {
            invalidateAutoReadDisplayLink()
            return
        }
        let previous = lastAutoReadTimestamp ?? displayLink.timestamp
        let interval = max(0, min(1.0 / 15.0, displayLink.timestamp - previous))
        lastAutoReadTimestamp = displayLink.timestamp
        advanceAutoRead(by: interval)
    }

    private func advanceAutoRead(by interval: TimeInterval) {
        guard isAutoReading,
              !collectionView.isDragging,
              !collectionView.isTracking else {
            return
        }
        let baseSpeed = currentAutoReadBaseSpeed()
        // 指数衰减,把当前速度朝目标收敛:
        //   向下(velocity >= 0):目标 = baseSpeed,形成"快速 → 减速 → 匀速"。
        //   向上(velocity < 0):目标 = 0,反向惯性衰减到接近停止后立即切回向下匀速。
        let target: CGFloat = autoReadVelocity >= 0 ? baseSpeed : 0
        let decayConstant = autoReadVelocity < 0
            ? Self.autoReadReverseInertiaDecayConstant
            : Self.autoReadForwardInertiaDecayConstant
        let decay = CGFloat(exp(-Double(decayConstant) * interval))
        autoReadVelocity = target + (autoReadVelocity - target) * decay
        let reverseResumeThreshold = max(baseSpeed * 0.05, 6)
        if autoReadVelocity < 0, abs(autoReadVelocity) <= reverseResumeThreshold {
            // 反向惯性收敛到 0,接力到向下匀速。
            autoReadVelocity = baseSpeed
        } else if autoReadVelocity > 0, abs(autoReadVelocity - baseSpeed) < 0.5 {
            autoReadVelocity = baseSpeed
        }
        let distance = autoReadVelocity * CGFloat(interval)
        if distance == 0 {
            return
        }
        let minOffsetY = -collectionView.contentInset.top
        let maxOffsetY = max(
            minOffsetY,
            collectionView.contentSize.height + collectionView.contentInset.bottom - collectionView.bounds.height
        )
        let proposedY = collectionView.contentOffset.y + distance
        let nextOffsetY = max(minOffsetY, min(maxOffsetY, proposedY))
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: nextOffsetY),
            animated: false
        )
        updateCurrentPageFromVisiblePage()
        if displayNeedsProgressSave() {
            scheduleProgressSave()
        }
        if distance > 0,
           nextOffsetY >= max(minOffsetY, maxOffsetY - autoReadPageHeight() * 1.6) {
            loadNextPageIfNeeded()
        }
        if distance < 0,
           nextOffsetY <= minOffsetY + autoReadPageHeight() * 1.6 {
            loadPreviousPageIfNeeded()
        }
        if nextOffsetY >= maxOffsetY,
           distance > 0,
           (didReachEndOfBook || (pages.last?.endAbsoluteOffset ?? 0) >= (chapters.last?.endOffset ?? 0)) {
            stopAutoReading(restoreLayout: true, animated: true)
        }
    }

    private func displayNeedsProgressSave() -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastAutoReadProgressUpdateTimestamp >= 0.35 else {
            return false
        }
        lastAutoReadProgressUpdateTimestamp = now
        return true
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

    private func makeMoreMenu() -> UIMenu {
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

    @objc private func closeButtonTapped() {
        stopAutoReading(restoreLayout: false, animated: false)
        saveProgressImmediately()
        saveSettingsImmediately()
        closeReader(animated: true)
    }

    @objc private func bookmarkButtonTapped() {
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

    @objc private func catalogButtonTapped() {
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

    @objc private func settingsButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        setMenuVisible(false, animated: true)
        setSettingsPanelVisible(true, animated: true)
    }

    @objc private func previousChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index - 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index - 1].startOffset, generation: pagingGeneration)
    }

    @objc private func nextChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index + 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index + 1].startOffset, generation: pagingGeneration)
    }

    @objc private func autoReadButtonTapped() {
        if isAutoReading {
            setAutoReadPanelVisible(!isAutoReadPanelVisible, animated: true)
        } else {
            startAutoReading()
        }
    }

    @objc private func darkModeButtonTapped() {
        var settings = readerSettings
        settings.theme = settings.theme == .dark ? .white : .dark
        applyReaderSettings(settings)
    }

    @objc private func autoReadSpeedChanged() {
        var settings = readerSettings
        settings.autoReadSpeed = Double(autoReadSpeedSlider.value)
        readerSettings = settings.normalized
        scheduleSettingsSave()
    }

    @objc private func autoReadExitTapped() {
        stopAutoReading(restoreLayout: true, animated: true)
    }

    @objc private func progressSliderTouchBegan() {
        stopAutoReading(restoreLayout: true, animated: true)
        isTrackingProgressSlider = true
    }

    @objc private func progressSliderChanged() {
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

    @objc private func progressSliderTouchFinished() {
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

    @objc private func handleAutoReadTouchReset(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              isAutoReading else {
            return
        }
        shouldSuppressNextAutoReadTap = !isAutoReadVelocityAtBaseSpeed()
        resetAutoReadVelocityToBaseSpeed()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        let location = gesture.location(in: view)
        if isAutoReading {
            if shouldSuppressNextAutoReadTap {
                shouldSuppressNextAutoReadTap = false
                return
            }
            guard !autoReadPanel.frame.contains(location) else {
                return
            }
            guard tapAction(at: location) == .menu else {
                return
            }
            setAutoReadPanelVisible(!isAutoReadPanelVisible, animated: true)
            return
        }
        if isSettingsPanelVisible {
            guard !settingsPanel.frame.contains(location) else {
                return
            }
            setSettingsPanelVisible(false, animated: true)
            return
        }

        if isMenuVisible {
            guard !topBar.frame.contains(location),
                  !bottomBar.frame.contains(location),
                  !floatingActionStack.frame.contains(location) else {
                return
            }
            setMenuVisible(false, animated: true)
            return
        }

        switch tapAction(at: location) {
        case .menu:
            setMenuVisible(!isMenuVisible, animated: true)
        case .previousPage:
            moveToPreviousPage()
        case .nextPage:
            moveToNextPage()
        case .none:
            break
        }
    }

    @objc private func handlePageSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended,
              readerSettings.pageMode == .curl,
              !isMenuVisible,
              !isSettingsPanelVisible,
              !isAutoReading else {
            return
        }
        if gesture.direction == .left {
            moveToNextPage()
        } else if gesture.direction == .right {
            moveToPreviousPage()
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

    @objc private func handleEdgeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard navigationController == nil,
              readerSettings.edgeSwipeBackEnabled,
              gesture.state == .ended else {
            return
        }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        guard translation.x > view.bounds.width * 0.18 || velocity.x > 520 else {
            return
        }
        closeButtonTapped()
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

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard pages.indices.contains(indexPath.item),
              let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CollectionReaderPageCell.reuseIdentifier,
                for: indexPath
              ) as? CollectionReaderPageCell else {
            return UICollectionViewCell()
        }
        cell.configure(
            page: pages[indexPath.item],
            settings: readerSettings.normalized,
            layout: displayLayoutForCurrentMode(),
            widgetSnapshot: pageWidgetSnapshot(for: pages[indexPath.item]),
            widgetLayout: widgetLayoutConfiguration(),
            showsWidgets: !usesVerticalScrolling
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard collectionView.isDragging || collectionView.isDecelerating || isAutoReading else {
            return
        }
        if indexPath.item <= 1 {
            loadPreviousPageIfNeeded()
        }
        if indexPath.item >= pages.count - 2 {
            loadNextPageIfNeeded()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView,
              !isApplyingProgrammaticScroll else {
            return
        }
        updateCurrentPageFromVisiblePage()
        if !isAutoReading {
            prefetchPagesNearCurrent()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else {
            return
        }
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        flushPendingPageInsertions()
        snapToNearestHorizontalPageIfNeeded()
        pendingTapTargetPageIndex = nil
        updateCurrentPageFromVisiblePage()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === collectionView, isAutoReading else {
            return
        }
        // 接管松手后的减速:禁用 UIScrollView 自带 deceleration(衰减到 0),
        // 改由 DisplayLink 用 autoReadVelocity 走指数衰减,最终收敛到基线速度。
        targetContentOffset.pointee = scrollView.contentOffset
        // UIScrollView 给的 velocity 单位是 points / millisecond,
        // 方向上 +y 对应 contentOffset.y 增大(向下翻),与自动阅读方向一致。
        let releaseSpeed = velocity.y * 1000
        let baseSpeed = currentAutoReadBaseSpeed()
        guard abs(releaseSpeed) >= baseSpeed * 0.25 else {
            autoReadVelocity = baseSpeed
            lastAutoReadTimestamp = nil
            return
        }
        // 向下松手:小于基线的低速直接回到匀速;高于基线则保留向下惯性,衰减到 baseSpeed。
        // 向上松手:保留向上惯性,衰减到 0,然后由 advanceAutoRead 接力切回向下匀速。
        if releaseSpeed < 0 {
            autoReadVelocity = releaseSpeed
        } else {
            autoReadVelocity = max(releaseSpeed, baseSpeed)
        }
        lastAutoReadTimestamp = nil
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if usesVerticalScrolling {
            return CGSize(
                width: collectionView.bounds.width,
                height: verticalExtentForPage(at: indexPath.item)
            )
        }
        return collectionView.bounds.size
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           settingsControlPanRecognizers.contains(where: { $0 === panGesture }) {
            let velocity = panGesture.velocity(in: settingsPanelScrollView)
            return abs(velocity.y) >= abs(velocity.x)
        }
        if let interactivePopGesture = navigationController?.interactivePopGestureRecognizer,
           gestureRecognizer === interactivePopGesture {
            guard (navigationController?.viewControllers.count ?? 0) > 1 else {
                return false
            }

            if let topViewController = navigationController?.topViewController,
               let readerStackController = navigationStackControllerForReader(),
               topViewController !== readerStackController {
                return true
            }

            return readerSettings.edgeSwipeBackEnabled
        }
        if gestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return navigationController == nil && readerSettings.edgeSwipeBackEnabled
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === autoReadTouchResetGesture
            || otherGestureRecognizer === autoReadTouchResetGesture {
            return true
        }
        return settingsControlPanRecognizers.contains { $0 === gestureRecognizer || $0 === otherGestureRecognizer }
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

struct ReaderHostView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var book: Book
    let fileStore: AppFileStore
    let repository: any LibraryRepository
    let onStatusBarHiddenChange: (Bool) -> Void

    init(
        book: Book,
        fileStore: AppFileStore,
        repository: any LibraryRepository,
        onStatusBarHiddenChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.book = book
        self.fileStore = fileStore
        self.repository = repository
        self.onStatusBarHiddenChange = onStatusBarHiddenChange
    }

    func makeUIViewController(context: Context) -> CollectionReaderViewController {
        CollectionReaderViewController(
            book: book,
            fileStore: fileStore,
            repository: repository,
            onClose: {
                dismiss()
            },
            onStatusBarHiddenChange: { isHidden in
                onStatusBarHiddenChange(isHidden)
            }
        )
    }

    func updateUIViewController(
        _ uiViewController: CollectionReaderViewController,
        context: Context
    ) {
        uiViewController.update(book: book)
    }
}

extension UIViewController {
    func readerPopOrDismiss(animated: Bool) {
        if let navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: animated)
        } else {
            dismiss(animated: animated)
        }
    }
}

struct ReaderContentTarget {
    let chapterID: UUID
    let offset: Int
}

private final class ReaderProgressSlider: UISlider {
    private let minimumHitSize = CGSize(width: 44, height: 44)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalInset = min((bounds.width - minimumHitSize.width) / 2, 0)
        let verticalInset = min((bounds.height - minimumHitSize.height) / 2, 0)
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset).contains(point)
    }
}

private extension UIButton {
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

private struct ReaderLayoutConfiguration {
    var bodyKern: CGFloat
    var bodyLineSpacing: CGFloat
    var bodyParagraphSpacing: CGFloat
    var topMargin: CGFloat
    var bottomMargin: CGFloat
    var leftMargin: CGFloat
    var rightMargin: CGFloat
    var bodyFontWeight: UIFont.Weight
    var firstLineIndentEms: CGFloat
    var titleKern: CGFloat
    var titleLineSpacing: CGFloat
    var titleParagraphSpacing: CGFloat
    var titleFontSizeDelta: CGFloat
    var titleFontWeight: UIFont.Weight
    var widgetHorizontalMargin: CGFloat
    var widgetBottomMargin: CGFloat
    var widgetTitleTopMargin: CGFloat
    var widgetTitleLeftMargin: CGFloat
}

private struct ReaderTypography: @unchecked Sendable {
    var fontSize: Double
    var textColor: UIColor
    var chapterTitle: String?
    var layout: ReaderLayoutConfiguration

    init(settings: ReaderSettings, chapterTitle: String? = nil) {
        let normalizedSettings = settings.normalized
        fontSize = normalizedSettings.fontSize
        textColor = normalizedSettings.theme.textColor
        self.chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        layout = normalizedSettings.effectiveLayoutConfiguration
    }

    func attributedString(for text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else {
            return attributedString
        }

        let bodyFont = scaledFont(
            size: CGFloat(fontSize),
            weight: layout.bodyFontWeight
        )
        let titleFont = scaledFont(
            size: CGFloat(fontSize) + layout.titleFontSizeDelta,
            weight: layout.titleFontWeight
        )
        let titleRange = titleParagraphRange(in: nsText, fullRange: fullRange)

        nsText.enumerateSubstrings(
            in: fullRange,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, enclosingRange, _ in
            let range = NSIntersectionRange(enclosingRange, fullRange)
            guard range.length > 0 else {
                return
            }

            let isTitle = titleRange?.location == paragraphRange.location
                && titleRange?.length == paragraphRange.length
            if isTitle {
                attributedString.addAttributes(
                    titleAttributes(font: titleFont),
                    range: range
                )
            } else {
                attributedString.addAttributes(
                    bodyAttributes(
                        font: bodyFont,
                        nsText: nsText,
                        paragraphRange: paragraphRange
                    ),
                    range: range
                )
            }
        }

        return attributedString
    }

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }

    private func bodyAttributes(
        font: UIFont,
        nsText: NSString,
        paragraphRange: NSRange
    ) -> [NSAttributedString.Key: Any] {
        let firstLineIndent = hasExistingFirstLineIndent(in: nsText, paragraphRange: paragraphRange)
            ? 0
            : font.pointSize * layout.firstLineIndentEms

        return [
            .font: font,
            .foregroundColor: textColor,
            .kern: layout.bodyKern,
            .paragraphStyle: coreTextParagraphStyle(
                lineSpacing: layout.bodyLineSpacing,
                paragraphSpacing: layout.bodyParagraphSpacing,
                firstLineIndent: firstLineIndent
            ),
            .ligature: 0
        ]
    }

    private func titleAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        return [
            .font: font,
            .foregroundColor: textColor,
            .kern: layout.titleKern,
            .paragraphStyle: coreTextParagraphStyle(
                lineSpacing: layout.titleLineSpacing,
                paragraphSpacing: layout.titleParagraphSpacing,
                firstLineIndent: 0
            ),
            .ligature: 0
        ]
    }

    private func coreTextParagraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        firstLineIndent: CGFloat
    ) -> CTParagraphStyle {
        var alignment = CTTextAlignment.justified
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        var lineSpacingAdjustment = lineSpacing
        var minimumLineSpacing = lineSpacing
        var maximumLineSpacing = lineSpacing
        var paragraphSpacingValue = paragraphSpacing
        var firstLineIndentValue = firstLineIndent
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                withUnsafePointer(to: &lineSpacingAdjustment) { lineSpacingAdjustmentPointer in
                    withUnsafePointer(to: &minimumLineSpacing) { minimumLineSpacingPointer in
                        withUnsafePointer(to: &maximumLineSpacing) { maximumLineSpacingPointer in
                            withUnsafePointer(to: &paragraphSpacingValue) { paragraphSpacingPointer in
                                withUnsafePointer(to: &firstLineIndentValue) { firstLineIndentPointer in
                                    let settings = [
                                        CTParagraphStyleSetting(
                                            spec: .alignment,
                                            valueSize: MemoryLayout<CTTextAlignment>.size,
                                            value: UnsafeRawPointer(alignmentPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .lineBreakMode,
                                            valueSize: MemoryLayout<CTLineBreakMode>.size,
                                            value: UnsafeRawPointer(lineBreakPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .lineSpacingAdjustment,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(lineSpacingAdjustmentPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .minimumLineSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(minimumLineSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .maximumLineSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(maximumLineSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .paragraphSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(paragraphSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .firstLineHeadIndent,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(firstLineIndentPointer)
                                        )
                                    ]
                                    return CTParagraphStyleCreate(settings, settings.count)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func titleParagraphRange(in nsText: NSString, fullRange: NSRange) -> NSRange? {
        guard let expectedTitle = chapterTitle,
              !expectedTitle.isEmpty
        else {
            return nil
        }

        var result: NSRange?
        nsText.enumerateSubstrings(
            in: fullRange,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, stop in
            let candidate = nsText.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else {
                return
            }

            if candidate == expectedTitle {
                result = paragraphRange
            }
            stop.pointee = true
        }
        return result
    }

    private func hasExistingFirstLineIndent(
        in nsText: NSString,
        paragraphRange: NSRange
    ) -> Bool {
        guard paragraphRange.length > 0 else {
            return false
        }

        let paragraph = nsText.substring(with: paragraphRange)
        guard let firstCharacter = paragraph.first else {
            return false
        }

        return firstCharacter.isWhitespace
    }
}

private func readerFontWeight(for value: Double) -> UIFont.Weight {
    switch Int(value.rounded()) {
    case 0:
        return .regular
    case 1:
        return .medium
    case 2:
        return .semibold
    case 3:
        return .bold
    case 4:
        return .heavy
    default:
        return .black
    }
}

private struct ReaderWidgetLayoutConfiguration {
    var horizontalMargin: CGFloat
    var bottomMargin: CGFloat
    var titleTopMargin: CGFloat
    var titleLeftMargin: CGFloat
}

private struct ReaderPageWidgetSnapshot {
    var chapterTitle: String
    var batteryLevel: Float
    var batteryState: UIDevice.BatteryState
    var timeText: String
    var pageProgressText: String
    var globalProgressText: String
}

private final class ReaderPageWidgetOverlayView: UIView {
    private let titleLabel = UILabel()
    private let bottomLeftStack = UIStackView()
    private let batteryPercentageLabel = UILabel()
    private let batteryIconView = ReaderBatteryIconView()
    private let timeLabel = UILabel()
    private let bottomRightStack = UIStackView()
    private let pageProgressLabel = UILabel()
    private let globalProgressLabel = UILabel()

    private var titleTopConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var bottomLeftLeadingConstraint: NSLayoutConstraint?
    private var bottomLeftBottomConstraint: NSLayoutConstraint?
    private var bottomRightTrailingConstraint: NSLayoutConstraint?
    private var bottomRightBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        snapshot: ReaderPageWidgetSnapshot,
        settings: ReaderSettings,
        layout: ReaderWidgetLayoutConfiguration
    ) {
        let visibility = settings.widgetVisibility
        let textColor = settings.theme.secondaryTextColor
        let secondaryColor = textColor.withAlphaComponent(0.78)
        titleLabel.text = snapshot.chapterTitle
        titleLabel.textColor = secondaryColor
        batteryPercentageLabel.text = batteryText(for: snapshot.batteryLevel)
        batteryPercentageLabel.textColor = textColor
        timeLabel.text = snapshot.timeText
        timeLabel.textColor = textColor
        pageProgressLabel.text = snapshot.pageProgressText
        pageProgressLabel.textColor = textColor
        globalProgressLabel.text = snapshot.globalProgressText
        globalProgressLabel.textColor = textColor
        batteryIconView.configure(
            level: snapshot.batteryLevel,
            state: snapshot.batteryState,
            strokeColor: textColor
        )

        titleLabel.isHidden = !visibility.chapterTitle
        batteryPercentageLabel.isHidden = !visibility.batteryPercentage
        batteryIconView.isHidden = !visibility.batteryIcon
        timeLabel.isHidden = !visibility.time
        pageProgressLabel.isHidden = !visibility.chapterPageProgress
        globalProgressLabel.isHidden = !visibility.globalProgress
        bottomLeftStack.isHidden = !visibility.batteryPercentage
            && !visibility.batteryIcon
            && !visibility.time
        bottomRightStack.isHidden = !visibility.chapterPageProgress
            && !visibility.globalProgress

        titleTopConstraint?.constant = layout.titleTopMargin
        titleLeadingConstraint?.constant = layout.titleLeftMargin
        bottomLeftLeadingConstraint?.constant = layout.horizontalMargin
        bottomLeftBottomConstraint?.constant = -layout.bottomMargin
        bottomRightTrailingConstraint?.constant = -layout.horizontalMargin
        bottomRightBottomConstraint?.constant = -layout.bottomMargin
    }

    private func configureViews() {
        backgroundColor = .clear

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        [batteryPercentageLabel, timeLabel, pageProgressLabel, globalProgressLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        bottomLeftStack.axis = .horizontal
        bottomLeftStack.alignment = .center
        bottomLeftStack.spacing = 6
        bottomLeftStack.translatesAutoresizingMaskIntoConstraints = false
        bottomLeftStack.addArrangedSubview(batteryPercentageLabel)
        bottomLeftStack.addArrangedSubview(batteryIconView)
        bottomLeftStack.addArrangedSubview(timeLabel)
        addSubview(bottomLeftStack)

        bottomRightStack.axis = .horizontal
        bottomRightStack.alignment = .center
        bottomRightStack.spacing = 8
        bottomRightStack.translatesAutoresizingMaskIntoConstraints = false
        bottomRightStack.addArrangedSubview(pageProgressLabel)
        bottomRightStack.addArrangedSubview(globalProgressLabel)
        addSubview(bottomRightStack)

        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        bottomLeftLeadingConstraint = bottomLeftStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        bottomLeftBottomConstraint = bottomLeftStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomRightTrailingConstraint = bottomRightStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        bottomRightBottomConstraint = bottomRightStack.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            titleTopConstraint,
            titleLeadingConstraint,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            bottomLeftLeadingConstraint,
            bottomLeftBottomConstraint,
            bottomLeftStack.trailingAnchor.constraint(lessThanOrEqualTo: bottomRightStack.leadingAnchor, constant: -12),

            bottomRightTrailingConstraint,
            bottomRightBottomConstraint,
            batteryIconView.widthAnchor.constraint(equalToConstant: 24),
            batteryIconView.heightAnchor.constraint(equalToConstant: 12)
        ].compactMap { $0 })
    }

    private func batteryText(for level: Float) -> String {
        guard level >= 0 else {
            return "--%"
        }
        return "\(Int((level * 100).rounded()))%"
    }
}

private final class ReaderBatteryIconView: UIView {
    private var level: Float = -1
    private var batteryState: UIDevice.BatteryState = .unknown
    private var strokeColor: UIColor = .secondaryLabel

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        level: Float,
        state: UIDevice.BatteryState,
        strokeColor: UIColor
    ) {
        self.level = level
        self.batteryState = state
        self.strokeColor = strokeColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let capWidth: CGFloat = 2.2
        let bodyRect = CGRect(
            x: 0.75,
            y: 1.5,
            width: bounds.width - capWidth - 2.25,
            height: bounds.height - 3
        )
        let capRect = CGRect(
            x: bodyRect.maxX + 1,
            y: bounds.midY - 2,
            width: capWidth,
            height: 4
        )

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(1)
        UIBezierPath(roundedRect: bodyRect, cornerRadius: 2).stroke()
        context.setFillColor(strokeColor.cgColor)
        UIBezierPath(roundedRect: capRect, cornerRadius: 1).fill()

        let clampedLevel = level < 0 ? 1 : CGFloat(max(min(level, 1), 0))
        let fillInset: CGFloat = 2
        let fillWidth = max(0, (bodyRect.width - fillInset * 2) * clampedLevel)
        let fillRect = CGRect(
            x: bodyRect.minX + fillInset,
            y: bodyRect.minY + fillInset,
            width: fillWidth,
            height: max(0, bodyRect.height - fillInset * 2)
        )
        guard fillRect.width > 0 else {
            return
        }
        let fillColor: UIColor = batteryState == .charging || batteryState == .full
            ? .systemGreen
            : .black
        context.setFillColor(fillColor.cgColor)
        UIBezierPath(roundedRect: fillRect, cornerRadius: 1).fill()
    }
}

private extension ReaderSettings.LayoutPreset {
    var layoutConfiguration: ReaderLayoutConfiguration {
        layoutConfiguration(customValues: nil)
    }

    func layoutConfiguration(customValues: ReaderSettings.LayoutValues?) -> ReaderLayoutConfiguration {
        let values = customValues?.normalized ?? layoutValues
        switch self {
        case .compact:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        case .standard, .custom:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        case .relaxed:
            return ReaderLayoutConfiguration(
                bodyKern: CGFloat(values.bodyKern),
                bodyLineSpacing: CGFloat(values.bodyLineSpacing),
                bodyParagraphSpacing: CGFloat(values.bodyParagraphSpacing),
                topMargin: CGFloat(values.bodyTopMargin),
                bottomMargin: CGFloat(values.bodyBottomMargin),
                leftMargin: CGFloat(values.bodyLeftMargin),
                rightMargin: CGFloat(values.bodyRightMargin),
                bodyFontWeight: readerFontWeight(for: values.bodyFontWeightValue),
                firstLineIndentEms: CGFloat(values.firstLineIndentEms),
                titleKern: CGFloat(values.titleKern),
                titleLineSpacing: CGFloat(values.titleLineSpacing),
                titleParagraphSpacing: CGFloat(values.titleParagraphSpacing),
                titleFontSizeDelta: CGFloat(values.titleFontSizeDelta),
                titleFontWeight: readerFontWeight(for: values.titleFontWeightValue),
                widgetHorizontalMargin: CGFloat(values.widgetHorizontalMargin),
                widgetBottomMargin: CGFloat(values.widgetBottomMargin),
                widgetTitleTopMargin: CGFloat(values.widgetTitleTopMargin),
                widgetTitleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
            )
        }
    }

    var layoutValues: ReaderSettings.LayoutValues {
        switch self {
        case .compact:
            return .compact
        case .standard, .custom:
            return .standard
        case .relaxed:
            return .relaxed
        }
    }
}

private extension ReaderSettings {
    var effectiveLayoutValues: LayoutValues {
        normalized.layoutPreset == .custom
            ? (normalized.customLayoutValues?.normalized ?? .standard)
            : normalized.layoutPreset.layoutValues
    }

    var effectiveLayoutConfiguration: ReaderLayoutConfiguration {
        normalized.layoutPreset.layoutConfiguration(
            customValues: normalized.layoutPreset == .custom
                ? normalized.customLayoutValues
                : nil
        )
    }
}

private extension ReaderSettings.Theme {
    var backgroundColor: UIColor {
        switch self {
        case .white:
            return .systemBackground
        case .eyeCare:
            return UIColor(red: 0.92, green: 0.97, blue: 0.90, alpha: 1)
        case .paper:
            return UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1)
        case .dark:
            return UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .white:
            return .label
        case .eyeCare:
            return UIColor(red: 0.11, green: 0.18, blue: 0.12, alpha: 1)
        case .paper:
            return UIColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return UIColor(red: 0.88, green: 0.88, blue: 0.86, alpha: 1)
        }
    }

    var secondaryTextColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.70, green: 0.70, blue: 0.68, alpha: 1)
        default:
            return .secondaryLabel
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}

final class ReaderContentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private enum Mode: Int, CaseIterable {
        case chapters
        case bookmarks
    }

    private enum CatalogJumpTarget {
        case top
        case bottom

        var titleKey: String {
            switch self {
            case .top:
                return "reader.catalog.jumpTop"
            case .bottom:
                return "reader.catalog.jumpBottom"
            }
        }

        var opposite: CatalogJumpTarget {
            switch self {
            case .top:
                return .bottom
            case .bottom:
                return .top
            }
        }

        var scrollPosition: UITableView.ScrollPosition {
            switch self {
            case .top:
                return .top
            case .bottom:
                return .bottom
            }
        }

        func rowIndex(itemCount: Int) -> Int {
            switch self {
            case .top:
                return 0
            case .bottom:
                return max(itemCount - 1, 0)
            }
        }
    }

    private enum Layout {
        static let searchHeaderHeight: CGFloat = 56
        static let catalogEstimatedRowHeight: CGFloat = 52
        static let bookmarkEstimatedRowHeight: CGFloat = 118
        static let segmentedControlMinimumWidth: CGFloat = 128
        static let catalogDirectionVelocityThreshold: CGFloat = 20
    }

    private struct ChapterListItem {
        let chapter: Chapter
        let originalIndex: Int
    }

    private let bookID: UUID
    private let repository: any LibraryRepository
    private let chapters: [Chapter]
    private let selectedChapterIndex: Int
    private let onBookmarksChanged: ([Bookmark]) -> Void
    private let onSelect: (ReaderContentTarget) -> Void
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchHeaderView = UIView(
        frame: CGRect(
            x: 0,
            y: 0,
            width: 0,
            height: Layout.searchHeaderHeight
        )
    )
    private let searchBar = UISearchBar(frame: .zero)
    private lazy var emptyBookmarksLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("reader.bookmarks.empty", comment: "")
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        return label
    }()
    private lazy var segmentedControl = UISegmentedControl(items: [
        NSLocalizedString("reader.catalog.title", comment: ""),
        NSLocalizedString("reader.bookmarks.title", comment: "")
    ])
    private var bookmarks: [Bookmark] = []
    private var currentMode: Mode = .chapters
    private var catalogJumpTarget: CatalogJumpTarget = .bottom
    private var ignoresCatalogScrollDirection = false
    private var searchText = ""
    private var needsSelectedChapterScroll = true

    private var displayedChapterItems: [ChapterListItem] {
        let allItems = chapters.enumerated().map { index, chapter in
            ChapterListItem(chapter: chapter, originalIndex: index)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return allItems
        }
        return allItems.filter { item in
            item.chapter.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var isCatalogSearchActive: Bool {
        searchBar.isFirstResponder || searchText.isEmpty == false
    }

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        chapters: [Chapter],
        selectedChapterIndex: Int,
        onBookmarksChanged: @escaping ([Bookmark]) -> Void,
        onSelect: @escaping (ReaderContentTarget) -> Void
    ) {
        self.bookID = bookID
        self.repository = repository
        self.chapters = chapters
        self.selectedChapterIndex = selectedChapterIndex
        self.onBookmarksChanged = onBookmarksChanged
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.contents.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureSearchBar()
        configureTableView()
        updateModeChrome()

        reloadBookmarks()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateSearchHeaderFrame()
        guard needsSelectedChapterScroll else {
            return
        }

        needsSelectedChapterScroll = false
        scrollToSelectedChapter(animated: false)
    }

    private func configureNavigationBar() {
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: NSLocalizedString("common.back", comment: ""),
                style: .plain,
                target: self,
                action: #selector(closeButtonTapped)
            )
        }

        segmentedControl.selectedSegmentIndex = currentMode.rawValue
        segmentedControl.addTarget(
            self,
            action: #selector(segmentChanged),
            for: .valueChanged
        )
        segmentedControl.setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .footnote)],
            for: .normal
        )
        segmentedControl.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.segmentedControlMinimumWidth
        ).isActive = true
        navigationItem.titleView = segmentedControl

        updateCatalogJumpButton()
    }

    private func configureSearchBar() {
        searchHeaderView.backgroundColor = .systemBackground

        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("reader.catalog.search.placeholder", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.barTintColor = .systemBackground
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = .systemBackground
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchHeaderView.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: searchHeaderView.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: searchHeaderView.trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: searchHeaderView.topAnchor, constant: 4),
            searchBar.bottomAnchor.constraint(equalTo: searchHeaderView.bottomAnchor, constant: -4)
        ])
    }

    private func configureTableView() {
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = Layout.catalogEstimatedRowHeight
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    @objc private func segmentChanged() {
        guard let mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else {
            return
        }

        currentMode = mode
        catalogJumpTarget = .bottom
        if mode == .bookmarks {
            clearCatalogSearch(animated: true)
        }
        updateModeChrome()
        tableView.reloadData()
        updateBackgroundView()
        if mode == .chapters {
            scrollToSelectedChapter()
        }
    }

    @objc private func catalogJumpButtonTapped() {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false
        else {
            return
        }

        let target = catalogJumpTarget
        catalogJumpTarget = target.opposite
        ignoresCatalogScrollDirection = true
        scrollToChapterRow(
            target.rowIndex(itemCount: displayedChapterItems.count),
            at: target.scrollPosition,
            animated: true
        )
        updateCatalogJumpButton()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ignoresCatalogScrollDirection = false
        }
    }

    @MainActor
    private func reloadBookmarks() {
        Task {
            do {
                bookmarks = try await repository.fetchBookmarks(bookID: bookID)
            } catch {
                bookmarks = []
            }
            if currentMode == .bookmarks {
                tableView.reloadData()
            }
            updateBackgroundView()
            onBookmarksChanged(bookmarks)
        }
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        let originalBookmarks = bookmarks
        bookmarks.removeAll { $0.id == bookmark.id }
        tableView.reloadData()
        updateBackgroundView()
        onBookmarksChanged(bookmarks)
        let repository = repository
        Task { [weak self] in
            do {
                try await repository.deleteBookmark(id: bookmark.id)
            } catch is CancellationError {
            } catch {
                readerLogger.error("Failed to delete bookmark from contents: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarks = originalBookmarks
                    self.tableView.reloadData()
                    self.updateBackgroundView()
                    self.onBookmarksChanged(self.bookmarks)
                    self.showError(error)
                }
            }
        }
    }

    private func updateCatalogJumpButton() {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false
        else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString(
                catalogJumpTarget.titleKey,
                comment: ""
            ),
            style: .plain,
            target: self,
            action: #selector(catalogJumpButtonTapped)
        )
    }

    private func updateCatalogJumpTarget(_ target: CatalogJumpTarget) {
        guard catalogJumpTarget != target else {
            return
        }
        catalogJumpTarget = target
        updateCatalogJumpButton()
    }

    private func updateModeChrome() {
        updateSearchHeaderAvailability()
        updateCatalogJumpButton()
        updateBackgroundView()
    }

    private func updateSearchHeaderAvailability() {
        switch currentMode {
        case .chapters:
            if tableView.tableHeaderView !== searchHeaderView {
                tableView.tableHeaderView = searchHeaderView
            }
            updateSearchHeaderFrame()
        case .bookmarks:
            tableView.tableHeaderView = nil
        }
    }

    private func updateSearchHeaderFrame() {
        guard tableView.tableHeaderView === searchHeaderView else {
            return
        }

        var frame = searchHeaderView.frame
        let targetSize = CGSize(
            width: tableView.bounds.width,
            height: Layout.searchHeaderHeight
        )
        guard abs(frame.width - targetSize.width) > 0.5
            || abs(frame.height - targetSize.height) > 0.5
        else {
            return
        }

        frame.size = targetSize
        searchHeaderView.frame = frame
        tableView.tableHeaderView = searchHeaderView
    }

    private func clearCatalogSearch(animated: Bool) {
        searchText = ""
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.setShowsCancelButton(false, animated: animated)
    }

    private func updateBackgroundView() {
        tableView.backgroundView = currentMode == .bookmarks && bookmarks.isEmpty
            ? emptyBookmarksLabel
            : nil
    }

    private func scrollToSelectedChapter(animated: Bool = false) {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false,
              let row = displayedChapterItems.firstIndex(where: { item in
                  item.originalIndex == selectedChapterIndex
              })
        else {
            hideSearchHeaderIfNeeded(animated: false)
            return
        }

        scrollToChapterRow(row, at: .middle, animated: animated)
    }

    private func scrollToChapterRow(
        _ row: Int,
        at position: UITableView.ScrollPosition,
        animated: Bool
    ) {
        guard displayedChapterItems.indices.contains(row) else {
            return
        }

        tableView.layoutIfNeeded()
        tableView.scrollToRow(
            at: IndexPath(row: row, section: 0),
            at: position,
            animated: animated
        )
        guard isCatalogSearchActive == false else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.hideSearchHeaderIfNeeded(animated: false)
        }
    }

    private func hideSearchHeaderIfNeeded(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView,
              isCatalogSearchActive == false
        else {
            return
        }

        let hiddenOffset = -tableView.adjustedContentInset.top + Layout.searchHeaderHeight
        guard tableView.contentOffset.y < hiddenOffset else {
            return
        }

        tableView.setContentOffset(
            CGPoint(x: 0, y: hiddenOffset),
            animated: animated
        )
    }

    private func collapseSearchHeaderToCatalogTop(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView
        else {
            return
        }

        tableView.layoutIfNeeded()
        let hiddenOffset = -tableView.adjustedContentInset.top + Layout.searchHeaderHeight
        tableView.setContentOffset(
            CGPoint(x: 0, y: hiddenOffset),
            animated: animated
        )
    }

    private func revealSearchHeader(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView
        else {
            return
        }

        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: animated
        )
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch currentMode {
        case .chapters:
            return max(displayedChapterItems.count, 1)
        case .bookmarks:
            return bookmarks.count
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch currentMode {
        case .chapters:
            guard chapters.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.catalog.empty", comment: "")
                )
            }
            guard displayedChapterItems.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.catalog.search.empty", comment: "")
                )
            }
            return chapterCell(for: indexPath)
        case .bookmarks:
            guard bookmarks.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.bookmarks.empty", comment: "")
                )
            }
            return bookmarkCell(for: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch currentMode {
        case .chapters:
            let items = displayedChapterItems
            guard items.indices.contains(indexPath.row) else {
                return
            }
            let chapter = items[indexPath.row].chapter
            onSelect(ReaderContentTarget(chapterID: chapter.id, offset: 0))
        case .bookmarks:
            guard bookmarks.indices.contains(indexPath.row) else {
                return
            }
            let bookmark = bookmarks[indexPath.row]
            guard let chapterID = bookmark.chapterID,
                  chapters.contains(where: { $0.id == chapterID })
            else {
                showMissingBookmarkChapterAlert()
                return
            }
            onSelect(ReaderContentTarget(chapterID: chapterID, offset: bookmark.offset))
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard currentMode == .bookmarks,
              bookmarks.indices.contains(indexPath.row)
        else {
            return nil
        }

        let action = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("library.delete", comment: "")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }

            let bookmark = self.bookmarks[indexPath.row]
            self.deleteBookmark(bookmark)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(
        _ tableView: UITableView,
        estimatedHeightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        switch currentMode {
        case .chapters:
            return Layout.catalogEstimatedRowHeight
        case .bookmarks:
            return Layout.bookmarkEstimatedRowHeight
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView,
              currentMode == .chapters,
              displayedChapterItems.isEmpty == false,
              scrollView.isDragging,
              ignoresCatalogScrollDirection == false
        else {
            return
        }

        let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
        if velocityY > Layout.catalogDirectionVelocityThreshold {
            updateCatalogJumpTarget(.top)
        } else if velocityY < -Layout.catalogDirectionVelocityThreshold {
            updateCatalogJumpTarget(.bottom)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }
        ignoresCatalogScrollDirection = false
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        revealSearchHeader(animated: true)
    }

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        self.searchText = searchText
        catalogJumpTarget = .bottom
        tableView.reloadData()
        updateCatalogJumpButton()
        revealSearchHeader(animated: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if searchText.isEmpty {
            searchBar.setShowsCancelButton(false, animated: true)
            collapseSearchHeaderToCatalogTop(animated: true)
        }
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        clearCatalogSearch(animated: true)
        catalogJumpTarget = .bottom
        tableView.reloadData()
        updateCatalogJumpButton()
        collapseSearchHeaderToCatalogTop(animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        guard searchText.isEmpty else {
            return
        }

        searchBar.setShowsCancelButton(false, animated: true)
        collapseSearchHeaderToCatalogTop(animated: true)
    }

    private func emptyCell(text: String) -> UITableViewCell {
        let reuseIdentifier = "empty"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
        cell.textLabel?.text = text
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    private func chapterCell(for indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "chapter"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
        let item = displayedChapterItems[indexPath.row]
        cell.textLabel?.text = "\(item.originalIndex + 1).\(item.chapter.title)"
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.textColor = item.originalIndex == selectedChapterIndex
            ? .systemRed
            : .label
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }

    private func bookmarkCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReaderBookmarkCell.reuseIdentifier
        ) as? ReaderBookmarkCell
            ?? ReaderBookmarkCell(
                style: .default,
                reuseIdentifier: ReaderBookmarkCell.reuseIdentifier
            )
        let bookmark = bookmarks[indexPath.row]
        let chapterTitle = bookmark.chapterID
            .flatMap { chapterID in chapters.first { $0.id == chapterID }?.title }
            ?? NSLocalizedString("reader.bookmark.unknownChapter", comment: "")
        let isAvailable = bookmark.chapterID
            .map { chapterID in chapters.contains { $0.id == chapterID } }
            ?? false
        cell.configure(
            chapterTitle,
            time: Self.dateFormatter.string(from: bookmark.createdAt),
            preview: bookmark.preview,
            isAvailable: isAvailable
        )
        return cell
    }

    private func showMissingBookmarkChapterAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: NSLocalizedString("reader.bookmark.missingChapter", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func showError(_ error: Error) {
        guard presentedViewController == nil else {
            readerLogger.error("Reader contents error while another controller is presented: \(error.localizedDescription, privacy: .public)")
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

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class ReaderBookmarkCell: UITableViewCell {
    static let reuseIdentifier = "readerBookmark"

    private let chapterLabel = UILabel()
    private let timeLabel = UILabel()
    private let previewLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        chapterLabel.text = nil
        timeLabel.text = nil
        previewLabel.text = nil
        chapterLabel.textColor = .label
        previewLabel.textColor = .secondaryLabel
    }

    func configure(
        _ chapterTitle: String,
        time: String,
        preview: String,
        isAvailable: Bool
    ) {
        chapterLabel.text = chapterTitle
        timeLabel.text = time
        previewLabel.text = preview
        chapterLabel.textColor = isAvailable ? .label : .tertiaryLabel
        previewLabel.textColor = isAvailable ? .secondaryLabel : .tertiaryLabel
        isUserInteractionEnabled = true
    }

    private func configureViews() {
        selectionStyle = .default
        accessoryType = .none

        chapterLabel.font = .preferredFont(forTextStyle: .subheadline)
        chapterLabel.adjustsFontForContentSizeCategory = true
        chapterLabel.textColor = .label
        chapterLabel.numberOfLines = 1
        chapterLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = .secondaryLabel
        timeLabel.textAlignment = .right
        timeLabel.numberOfLines = 1
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        previewLabel.font = .preferredFont(forTextStyle: .callout)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail

        let headerStackView = UIStackView(arrangedSubviews: [
            chapterLabel,
            timeLabel
        ])
        headerStackView.axis = .horizontal
        headerStackView.alignment = .firstBaseline
        headerStackView.spacing = 12

        let contentStackView = UIStackView(arrangedSubviews: [
            headerStackView,
            previewLabel
        ])
        contentStackView.axis = .vertical
        contentStackView.spacing = 6
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        let guide = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            contentStackView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -6)
        ])
    }
}

private final class ReaderSettingsViewController: UIViewController {
    private var settings: ReaderSettings
    private let onChange: (ReaderSettings) -> Void
    private let fontValueLabel = UILabel()
    private let fontStepper = UIStepper()
    private lazy var pageModeControl = UISegmentedControl(
        items: ReaderSettings.PageMode.allCases.map(\.localizedTitle)
    )
    private lazy var themeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.localizedTitle)
    )

    init(
        settings: ReaderSettings,
        onChange: @escaping (ReaderSettings) -> Void
    ) {
        self.settings = settings.normalized
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.settings.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.close", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )

        configureControls()
    }

    private func configureControls() {
        pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases
            .firstIndex(of: settings.pageMode) ?? 0
        pageModeControl.addTarget(self, action: #selector(pageModeChanged), for: .valueChanged)

        themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases
            .firstIndex(of: settings.theme) ?? 0
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)

        fontStepper.minimumValue = ReaderSettings.minimumFontSize
        fontStepper.maximumValue = ReaderSettings.maximumFontSize
        fontStepper.stepValue = 1
        fontStepper.value = settings.fontSize
        fontStepper.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        updateFontValueLabel()

        let fontRow = UIStackView(arrangedSubviews: [fontValueLabel, fontStepper])
        fontRow.axis = .horizontal
        fontRow.alignment = .center
        fontRow.spacing = 12
        fontRow.distribution = .equalSpacing

        let stackView = UIStackView(arrangedSubviews: [
            settingsSection(
                title: NSLocalizedString("reader.settings.pageMode", comment: ""),
                control: pageModeControl
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.fontSize", comment: ""),
                control: fontRow
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.theme", comment: ""),
                control: themeControl
            )
        ])
        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    private func settingsSection(title: String, control: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        let stackView = UIStackView(arrangedSubviews: [titleLabel, control])
        stackView.axis = .vertical
        stackView.spacing = 8
        return stackView
    }

    private func updateFontValueLabel() {
        fontValueLabel.text = String(
            format: NSLocalizedString("reader.settings.fontSize.value", comment: ""),
            Int(settings.fontSize)
        )
        fontValueLabel.font = .preferredFont(forTextStyle: .body)
        fontValueLabel.adjustsFontForContentSizeCategory = true
    }

    @objc private func pageModeChanged() {
        let index = pageModeControl.selectedSegmentIndex
        guard ReaderSettings.PageMode.allCases.indices.contains(index) else {
            return
        }
        settings.pageMode = ReaderSettings.PageMode.allCases[index]
        onChange(settings)
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard ReaderSettings.Theme.allCases.indices.contains(index) else {
            return
        }
        settings.theme = ReaderSettings.Theme.allCases[index]
        onChange(settings)
    }

    @objc private func fontSizeChanged() {
        settings.fontSize = fontStepper.value
        updateFontValueLabel()
        onChange(settings)
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }
}

private extension ReaderSettings.PageMode {
    init?(settingsPageTurnIndex: Int) {
        switch settingsPageTurnIndex {
        case 0:
            self = .paged
        case 1:
            self = .curl
        case 2:
            self = .scroll
        default:
            return nil
        }
    }

    var settingsPageTurnIndex: Int {
        switch self {
        case .paged:
            return 0
        case .curl:
            return 1
        case .scroll:
            return 2
        }
    }

    var localizedTitle: String {
        switch self {
        case .paged:
            return NSLocalizedString("reader.settings.pageMode.paged", comment: "")
        case .curl:
            return NSLocalizedString("reader.settings.pageTurn.curl", comment: "")
        case .scroll:
            return NSLocalizedString("reader.settings.pageMode.scroll", comment: "")
        }
    }
}

private extension ReaderSettings.LayoutPreset {
    var localizedTitle: String {
        switch self {
        case .compact:
            return NSLocalizedString("reader.settings.layoutPreset.compact", comment: "")
        case .standard:
            return NSLocalizedString("reader.settings.layoutPreset.standard", comment: "")
        case .relaxed:
            return NSLocalizedString("reader.settings.layoutPreset.relaxed", comment: "")
        case .custom:
            return NSLocalizedString("reader.settings.layoutPreset.custom", comment: "")
        }
    }
}

private extension ReaderSettings.Theme {
    var localizedTitle: String {
        switch self {
        case .white:
            return NSLocalizedString("reader.settings.theme.white", comment: "")
        case .eyeCare:
            return NSLocalizedString("reader.settings.theme.eyeCare", comment: "")
        case .paper:
            return NSLocalizedString("reader.settings.theme.paper", comment: "")
        case .dark:
            return NSLocalizedString("reader.settings.theme.dark", comment: "")
        }
    }
}

private final class ChapterPaginator: @unchecked Sendable {
    struct Page {
        let attributedText: NSAttributedString
        let startDisplayUTF16Index: Int
        let displayUTF16Length: Int
        let usedHeight: CGFloat
    }

    private let attributedText: NSAttributedString
    private(set) var pageCharacterRanges: [NSRange] = []
    private(set) var pageStartDisplayUTF16Indexes: [Int] = []
    private(set) var pageUsedHeights: [CGFloat] = []

    var pageCount: Int {
        pageCharacterRanges.count
    }

    init(
        text: String,
        typography: ReaderTypography,
        fittingSize: CGSize
    ) {
        attributedText = typography.attributedString(for: text)
        buildPages(fittingSize: fittingSize)
    }

    func page(at index: Int) -> Page {
        guard pageCharacterRanges.isEmpty == false else {
            return Page(
                attributedText: NSAttributedString(string: ""),
                startDisplayUTF16Index: 0,
                displayUTF16Length: 0,
                usedHeight: 1
            )
        }

        let safeIndex = min(max(index, 0), pageCharacterRanges.count - 1)
        let range = pageCharacterRanges[safeIndex]
        let pageText = attributedText.attributedSubstring(from: range)
        let usedHeight = pageUsedHeights.indices.contains(safeIndex)
            ? pageUsedHeights[safeIndex]
            : 1

        return Page(
            attributedText: pageText,
            startDisplayUTF16Index: range.location,
            displayUTF16Length: range.length,
            usedHeight: usedHeight
        )
    }

    func pageStartDisplayUTF16Index(at index: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let safeIndex = min(max(index, 0), pageStartDisplayUTF16Indexes.count - 1)
        return pageStartDisplayUTF16Indexes[safeIndex]
    }

    func pageIndex(containingDisplayUTF16Index displayIndex: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let clampedIndex = min(max(displayIndex, 0), attributedText.length)
        var lowerBound = 0
        var upperBound = pageStartDisplayUTF16Indexes.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if pageStartDisplayUTF16Indexes[middle] <= clampedIndex {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return max(0, lowerBound - 1)
    }

    private func buildPages(fittingSize: CGSize) {
        let textLength = attributedText.length
        guard textLength > 0 else {
            return
        }

        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let pageRect = CGRect(
            x: 0,
            y: 0,
            width: max(fittingSize.width, 1),
            height: max(fittingSize.height, 1)
        )
        let path = CGMutablePath()
        path.addRect(pageRect)
        var startIndex = 0

        while startIndex < textLength {
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: startIndex, length: 0),
                path,
                nil
            )
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            let visibleLength = max(visibleRange.length, 1)
            let characterRange = NSRange(
                location: startIndex,
                length: min(visibleLength, textLength - startIndex)
            )

            guard characterRange.length > 0 else {
                break
            }

            let pageString = attributedText.attributedSubstring(from: characterRange).string
            if pageString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                pageCharacterRanges.append(characterRange)
                pageStartDisplayUTF16Indexes.append(characterRange.location)
                pageUsedHeights.append(
                    Self.usedHeight(
                        for: frame,
                        fallback: 1
                    )
                )
            }

            startIndex = characterRange.location + characterRange.length
        }

        if pageCharacterRanges.isEmpty {
            pageCharacterRanges = [NSRange(location: 0, length: textLength)]
            pageStartDisplayUTF16Indexes = [0]
            pageUsedHeights = [max(1, fittingSize.height)]
        }
    }

    private static func usedHeight(for frame: CTFrame, fallback: CGFloat) -> CGFloat {
        let lines = CTFrameGetLines(frame)
        let lineCount = CFArrayGetCount(lines)
        guard lineCount > 0 else {
            return max(1, fallback)
        }

        var origins = Array(repeating: CGPoint.zero, count: lineCount)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let firstLine = unsafeBitCast(
            CFArrayGetValueAtIndex(lines, 0),
            to: CTLine.self
        )
        let lastLine = unsafeBitCast(
            CFArrayGetValueAtIndex(lines, lineCount - 1),
            to: CTLine.self
        )

        var firstAscent: CGFloat = 0
        var firstDescent: CGFloat = 0
        var firstLeading: CGFloat = 0
        CTLineGetTypographicBounds(
            firstLine,
            &firstAscent,
            &firstDescent,
            &firstLeading
        )

        var lastAscent: CGFloat = 0
        var lastDescent: CGFloat = 0
        var lastLeading: CGFloat = 0
        CTLineGetTypographicBounds(
            lastLine,
            &lastAscent,
            &lastDescent,
            &lastLeading
        )

        let top = origins[0].y + firstAscent
        let bottom = origins[lineCount - 1].y - lastDescent
        return max(1, ceil(top - bottom))
    }
}

private struct CollectionReaderPage: Equatable, @unchecked Sendable {
    let id: String
    let bookID: UUID
    let chapterID: UUID
    let chapterTitle: String
    let chapterIndex: Int
    let pageIndex: Int
    let localPageIndex: Int
    let chapterPageCount: Int
    let chapterPageStartOffsets: [Int]
    let startAbsoluteOffset: Int
    let endAbsoluteOffset: Int
    let startChapterOffset: Int
    let globalProgress: Double
    let containsChapterTitle: Bool
    let verticalExtent: CGFloat
    let attributedText: NSAttributedString
    let text: String

    static func == (lhs: CollectionReaderPage, rhs: CollectionReaderPage) -> Bool {
        lhs.id == rhs.id
    }
}

private enum CollectionReaderError: LocalizedError {
    case bookNotFound
    case emptyPage

    var errorDescription: String? {
        switch self {
        case .bookNotFound:
            return NSLocalizedString("library.error.bookNotFound", comment: "")
        case .emptyPage:
            return NSLocalizedString("reader.emptyChapter", comment: "")
        }
    }
}

private enum CollectionReaderPaginator {
    static func makePage(
        book: Book,
        chapters: [Chapter],
        absoluteOffset: Int,
        forcedPageIndex: Int? = nil,
        settings: ReaderSettings,
        filterRules: [TextFilterRule],
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        widgetInsets: UIEdgeInsets,
        isVerticalViewport: Bool,
        targetLocalPageIndex: Int? = nil,
        fileStore: AppFileStore
    ) async throws -> CollectionReaderPage {
        try await Task.detached(priority: .userInitiated) {
            guard !chapters.isEmpty else {
                throw CollectionReaderError.bookNotFound
            }

            let chapterIndex = Self.chapterIndex(
                containing: absoluteOffset,
                in: chapters
            ) ?? 0
            let chapter = chapters[chapterIndex]
            let chapterOffset = min(
                max(absoluteOffset - chapter.startOffset, 0),
                max(chapter.byteLength - 1, 0)
            )
            let text = try ReaderChapterTextReader.readText(
                book: book,
                chapter: chapter,
                fileStore: fileStore
            )
            try Task.checkCancellation()

            let filtered = ReaderTextFilter.readingFilteredText(
                rules: filterRules,
                to: text
            )
            let isPlaceholderPage = filtered.displayText.isEmpty
            let displayText = isPlaceholderPage
                ? NSLocalizedString("reader.emptyChapter", comment: "")
                : filtered.displayText
            let normalizedSettings = settings.normalized
            let effectiveWidgetInsets = isVerticalViewport ? .zero : widgetInsets
            let layout = Self.effectiveLayout(
                settings: normalizedSettings,
                viewportSize: viewportSize,
                safeAreaInsets: safeAreaInsets,
                widgetInsets: effectiveWidgetInsets
            )
            let fittingSize = layout.contentRect(in: CGRect(origin: .zero, size: viewportSize)).size
            let typography = ReaderTypography(
                settings: normalizedSettings,
                chapterTitle: chapter.title
            )
            let paginator = ChapterPaginator(
                text: displayText,
                typography: typography,
                fittingSize: fittingSize
            )
            try Task.checkCancellation()

            let displayIndex = isPlaceholderPage
                ? 0
                : filtered.displayUTF16Index(containingOriginalByteOffset: chapterOffset)
            let localPageIndex = targetLocalPageIndex
                .map { min(max($0, 0), max(paginator.pageCount - 1, 0)) }
                ?? paginator.pageIndex(
                    containingDisplayUTF16Index: displayIndex
                )
            let page = paginator.page(at: localPageIndex)
            let chapterPageStartOffsets: [Int] = isPlaceholderPage
                ? [0]
                : (0..<paginator.pageCount).map { index in
                    filtered.originalByteOffset(
                        atDisplayUTF16Index: paginator.pageStartDisplayUTF16Index(at: index)
                    )
                }
            let pageEndDisplayIndex = page.startDisplayUTF16Index + page.displayUTF16Length
            let pageStartOffset: Int
            let pageEndOffset: Int
            if isPlaceholderPage {
                pageStartOffset = min(chapterOffset, max(chapter.byteLength - 1, 0))
                pageEndOffset = max(pageStartOffset + 1, chapter.byteLength)
            } else {
                pageStartOffset = filtered.originalByteOffset(
                    atDisplayUTF16Index: page.startDisplayUTF16Index
                )
                pageEndOffset = max(
                    filtered.originalByteOffset(atDisplayUTF16Index: pageEndDisplayIndex),
                    pageStartOffset + 1
                )
            }
            let startAbsoluteOffset = chapter.startOffset + pageStartOffset
            let endAbsoluteOffset = isPlaceholderPage
                ? max(chapter.startOffset + pageEndOffset, startAbsoluteOffset + 1)
                : min(
                    chapter.startOffset + pageEndOffset,
                    chapter.endOffset
                )
            let pageIndex = forcedPageIndex ?? localPageIndex
            let pageText = page.attributedText.string
            let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
            let globalProgress = min(max(Double(startAbsoluteOffset) / Double(totalByteLength), 0), 1)
            let containsChapterTitle = localPageIndex == 0
                && Self.pageContainsChapterTitle(pageText, chapterTitle: chapter.title)
            let pageGap = Self.pageGap(
                displayText: displayText,
                pageEndDisplayIndex: pageEndDisplayIndex,
                isChapterEnd: endAbsoluteOffset >= chapter.endOffset,
                fontSize: CGFloat(normalizedSettings.fontSize),
                layout: layout
            )
            let verticalExtent = ceil(page.usedHeight + pageGap)

            guard endAbsoluteOffset > startAbsoluteOffset else {
                throw CollectionReaderError.emptyPage
            }

            return CollectionReaderPage(
                id: "\(chapter.id.uuidString)-\(pageIndex)-\(startAbsoluteOffset)",
                bookID: book.id,
                chapterID: chapter.id,
                chapterTitle: chapter.title,
                chapterIndex: chapterIndex,
                pageIndex: pageIndex,
                localPageIndex: localPageIndex,
                chapterPageCount: paginator.pageCount,
                chapterPageStartOffsets: chapterPageStartOffsets,
                startAbsoluteOffset: startAbsoluteOffset,
                endAbsoluteOffset: endAbsoluteOffset,
                startChapterOffset: pageStartOffset,
                globalProgress: globalProgress,
                containsChapterTitle: containsChapterTitle,
                verticalExtent: verticalExtent,
                attributedText: page.attributedText,
                text: pageText
            )
        }.value
    }

    private static func chapterIndex(
        containing absoluteOffset: Int,
        in chapters: [Chapter]
    ) -> Int? {
        if let index = chapters.firstIndex(where: { absoluteOffset >= $0.startOffset && absoluteOffset < $0.endOffset }) {
            return index
        }
        if absoluteOffset >= (chapters.last?.endOffset ?? 0) {
            return chapters.indices.last
        }
        return chapters.indices.first
    }

    private static func effectiveLayout(
        settings: ReaderSettings,
        viewportSize: CGSize,
        safeAreaInsets: UIEdgeInsets,
        widgetInsets: UIEdgeInsets
    ) -> ReaderLayoutConfiguration {
        var layout = settings.effectiveLayoutConfiguration
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

    static func withDisabledWidgets(_ settings: ReaderSettings) -> ReaderSettings {
        var settings = settings
        settings.widgetVisibility = .hidden
        return settings
    }

    private static func pageGap(
        displayText: String,
        pageEndDisplayIndex: Int,
        isChapterEnd: Bool,
        fontSize: CGFloat,
        layout: ReaderLayoutConfiguration
    ) -> CGFloat {
        if isChapterEnd {
            return chapterEndGap(fontSize: fontSize, layout: layout)
        }
        guard pageEndDisplayIndex < displayText.utf16.count else {
            return 0
        }
        return isParagraphBoundary(in: displayText, atUTF16Index: pageEndDisplayIndex)
            ? layout.bodyParagraphSpacing
            : layout.bodyLineSpacing
    }

    private static func chapterEndGap(
        fontSize: CGFloat,
        layout: ReaderLayoutConfiguration
    ) -> CGFloat {
        let lineHeight = fontSize + layout.bodyLineSpacing
        return max(lineHeight * 3, layout.bodyParagraphSpacing)
    }

    private static func isParagraphBoundary(
        in text: String,
        atUTF16Index index: Int
    ) -> Bool {
        let clampedIndex = min(max(index, 0), text.utf16.count)
        let currentIndex = stringIndex(in: text, atUTF16Offset: clampedIndex)
        let previousIndex = previousCharacterIndex(in: text, before: currentIndex)

        let previousIsNewline = previousIndex.map { isNewline(text[$0]) } ?? false
        let currentIsNewline = currentIndex < text.endIndex && isNewline(text[currentIndex])
        return previousIsNewline || currentIsNewline
    }

    private static func isNewline(_ character: Character) -> Bool {
        character == "\n" || character == "\r"
    }

    private static func stringIndex(
        in text: String,
        atUTF16Offset offset: Int
    ) -> String.Index {
        var candidate = min(max(offset, 0), text.utf16.count)
        while candidate <= text.utf16.count {
            let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: candidate)
            if let index = String.Index(utf16Index, within: text) {
                return index
            }
            candidate += 1
        }
        return text.endIndex
    }

    private static func previousCharacterIndex(
        in text: String,
        before index: String.Index
    ) -> String.Index? {
        guard index > text.startIndex else {
            return nil
        }
        return text.index(before: index)
    }

    private static func pageContainsChapterTitle(_ text: String, chapterTitle: String) -> Bool {
        let expectedTitle = chapterTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedTitle.isEmpty else {
            return false
        }

        let lines = text.components(separatedBy: .newlines)
        guard let firstContentLine = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return false
        }
        return firstContentLine.trimmingCharacters(in: .whitespacesAndNewlines) == expectedTitle
    }
}

private final class CollectionReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "CollectionReaderPageCell"

    private let pageView = CollectionCoreTextPageView()
    private let widgetOverlay = ReaderPageWidgetOverlayView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        pageView.translatesAutoresizingMaskIntoConstraints = false
        widgetOverlay.translatesAutoresizingMaskIntoConstraints = false
        widgetOverlay.isUserInteractionEnabled = false
        contentView.addSubview(pageView)
        contentView.addSubview(widgetOverlay)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            widgetOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            widgetOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            widgetOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            widgetOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pageView.configure(
            attributedText: NSAttributedString(string: ""),
            layout: CollectionReaderPaginator.withDisabledWidgets(ReaderSettings.default)
                .effectiveLayoutConfiguration,
            backgroundColor: ReaderSettings.default.theme.backgroundColor
        )
        widgetOverlay.isHidden = true
    }

    func configure(
        page: CollectionReaderPage,
        settings: ReaderSettings,
        layout: ReaderLayoutConfiguration,
        widgetSnapshot: ReaderPageWidgetSnapshot,
        widgetLayout: ReaderWidgetLayoutConfiguration,
        showsWidgets: Bool
    ) {
        let backgroundColor = settings.theme.backgroundColor
        contentView.backgroundColor = backgroundColor
        pageView.configure(
            attributedText: page.attributedText,
            layout: layout,
            backgroundColor: backgroundColor
        )
        widgetOverlay.isHidden = !showsWidgets
        if showsWidgets {
            widgetOverlay.configure(
                snapshot: widgetSnapshot,
                settings: settings,
                layout: widgetLayout
            )
        }
    }
}

private final class CollectionCoreTextPageView: UIView {
    private var attributedText = NSAttributedString(string: "")
    private var layout = ReaderSettings.default.layoutPreset.layoutConfiguration

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        attributedText: NSAttributedString,
        layout: ReaderLayoutConfiguration,
        backgroundColor: UIColor
    ) {
        self.attributedText = attributedText
        self.layout = layout
        self.backgroundColor = backgroundColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard attributedText.length > 0,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let contentRect = layout.contentRect(in: bounds)
        guard contentRect.width > 0,
              contentRect.height > 0 else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

private extension ReaderLayoutConfiguration {
    func contentRect(in bounds: CGRect) -> CGRect {
        let minX = ceil(leftMargin)
        let minY = ceil(bottomMargin)
        let maxX = floor(bounds.width - rightMargin)
        let maxY = floor(bounds.height - topMargin)
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }
}
