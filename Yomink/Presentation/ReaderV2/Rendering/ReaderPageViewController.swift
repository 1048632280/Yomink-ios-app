import UIKit

final class ReaderPageViewController: UIViewController {
    private(set) var backgroundView = ReaderPageBackgroundView()
    private(set) var textView = TextReadView()
    private(set) var chapterTitleLabel = UILabel()
    private(set) var bottomWidgetView = ReaderBottomWidgetView()
    private var page: ReaderDivisionPage?
    private(set) var pageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var chapterTitle = ""
    private var bookTitle = ""
    private var fullProgress: Double = 0
    private var widgetVisibility = ReaderSettings.WidgetVisibility.default

    var onTextSelectionAction: ((ReaderTextSelectionAction, String) -> Void)? {
        didSet {
            textView.onSelectionAction = onTextSelectionAction
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        view.addSubview(textView)
        configureWidgets()
        view.addSubview(chapterTitleLabel)
        view.addSubview(bottomWidgetView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        applyConfiguration()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWidgetLayout(screenSize: view.bounds.size, layoutConfig: layout)
    }

    func configure(
        page: ReaderDivisionPage,
        pageModel: ReaderPageModel,
        layout: ReaderLayout,
        theme: ReaderTheme,
        chapterTitle: String = "",
        bookTitle: String = "",
        fullProgress: Double = 0,
        widgetVisibility: ReaderSettings.WidgetVisibility = .default
    ) {
        self.page = page
        self.pageModel = pageModel
        self.layout = layout
        self.theme = theme
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.fullProgress = ReaderPageModel.clampedProgress(fullProgress)
        self.widgetVisibility = widgetVisibility
        applyConfiguration()
    }

    func setHighlightedRanges(_ ranges: [NSRange]) {
        textView.setHighlightedRanges(ranges)
    }

    func setSelectedRange(_ range: NSRange?) {
        textView.setSelectedRange(range)
    }

    func updateTheme(headerColor: UIColor) {
        chapterTitleLabel.textColor = headerColor
        bottomWidgetView.updateTheme(headerColor: headerColor)
    }

    func updateFont(_ font: UIFont) {
        chapterTitleLabel.font = font
        bottomWidgetView.updateFont(font)
    }

    func updateWidgetLayout(
        screenSize: CGSize,
        layoutConfig: ReaderLayout
    ) {
        chapterTitleLabel.frame = ReaderPageWidgetLayout.titleFrame(
            screenSize: screenSize,
            layout: layoutConfig
        )
        bottomWidgetView.frame = ReaderPageWidgetLayout.bottomFrame(
            screenSize: screenSize,
            layout: layoutConfig
        )
        bottomWidgetView.updateWidgetLayout(
            screenSize: bottomWidgetView.bounds.size,
            layoutConfig: layoutConfig
        )
    }

    func updateContent(
        chapterTitle: String,
        bookTitle: String? = nil,
        pageIndex: Int,
        pageCount: Int,
        fullProgress: Double
    ) {
        self.chapterTitle = chapterTitle
        if let bookTitle {
            self.bookTitle = bookTitle
        }
        self.fullProgress = ReaderPageModel.clampedProgress(fullProgress)
        chapterTitleLabel.text = ReaderPageWidgetLayout.headerTitle(
            bookTitle: self.bookTitle,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex
        )
        bottomWidgetView.updateContent(
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            pageCount: pageCount,
            fullProgress: self.fullProgress
        )
    }

    func updateSettings(
        showTime: Bool,
        showBatteryView: Bool,
        showBatteryLabel: Bool,
        showChapterTitle: Bool,
        showPageProgress: Bool,
        showFullProgress: Bool
    ) {
        chapterTitleLabel.isHidden = !showChapterTitle
        bottomWidgetView.updateSettings(
            showTime: showTime,
            showBatteryView: showBatteryView,
            showBatteryLabel: showBatteryLabel,
            showChapterTitle: showChapterTitle,
            showPageProgress: showPageProgress,
            showFullProgress: showFullProgress
        )
    }

    private func configureWidgets() {
        chapterTitleLabel.backgroundColor = .clear
        chapterTitleLabel.textAlignment = .left
        chapterTitleLabel.font = ReaderPageWidgetLayout.font
        chapterTitleLabel.numberOfLines = 1
        chapterTitleLabel.lineBreakMode = .byTruncatingTail
        chapterTitleLabel.isUserInteractionEnabled = false
        bottomWidgetView.isUserInteractionEnabled = false
    }

    private func applyConfiguration() {
        backgroundView.apply(theme: theme)
        textView.layout = layout
        textView.contentColor = theme.contentColor
        textView.onSelectionAction = onTextSelectionAction
        if let page {
            textView.setAttributedText(page.attributedText)
        }
        let visibility = widgetVisibility
        updateTheme(headerColor: theme.headerColor)
        updateFont(ReaderPageWidgetLayout.font)
        updateSettings(
            showTime: visibility.time,
            showBatteryView: visibility.batteryIcon,
            showBatteryLabel: visibility.batteryPercentage,
            showChapterTitle: visibility.chapterTitle,
            showPageProgress: visibility.chapterPageProgress,
            showFullProgress: visibility.globalProgress
        )
        updateContent(
            chapterTitle: chapterTitle,
            bookTitle: bookTitle,
            pageIndex: pageModel?.pageIndex ?? 0,
            pageCount: pageModel?.pageCount ?? 1,
            fullProgress: fullProgress
        )
        updateWidgetLayout(screenSize: view.bounds.size, layoutConfig: layout)
    }
}

enum ReaderPageWidgetLayout {
    static let height: CGFloat = 14
    static let font = UIFont.systemFont(ofSize: 12)

    static func headerTitle(
        bookTitle: String,
        chapterTitle: String,
        pageIndex: Int,
        prefersBookTitleOnFirstPage: Bool = true
    ) -> String {
        let normalizedBookTitle = bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if prefersBookTitleOnFirstPage,
           pageIndex == 0,
           normalizedBookTitle.isEmpty == false {
            return normalizedBookTitle
        }
        return chapterTitle
    }

    static func titleFrame(
        screenSize: CGSize,
        layout: ReaderLayout
    ) -> CGRect {
        CGRect(
            x: layout.widgetTitleLeft,
            y: layout.widgetTitleTop,
            width: max(0, screenSize.width - layout.widgetTitleLeft * 2),
            height: height
        ).integral
    }

    static func bottomFrame(
        screenSize: CGSize,
        layout: ReaderLayout
    ) -> CGRect {
        CGRect(
            x: layout.widgetLeft,
            y: screenSize.height - layout.widgetBottom - height,
            width: max(0, screenSize.width - layout.widgetLeft - layout.widgetRight),
            height: height
        ).integral
    }
}

@MainActor
final class ReaderBottomWidgetView: UIView {
    let timeLabel = UILabel()
    let batteryView = WKJBatteryView()
    let batteryLabel = UILabel()
    let progressLabel = UILabel()

    var batterySnapshotProvider: () -> ReaderBatterySnapshot = {
        ReaderBatterySnapshot.current
    }

    private var showTime = false
    private var showBatteryView = false
    private var showBatteryLabel = false
    private var showPageProgress = true
    private var showFullProgress = false
    private var pageIndex = 0
    private var pageCount = 1
    private var fullProgress: Double = 0
    private var widgetFont = ReaderPageWidgetLayout.font
    private var headerColor = ReaderTheme.standard.headerColor
    private static let leftWidgetSpacing: CGFloat = 3
    private static let batteryIconSize = CGSize(width: 17, height: 8)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        [timeLabel, batteryLabel, progressLabel].forEach(configureLabel)
        progressLabel.textAlignment = .right
        addSubview(timeLabel)
        addSubview(batteryView)
        addSubview(batteryLabel)
        addSubview(progressLabel)
        updateTheme(headerColor: headerColor)
        updateSettings(
            showTime: false,
            showBatteryView: false,
            showBatteryLabel: false,
            showChapterTitle: true,
            showPageProgress: true,
            showFullProgress: false
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLeftWidgets()
        let progressWidth = min(bounds.width, CGFloat(120))
        progressLabel.frame = CGRect(
            x: max(0, bounds.width - progressWidth),
            y: 0,
            width: progressWidth,
            height: ReaderPageWidgetLayout.height
        ).integral
    }

    func updateTheme(headerColor: UIColor) {
        self.headerColor = headerColor
        [timeLabel, batteryLabel, progressLabel].forEach {
            $0.textColor = headerColor
        }
        batteryView.color = headerColor
        updateBattery()
    }

    func updateFont(_ font: UIFont) {
        widgetFont = font
        [timeLabel, batteryLabel, progressLabel].forEach {
            $0.font = font
        }
        setNeedsLayout()
    }

    func updateWidgetLayout(
        screenSize _: CGSize,
        layoutConfig _: ReaderLayout
    ) {
        setNeedsLayout()
    }

    func updateContent(
        chapterTitle _: String,
        pageIndex: Int,
        pageCount: Int,
        fullProgress: Double
    ) {
        self.pageIndex = max(0, pageIndex)
        self.pageCount = max(1, pageCount)
        self.fullProgress = ReaderPageModel.clampedProgress(fullProgress)
        timeLabel.text = Self.timeFormatter.string(from: Date())
        updateBattery()
        updateProgressText()
        setNeedsLayout()
    }

    func updateSettings(
        showTime: Bool,
        showBatteryView: Bool,
        showBatteryLabel: Bool,
        showChapterTitle _: Bool,
        showPageProgress: Bool,
        showFullProgress: Bool
    ) {
        self.showTime = showTime
        self.showBatteryView = showBatteryView
        self.showBatteryLabel = showBatteryLabel
        self.showPageProgress = showPageProgress
        self.showFullProgress = showFullProgress
        timeLabel.isHidden = !showTime
        batteryView.isHidden = !showBatteryView
        batteryLabel.isHidden = !showBatteryLabel
        progressLabel.isHidden = !(showPageProgress || showFullProgress)
        if showBatteryView || showBatteryLabel {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        updateBattery()
        updateProgressText()
        setNeedsLayout()
    }

    private func configureLabel(_ label: UILabel) {
        label.backgroundColor = .clear
        label.font = widgetFont
        label.textColor = headerColor
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
    }

    private func layoutLeftWidgets() {
        var nextX: CGFloat = 0
        var hasPlacedWidget = false

        func place(_ view: UIView, width: CGFloat, height: CGFloat) {
            if hasPlacedWidget {
                nextX += Self.leftWidgetSpacing
            }
            view.frame = CGRect(
                x: nextX,
                y: (bounds.height - height) / 2,
                width: width,
                height: height
            ).integral
            nextX = view.frame.maxX
            hasPlacedWidget = true
        }

        if showBatteryLabel {
            let width = ceil((batteryLabel.text ?? "").size(withAttributes: [.font: widgetFont]).width)
            place(
                batteryLabel,
                width: width,
                height: ReaderPageWidgetLayout.height
            )
        }
        if showBatteryView {
            place(
                batteryView,
                width: Self.batteryIconSize.width,
                height: Self.batteryIconSize.height
            )
        }
        if showTime {
            let width = ceil((timeLabel.text ?? "").size(withAttributes: [.font: widgetFont]).width)
            place(
                timeLabel,
                width: width,
                height: ReaderPageWidgetLayout.height
            )
        }
    }

    private func updateBattery() {
        guard showBatteryView || showBatteryLabel else {
            return
        }
        let snapshot = batterySnapshotProvider()
        batteryView.batteryState = snapshot.state
        batteryView.value = snapshot.level
        batteryLabel.textColor = headerColor
        batteryLabel.text = String(format: "%.0f%%", Double(snapshot.level * 100))
    }

    private func updateProgressText() {
        var text = ""
        if showPageProgress {
            text = "\(min(pageIndex + 1, pageCount))/\(pageCount)"
        }
        if showFullProgress {
            let fullText = String(format: "%.2f%%", fullProgress * 100)
            text = text.isEmpty ? fullText : "\(text)  \(fullText)"
        }
        progressLabel.text = text
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @objc private func batteryDidChange() {
        updateBattery()
        setNeedsLayout()
    }
}

struct ReaderBatterySnapshot {
    var level: CGFloat
    var state: UIDevice.BatteryState

    var isCharging: Bool {
        state == .charging || state == .full
    }

    static var current: ReaderBatterySnapshot {
        let rawLevel = UIDevice.current.batteryLevel
        let level = rawLevel >= 0 ? CGFloat(min(max(rawLevel, 0), 1)) : 0
        return ReaderBatterySnapshot(
            level: level,
            state: UIDevice.current.batteryState
        )
    }
}

@MainActor
final class WKJBatteryView: UIView {
    private static let defaultColor = UIColor(white: 0.5490196078431373, alpha: 1)
    private static let chargeColor = UIColor(red: 48.0 / 255.0, green: 208.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)

    private let batteryView = UIView()
    private let frameLayer = CAShapeLayer()
    private let arrowLayer = CAShapeLayer()
    private var lastBatViewColor: UIColor?
    private var storedValue: CGFloat = 0
    private var bWidth: CGFloat {
        max(0, bounds.width - 1)
    }
    private var bHeight: CGFloat {
        max(0, bounds.height)
    }

    var value: CGFloat {
        get {
            storedValue
        }
        set {
            guard newValue.isNaN == false else {
                return
            }
            storedValue = min(max(newValue, 0), 1)
            resetColor()
            updateBatteryFrame()
        }
    }

    var color = WKJBatteryView.defaultColor {
        didSet {
            updateLayerColor()
            resetColor()
        }
    }

    var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState {
        didSet {
            resetColor()
        }
    }

    private(set) var fillColor = WKJBatteryView.defaultColor {
        didSet {
            batteryView.backgroundColor = fillColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        configureLayers()
        addSubview(batteryView)
        updateLayerColor()
        resetColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateBatteryPath()
        updateBatteryFrame()
    }

    private func configureLayers() {
        frameLayer.lineWidth = 1
        frameLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(frameLayer)

        arrowLayer.lineWidth = 1
        arrowLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(arrowLayer)
    }

    private func updateLayerColor() {
        let resolvedColor = color
        frameLayer.strokeColor = resolvedColor.cgColor
        arrowLayer.strokeColor = resolvedColor.cgColor
    }

    private func updateBatteryPath() {
        let bodyRect = CGRect(x: 0, y: 0, width: bWidth, height: bHeight)
        frameLayer.path = UIBezierPath(
            roundedRect: bodyRect,
            cornerRadius: 1
        ).cgPath

        let capRect = CGRect(
            x: bWidth,
            y: bHeight * 0.25,
            width: 1,
            height: bHeight * 0.5
        )
        arrowLayer.path = UIBezierPath(
            roundedRect: capRect,
            cornerRadius: 0
        ).cgPath
    }

    private func updateBatteryFrame() {
        batteryView.frame = CGRect(
            x: 1,
            y: 1,
            width: max(0, bWidth - 2) * value,
            height: max(0, bHeight - 2)
        )
    }

    private func resetColor() {
        let nextFillColor: UIColor
        if batteryState == .charging {
            nextFillColor = Self.chargeColor
        } else if value < 0.1 {
            nextFillColor = .red
        } else {
            nextFillColor = color
        }

        if lastBatViewColor?.isEqual(nextFillColor) != true {
            lastBatViewColor = nextFillColor
            fillColor = nextFillColor
        }
    }
}
