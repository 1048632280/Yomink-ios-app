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
    let batteryView = ReaderBatteryIndicatorView()
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
        if showTime {
            let width = max(38, ceil((timeLabel.text ?? "").size(withAttributes: [.font: widgetFont]).width))
            timeLabel.frame = CGRect(
                x: nextX,
                y: 0,
                width: width,
                height: ReaderPageWidgetLayout.height
            ).integral
            nextX = timeLabel.frame.maxX + 5
        }
        if showBatteryView {
            batteryView.frame = CGRect(
                x: nextX,
                y: (ReaderPageWidgetLayout.height - 8) / 2,
                width: 17,
                height: 8
            ).integral
            nextX = batteryView.frame.maxX + 5
        }
        if showBatteryLabel {
            let width = max(38, ceil((batteryLabel.text ?? "").size(withAttributes: [.font: widgetFont]).width))
            batteryLabel.frame = CGRect(
                x: nextX,
                y: 0,
                width: width,
                height: ReaderPageWidgetLayout.height
            ).integral
        }
    }

    private func updateBattery() {
        guard showBatteryView || showBatteryLabel else {
            return
        }
        let snapshot = batterySnapshotProvider()
        batteryView.value = snapshot.level
        batteryView.fillColor = snapshot.isCharging ? Self.chargingColor : headerColor
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

    private static let chargingColor = UIColor(red: 0.24, green: 0.73, blue: 0.32, alpha: 1)

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
final class ReaderBatteryIndicatorView: UIView {
    private var storedValue: CGFloat = 0

    var value: CGFloat {
        get {
            storedValue
        }
        set {
            storedValue = min(max(newValue, 0), 1)
            setNeedsDisplay()
        }
    }

    var color: UIColor {
        get {
            outlineColor
        }
        set {
            outlineColor = newValue
            fillColor = newValue
        }
    }

    var fillColor = ReaderTheme.standard.headerColor {
        didSet {
            setNeedsDisplay()
        }
    }

    private var outlineColor = ReaderTheme.standard.headerColor {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(),
              rect.width > 3,
              rect.height > 2 else {
            return
        }
        context.saveGState()
        context.setLineWidth(1.1)

        let capWidth: CGFloat = 2.2
        let capGap: CGFloat = 0.8
        let bodyRect = CGRect(
            x: 0.7,
            y: 0.7,
            width: rect.width - capWidth - capGap - 1.4,
            height: rect.height - 1.4
        )
        let capRect = CGRect(
            x: bodyRect.maxX + capGap,
            y: rect.height * 0.31,
            width: capWidth,
            height: rect.height * 0.38
        )
        outlineColor.setStroke()
        UIBezierPath(roundedRect: bodyRect, cornerRadius: 1.4).stroke()
        outlineColor.setFill()
        UIBezierPath(roundedRect: capRect, cornerRadius: 0.5).fill()

        let fillInset: CGFloat = 2.1
        let fillWidth = max(0, (bodyRect.width - fillInset * 2) * value)
        let fillRect = CGRect(
            x: bodyRect.minX + fillInset,
            y: bodyRect.minY + fillInset,
            width: fillWidth,
            height: max(0, bodyRect.height - fillInset * 2)
        )
        if fillRect.width > 0 {
            fillColor.setFill()
            UIBezierPath(roundedRect: fillRect, cornerRadius: 0.8).fill()
        }
        context.restoreGState()
    }
}
