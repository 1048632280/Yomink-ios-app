import UIKit

@MainActor
final class ReaderV2SettingsPanelView: UIView {
    let pageModeControl = UISegmentedControl(
        items: ReaderSettings.PageMode.allCases.map(\.readerV2Title)
    )
    let themeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.readerV2Title)
    )
    let layoutControl = UISegmentedControl(
        items: ReaderSettings.LayoutPreset.allCases.map(\.readerV2Title)
    )
    let fontStepper = UIStepper()
    let keepAwakeSwitch = UISwitch()
    let homeIndicatorSwitch = UISwitch()
    let statusBarSwitch = UISwitch()
    let chapterTitleSwitch = UISwitch()
    let batteryPercentageSwitch = UISwitch()
    let batteryIconSwitch = UISwitch()
    let timeSwitch = UISwitch()
    let chapterPageProgressSwitch = UISwitch()
    let globalProgressSwitch = UISwitch()

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let fontValueLabel = UILabel()
    private var settings: ReaderSettings = .default
    private(set) var isPanelVisible = false

    var onChange: ((ReaderSettings) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        configureActions()
        setSettings(.default)
        setPanelVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSettings(_ settings: ReaderSettings) {
        self.settings = settings.normalized
        pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases
            .firstIndex(of: self.settings.pageMode) ?? 0
        themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases
            .firstIndex(of: self.settings.theme) ?? 0
        layoutControl.selectedSegmentIndex = ReaderSettings.LayoutPreset.allCases
            .firstIndex(of: self.settings.layoutPreset) ?? 0
        fontStepper.value = self.settings.fontSize
        keepAwakeSwitch.isOn = self.settings.keepScreenAwake
        homeIndicatorSwitch.isOn = self.settings.autoHideHomeIndicator
        statusBarSwitch.isOn = self.settings.autoHideStatusBar

        let visibility = self.settings.widgetVisibility
        chapterTitleSwitch.isOn = visibility.chapterTitle
        batteryPercentageSwitch.isOn = visibility.batteryPercentage
        batteryIconSwitch.isOn = visibility.batteryIcon
        timeSwitch.isOn = visibility.time
        chapterPageProgressSwitch.isOn = visibility.chapterPageProgress
        globalProgressSwitch.isOn = visibility.globalProgress
        updateFontValueLabel()
    }

    func apply(chromeTheme: ReaderChromeTheme) {
        backgroundColor = chromeTheme.panelBackgroundColor
        layer.borderColor = chromeTheme.separatorColor.cgColor
        stackView.arrangedSubviews.forEach { section in
            tintLabels(in: section, chromeTheme: chromeTheme)
        }
        [
            pageModeControl,
            themeControl,
            layoutControl,
            fontStepper,
            keepAwakeSwitch,
            homeIndicatorSwitch,
            statusBarSwitch,
            chapterTitleSwitch,
            batteryPercentageSwitch,
            batteryIconSwitch,
            timeSwitch,
            chapterPageProgressSwitch,
            globalProgressSwitch
        ].forEach { control in
            control.tintColor = chromeTheme.controlTintColor
        }
        [
            keepAwakeSwitch,
            homeIndicatorSwitch,
            statusBarSwitch,
            chapterTitleSwitch,
            batteryPercentageSwitch,
            batteryIconSwitch,
            timeSwitch,
            chapterPageProgressSwitch,
            globalProgressSwitch
        ].forEach { control in
            control.onTintColor = chromeTheme.controlTintColor
        }
    }

    func setPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        isPanelVisible = visible
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 18)
        }
        isHidden = false
        isUserInteractionEnabled = visible
        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: changes
            ) { _ in
                self.isHidden = !visible
            }
        } else {
            changes()
            isHidden = !visible
        }
    }

    private func configureViews() {
        layer.cornerRadius = 8
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        layer.borderWidth = 1 / UIScreen.main.scale

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        configureFontStepper()
        stackView.addArrangedSubview(section(
            title: NSLocalizedString("reader.settings.quick.page", comment: ""),
            rows: [
                controlRow(
                    title: NSLocalizedString("reader.settings.pageTurn", comment: ""),
                    control: pageModeControl
                ),
                controlRow(
                    title: NSLocalizedString("reader.settings.fontSize", comment: ""),
                    control: fontSizeControlRow()
                )
            ]
        ))
        stackView.addArrangedSubview(section(
            title: NSLocalizedString("reader.settings.quick.layout", comment: ""),
            rows: [
                controlRow(
                    title: NSLocalizedString("reader.settings.theme", comment: ""),
                    control: themeControl
                ),
                controlRow(
                    title: NSLocalizedString("reader.settings.layoutPreset", comment: ""),
                    control: layoutControl
                )
            ]
        ))
        stackView.addArrangedSubview(section(
            title: NSLocalizedString("reader.settings.quick.more", comment: ""),
            rows: [
                switchRow(
                    title: NSLocalizedString("reader.settings.keepScreenAwake", comment: ""),
                    control: keepAwakeSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.autoHideHomeIndicator", comment: ""),
                    control: homeIndicatorSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.autoHideStatusBar", comment: ""),
                    control: statusBarSwitch
                )
            ]
        ))
        stackView.addArrangedSubview(section(
            title: NSLocalizedString("reader.settings.widgets.group", comment: ""),
            rows: [
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.chapterTitle", comment: ""),
                    control: chapterTitleSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.batteryPercentage", comment: ""),
                    control: batteryPercentageSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.batteryIcon", comment: ""),
                    control: batteryIconSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.time", comment: ""),
                    control: timeSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.chapterPageProgress", comment: ""),
                    control: chapterPageProgressSwitch
                ),
                switchRow(
                    title: NSLocalizedString("reader.settings.widgets.globalProgress", comment: ""),
                    control: globalProgressSwitch
                )
            ]
        ))

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -18),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -22),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -36)
        ])
    }

    private func configureFontStepper() {
        fontStepper.minimumValue = ReaderSettings.minimumFontSize
        fontStepper.maximumValue = ReaderSettings.maximumFontSize
        fontStepper.stepValue = 1
        fontValueLabel.font = .preferredFont(forTextStyle: .body)
        fontValueLabel.adjustsFontForContentSizeCategory = true
        fontValueLabel.textAlignment = .right
        fontValueLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureActions() {
        pageModeControl.addTarget(self, action: #selector(pageModeChanged), for: .valueChanged)
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        layoutControl.addTarget(self, action: #selector(layoutChanged), for: .valueChanged)
        fontStepper.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        keepAwakeSwitch.addTarget(self, action: #selector(keepAwakeChanged), for: .valueChanged)
        homeIndicatorSwitch.addTarget(self, action: #selector(homeIndicatorChanged), for: .valueChanged)
        statusBarSwitch.addTarget(self, action: #selector(statusBarChanged), for: .valueChanged)
        chapterTitleSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        batteryPercentageSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        batteryIconSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        timeSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        chapterPageProgressSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        globalProgressSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
    }

    private func section(
        title: String,
        rows: [UIView]
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        let stack = UIStackView(arrangedSubviews: [titleLabel] + rows)
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    private func controlRow(
        title: String,
        control: UIView
    ) -> UIView {
        let titleLabel = rowTitleLabel(title)
        let stack = UIStackView(arrangedSubviews: [titleLabel, control])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func switchRow(
        title: String,
        control: UISwitch
    ) -> UIView {
        let titleLabel = rowTitleLabel(title)
        let stack = UIStackView(arrangedSubviews: [titleLabel, control])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func fontSizeControlRow() -> UIView {
        let stack = UIStackView(arrangedSubviews: [fontValueLabel, fontStepper])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.distribution = .equalSpacing
        return stack
    }

    private func rowTitleLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func tintLabels(
        in view: UIView,
        chromeTheme: ReaderChromeTheme
    ) {
        if let label = view as? UILabel {
            label.textColor = label.font.fontDescriptor.symbolicTraits.contains(.traitBold)
                ? chromeTheme.primaryTextColor
                : chromeTheme.secondaryTextColor
        }
        view.subviews.forEach { tintLabels(in: $0, chromeTheme: chromeTheme) }
    }

    private func updateFontValueLabel() {
        fontValueLabel.text = String(
            format: NSLocalizedString("reader.settings.fontSize.value", comment: ""),
            Int(settings.fontSize)
        )
    }

    private func emitChange() {
        settings = settings.normalized
        updateFontValueLabel()
        onChange?(settings)
    }

    @objc private func pageModeChanged() {
        let index = pageModeControl.selectedSegmentIndex
        guard ReaderSettings.PageMode.allCases.indices.contains(index) else {
            return
        }
        settings.pageMode = ReaderSettings.PageMode.allCases[index]
        emitChange()
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard ReaderSettings.Theme.allCases.indices.contains(index) else {
            return
        }
        settings.theme = ReaderSettings.Theme.allCases[index]
        emitChange()
    }

    @objc private func layoutChanged() {
        let index = layoutControl.selectedSegmentIndex
        guard ReaderSettings.LayoutPreset.allCases.indices.contains(index) else {
            return
        }
        settings.layoutPreset = ReaderSettings.LayoutPreset.allCases[index]
        emitChange()
    }

    @objc private func fontSizeChanged() {
        settings.fontSize = fontStepper.value
        emitChange()
    }

    @objc private func keepAwakeChanged() {
        settings.keepScreenAwake = keepAwakeSwitch.isOn
        emitChange()
    }

    @objc private func homeIndicatorChanged() {
        settings.autoHideHomeIndicator = homeIndicatorSwitch.isOn
        emitChange()
    }

    @objc private func statusBarChanged() {
        settings.autoHideStatusBar = statusBarSwitch.isOn
        emitChange()
    }

    @objc private func widgetSwitchChanged() {
        settings.widgetVisibility = ReaderSettings.WidgetVisibility(
            chapterTitle: chapterTitleSwitch.isOn,
            batteryPercentage: batteryPercentageSwitch.isOn,
            batteryIcon: batteryIconSwitch.isOn,
            time: timeSwitch.isOn,
            chapterPageProgress: chapterPageProgressSwitch.isOn,
            globalProgress: globalProgressSwitch.isOn
        )
        emitChange()
    }
}

private extension ReaderSettings.PageMode {
    var readerV2Title: String {
        switch self {
        case .paged:
            return NSLocalizedString("reader.settings.pageTurn.slide", comment: "")
        case .curl:
            return NSLocalizedString("reader.settings.pageTurn.curl", comment: "")
        case .scroll:
            return NSLocalizedString("reader.settings.pageTurn.scroll", comment: "")
        }
    }
}

private extension ReaderSettings.Theme {
    var readerV2Title: String {
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

private extension ReaderSettings.LayoutPreset {
    var readerV2Title: String {
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
