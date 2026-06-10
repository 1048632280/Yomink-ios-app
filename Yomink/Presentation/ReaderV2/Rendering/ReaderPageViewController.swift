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
    private static let leftWidgetSpacing: CGFloat = 4
    private static let batteryIconSize = CGSize(width: 24, height: 12)

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
        let isLowBattery = snapshot.level < 0.2
        let batteryColor = isLowBattery ? Self.lowBatteryColor : headerColor
        batteryView.value = snapshot.level
        batteryView.fillColor = batteryColor
        batteryLabel.textColor = batteryColor
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

    private static let lowBatteryColor = UIColor(red: 0.82, green: 0.20, blue: 0.18, alpha: 1)

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

        let scale = rect.height / 12
        let capWidth = max(1.5, 1.55 * scale)
        let capGap = max(0.55, 0.75 * scale)
        let bodyRect = CGRect(
            x: max(0.8, 0.9 * scale),
            y: max(0.9, 1.1 * scale),
            width: rect.width - capWidth - capGap - max(1.8, 2.0 * scale),
            height: rect.height - max(1.8, 2.2 * scale)
        )
        let capHeight = min(rect.height - 4, max(4, 4.8 * scale))
        let capRect = CGRect(
            x: bodyRect.maxX + capGap,
            y: (rect.height - capHeight) / 2,
            width: capWidth,
            height: capHeight
        )
        let bodyCornerRadius = min(2.3 * scale, bodyRect.height / 2)
        let capCornerRadius = min(0.8 * scale, capRect.height / 2)

        context.setShadow(
            offset: CGSize(width: 0.6 * scale, height: 0.8 * scale),
            blur: 1.2 * scale,
            color: outlineColor.withAlphaComponent(0.28).cgColor
        )
        outlineColor.setFill()
        UIBezierPath(roundedRect: bodyRect, cornerRadius: bodyCornerRadius).fill()
        UIBezierPath(roundedRect: capRect, cornerRadius: capCornerRadius).fill()

        context.setShadow(offset: .zero, blur: 0, color: nil)
        UIColor(white: isDarkColor(outlineColor) ? 0.10 : 0.96, alpha: 1).setFill()
        let innerInsetX = max(2.0, 2.0 * scale)
        let innerInsetY = max(1.7, 1.8 * scale)
        let innerRect = bodyRect.insetBy(dx: innerInsetX, dy: innerInsetY)
        if innerRect.width > 0, innerRect.height > 0 {
            UIBezierPath(
                roundedRect: innerRect,
                cornerRadius: min(1.5 * scale, innerRect.height / 2)
            ).fill()

            let fillPadding = max(0.5, 0.45 * scale)
            let fillBounds = innerRect.insetBy(dx: fillPadding, dy: fillPadding)
            let fillWidth = max(0, fillBounds.width * value)
            let fillRect = CGRect(
                x: fillBounds.minX,
                y: fillBounds.minY,
                width: fillWidth,
                height: fillBounds.height
            )
            if fillRect.width > 0 {
                fillColor.setFill()
                UIBezierPath(
                    roundedRect: fillRect,
                    cornerRadius: min(1.0 * scale, fillRect.height / 2)
                ).fill()
            }
        }
        context.restoreGState()
    }

    private func isDarkColor(_ color: UIColor) -> Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return white < 0.45
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return red * 0.299 + green * 0.587 + blue * 0.114 < 0.45
        }
        return false
    }
}
