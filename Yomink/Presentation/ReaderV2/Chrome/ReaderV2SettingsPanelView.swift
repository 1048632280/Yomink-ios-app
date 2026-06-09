import UIKit

@MainActor
final class ReaderV2SettingsPanelView: UIView, UIGestureRecognizerDelegate {
    let pageModeControl = UISegmentedControl(
        items: ReaderSettings.PageMode.allCases.map(\.readerV2Title)
    )
    let themeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.readerV2Title)
    )
    let quickControl = UISegmentedControl(
        items: [
            NSLocalizedString("reader.settings.quick.page", comment: ""),
            NSLocalizedString("reader.settings.quick.layout", comment: ""),
            NSLocalizedString("reader.settings.quick.more", comment: "")
        ]
    )
    let layoutControl = UISegmentedControl(
        items: ReaderSettings.LayoutPreset.allCases.map(\.readerV2Title)
    )
    let fontDecreaseButton = UIButton(type: .system)
    let fontValueButton = UIButton(type: .system)
    let fontIncreaseButton = UIButton(type: .system)
    let keepAwakeSwitch = UISwitch()
    let homeIndicatorSwitch = UISwitch()
    let statusBarControl = UISegmentedControl(items: [
        "隐藏",
        "白色",
        "黑色"
    ])
    let edgeSwipeBackSwitch = UISwitch()
    let chapterTitleSwitch = UISwitch()
    let batteryPercentageSwitch = UISwitch()
    let batteryIconSwitch = UISwitch()
    let timeSwitch = UISwitch()
    let chapterPageProgressSwitch = UISwitch()
    let globalProgressSwitch = UISwitch()

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private weak var pageModeSection: UIView?
    private weak var layoutSection: UIView?
    private weak var moreSection: UIView?
    private var settings: ReaderSettings = .default
    private var quickMode: SettingsQuickMode = .page
    private var layoutValueLabels: [LayoutAdjustment: UILabel] = [:]
    private var controlPanRecognizers: [UIPanGestureRecognizer] = []
    private var controlDragLastY: CGFloat = 0
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
        updateControlsFromSettings()
    }

    func apply(chromeTheme _: ReaderChromeTheme) {
        backgroundColor = MenuStyle.barBackgroundColor
        scrollView.backgroundColor = .clear
        tintLabels(in: self)
        [
            keepAwakeSwitch,
            homeIndicatorSwitch,
            edgeSwipeBackSwitch,
            chapterTitleSwitch,
            batteryPercentageSwitch,
            batteryIconSwitch,
            timeSwitch,
            chapterPageProgressSwitch,
            globalProgressSwitch
        ].forEach { control in
            control.onTintColor = .systemGreen
        }
    }

    func setPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        isPanelVisible = visible
        isHidden = false
        isUserInteractionEnabled = visible
        layoutIfNeeded()

        let changes = {
            self.applyPanelPosition()
        }
        let completion: (Bool) -> Void = { _ in
            self.isHidden = !visible
        }

        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPanelPosition()
    }

    private func configureViews() {
        backgroundColor = MenuStyle.barBackgroundColor
        clipsToBounds = true

        scrollView.alwaysBounceVertical = true
        scrollView.canCancelContentTouches = true
        scrollView.delaysContentTouches = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        configureFontButtons()
        [pageModeControl, themeControl, quickControl, layoutControl, statusBarControl].forEach(styleSettingsControl)

        stackView.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.fontSize", comment: ""),
            control: fontSizeControl()
        ))
        stackView.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.theme", comment: ""),
            control: themeControl
        ))
        stackView.addArrangedSubview(settingsSection(
            title: NSLocalizedString("reader.settings.quick", comment: ""),
            control: quickControl
        ))

        let pageModeSection = settingsSection(
            title: NSLocalizedString("reader.settings.pageTurn", comment: ""),
            control: pageModeControl
        )
        self.pageModeSection = pageModeSection
        stackView.addArrangedSubview(pageModeSection)

        let layoutSection = settingsSection(
            title: NSLocalizedString("reader.settings.layoutPreset", comment: ""),
            control: layoutSettingsControl()
        )
        self.layoutSection = layoutSection
        stackView.addArrangedSubview(layoutSection)

        let moreSection = settingsMoreControls()
        self.moreSection = moreSection
        stackView.addArrangedSubview(moreSection)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: Layout.settingsPanelHorizontalInset
            ),
            stackView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -Layout.settingsPanelHorizontalInset
            ),
            stackView.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: Layout.settingsPanelTopInset
            ),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -Layout.settingsPanelHorizontalInset * 2
            )
        ])
    }

    private func configureActions() {
        quickControl.addTarget(self, action: #selector(quickModeChanged), for: .valueChanged)
        pageModeControl.addTarget(self, action: #selector(pageModeChanged), for: .valueChanged)
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
        layoutControl.addTarget(self, action: #selector(layoutPresetChanged), for: .valueChanged)
        fontDecreaseButton.addTarget(self, action: #selector(fontDecreaseTapped), for: .touchUpInside)
        fontIncreaseButton.addTarget(self, action: #selector(fontIncreaseTapped), for: .touchUpInside)
        fontValueButton.addTarget(self, action: #selector(fontResetTapped), for: .touchUpInside)
        keepAwakeSwitch.addTarget(self, action: #selector(keepAwakeChanged), for: .valueChanged)
        homeIndicatorSwitch.addTarget(self, action: #selector(homeIndicatorChanged), for: .valueChanged)
        statusBarControl.addTarget(self, action: #selector(statusBarChanged), for: .valueChanged)
        edgeSwipeBackSwitch.addTarget(self, action: #selector(edgeSwipeBackChanged), for: .valueChanged)
        chapterTitleSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        batteryPercentageSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        batteryIconSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        timeSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        chapterPageProgressSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
        globalProgressSwitch.addTarget(self, action: #selector(widgetSwitchChanged), for: .valueChanged)
    }

    private func configureFontButtons() {
        configureFontButton(fontDecreaseButton, title: "-")
        configureFontButton(fontValueButton, title: "\(Int(settings.fontSize))")
        configureFontButton(fontIncreaseButton, title: "+")
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
        enableControlDrag(button)
    }

    private func fontSizeControl() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            fontDecreaseButton,
            fontValueButton,
            fontIncreaseButton
        ])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        return stack
    }

    private func settingsSection(title: String, control: UIView) -> UIView {
        let label = sectionTitleLabel(title)
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 9
        return stack
    }

    private func sectionTitleLabel(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = MenuStyle.secondaryTextColor
        label.adjustsFontForContentSizeCategory = true
        return label
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
        enableControlDrag(control)
    }

    private func layoutSettingsControl() -> UIView {
        let stack = UIStackView(arrangedSubviews: [
            layoutControl,
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

    private func layoutAdjustmentGroup(
        titleKey: String,
        adjustments: [LayoutAdjustment]
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString(titleKey, comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .footnote)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = MenuStyle.secondaryTextColor

        let rowStack = UIStackView(arrangedSubviews: adjustments.map(layoutAdjustmentRow))
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

        let decreaseButton = layoutAdjustmentButton(
            systemName: "minus",
            adjustment: adjustment,
            delta: -adjustment.step
        )
        let increaseButton = layoutAdjustmentButton(
            systemName: "plus",
            adjustment: adjustment,
            delta: adjustment.step
        )

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
        button.addTarget(self, action: #selector(layoutAdjustmentTapped(_:)), for: .touchUpInside)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold),
            forImageIn: .normal
        )
        enableControlDrag(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.settingsFontButtonHeight),
            button.heightAnchor.constraint(equalToConstant: Layout.settingsFontButtonHeight)
        ])
        return button
    }

    private func settingsMoreControls() -> UIView {
        let widgetStack = UIStackView(arrangedSubviews: [
            settingsGroupTitle("reader.settings.widgets.group"),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.chapterTitle", comment: ""),
                toggle: chapterTitleSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.batteryPercentage", comment: ""),
                toggle: batteryPercentageSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.batteryIcon", comment: ""),
                toggle: batteryIconSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.time", comment: ""),
                toggle: timeSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.chapterPageProgress", comment: ""),
                toggle: chapterPageProgressSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.widgets.globalProgress", comment: ""),
                toggle: globalProgressSwitch
            )
        ])
        widgetStack.axis = .vertical
        widgetStack.spacing = 2

        let stack = UIStackView(arrangedSubviews: [
            switchRow(
                title: NSLocalizedString("reader.settings.keepScreenAwake", comment: ""),
                toggle: keepAwakeSwitch
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.autoHideHomeIndicator", comment: ""),
                toggle: homeIndicatorSwitch
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.autoHideStatusBar", comment: ""),
                control: statusBarControl
            ),
            switchRow(
                title: NSLocalizedString("reader.settings.edgeSwipeBack", comment: ""),
                toggle: edgeSwipeBackSwitch
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

    private func switchRow(
        title: String,
        toggle: UISwitch
    ) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = MenuStyle.primaryTextColor
        label.adjustsFontForContentSizeCategory = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toggle.onTintColor = .systemGreen
        enableControlDrag(toggle)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .fill
        row.spacing = 16
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        return row
    }

    private func updateControlsFromSettings() {
        let normalized = settings.normalized
        pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases
            .firstIndex(of: normalized.pageMode) ?? 0
        themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases
            .firstIndex(of: normalized.theme) ?? 0
        quickControl.selectedSegmentIndex = quickMode.rawValue
        layoutControl.selectedSegmentIndex = ReaderSettings.LayoutPreset.allCases
            .firstIndex(of: normalized.layoutPreset) ?? 0
        fontValueButton.setTitle("\(Int(normalized.fontSize))", for: .normal)
        keepAwakeSwitch.isOn = normalized.keepScreenAwake
        homeIndicatorSwitch.isOn = normalized.autoHideHomeIndicator
        statusBarControl.selectedSegmentIndex = ReaderSettings.StatusBarMode.allCases
            .firstIndex(of: normalized.statusBarMode) ?? 0
        edgeSwipeBackSwitch.isOn = normalized.edgeSwipeBackEnabled
        chapterTitleSwitch.isOn = normalized.widgetVisibility.chapterTitle
        batteryPercentageSwitch.isOn = normalized.widgetVisibility.batteryPercentage
        batteryIconSwitch.isOn = normalized.widgetVisibility.batteryIcon
        timeSwitch.isOn = normalized.widgetVisibility.time
        chapterPageProgressSwitch.isOn = normalized.widgetVisibility.chapterPageProgress
        globalProgressSwitch.isOn = normalized.widgetVisibility.globalProgress
        updateLayoutValueLabels()
        updateQuickSection()
    }

    private func updateQuickSection() {
        pageModeSection?.isHidden = quickMode != .page
        layoutSection?.isHidden = quickMode != .layout
        moreSection?.isHidden = quickMode != .more
    }

    private func updateLayoutValueLabels() {
        let values = effectiveLayoutValues
        for adjustment in LayoutAdjustment.allCases {
            layoutValueLabels[adjustment]?.text = adjustment.formattedValue(adjustment.value(in: values))
        }
    }

    private var effectiveLayoutValues: ReaderSettings.LayoutValues {
        let normalized = settings.normalized
        if normalized.layoutPreset == .custom {
            return normalized.customLayoutValues?.normalized ?? .standard
        }
        return ReaderThemeManager.layoutValues(from: normalized)
    }

    private func emitChange() {
        settings = settings.normalized
        updateControlsFromSettings()
        onChange?(settings)
    }

    private func applyPanelPosition() {
        let hiddenOffset = bounds.height + 1
        transform = isPanelVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: hiddenOffset)
    }

    private func enableControlDrag(_ control: UIControl) {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(controlPanChanged(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        control.addGestureRecognizer(panGesture)
        controlPanRecognizers.append(panGesture)
    }

    @objc private func controlPanChanged(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: scrollView)
        switch gesture.state {
        case .began:
            controlDragLastY = translation.y
            scrollView.panGestureRecognizer.isEnabled = false
        case .changed:
            let deltaY = translation.y - controlDragLastY
            controlDragLastY = translation.y
            scrollSettingsPanel(by: deltaY)
        default:
            controlDragLastY = 0
            scrollView.panGestureRecognizer.isEnabled = true
        }
    }

    private func scrollSettingsPanel(by deltaY: CGFloat) {
        guard scrollView.contentSize.height > scrollView.bounds.height else {
            return
        }
        let minOffset = -scrollView.adjustedContentInset.top
        let maxOffset = max(
            minOffset,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let targetY = min(max(scrollView.contentOffset.y - deltaY, minOffset), maxOffset)
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
    }

    private func tintLabels(in view: UIView) {
        if let label = view as? UILabel,
           label.textColor != MenuStyle.primaryTextColor {
            label.textColor = label.font.fontDescriptor.symbolicTraits.contains(.traitBold)
                ? MenuStyle.primaryTextColor
                : label.textColor
        }
        view.subviews.forEach { subview in
            tintLabels(in: subview)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func quickModeChanged() {
        quickMode = SettingsQuickMode(rawValue: quickControl.selectedSegmentIndex) ?? .page
        updateQuickSection()
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

    @objc private func layoutPresetChanged() {
        let index = layoutControl.selectedSegmentIndex
        guard ReaderSettings.LayoutPreset.allCases.indices.contains(index) else {
            return
        }
        settings.layoutPreset = ReaderSettings.LayoutPreset.allCases[index]
        if settings.layoutPreset == .custom,
           settings.customLayoutValues == nil {
            settings.customLayoutValues = effectiveLayoutValues
        }
        emitChange()
    }

    @objc private func layoutAdjustmentTapped(_ sender: LayoutAdjustmentButton) {
        var values = effectiveLayoutValues
        sender.adjustment.apply(delta: sender.delta, to: &values)
        settings.layoutPreset = .custom
        settings.customLayoutValues = values
        emitChange()
    }

    @objc private func fontDecreaseTapped() {
        settings.fontSize -= 1
        emitChange()
    }

    @objc private func fontIncreaseTapped() {
        settings.fontSize += 1
        emitChange()
    }

    @objc private func fontResetTapped() {
        settings.fontSize = ReaderSettings.default.fontSize
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
        let index = statusBarControl.selectedSegmentIndex
        guard ReaderSettings.StatusBarMode.allCases.indices.contains(index) else {
            return
        }
        settings.statusBarMode = ReaderSettings.StatusBarMode.allCases[index]
        settings.autoHideStatusBar = settings.statusBarMode == .hidden
        emitChange()
    }

    @objc private func edgeSwipeBackChanged() {
        settings.edgeSwipeBackEnabled = edgeSwipeBackSwitch.isOn
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

private extension ReaderV2SettingsPanelView {
    enum SettingsQuickMode: Int {
        case page
        case layout
        case more
    }

    enum LayoutAdjustment: CaseIterable, Hashable {
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
            case .bodyKern, .titleKern, .firstLineIndent:
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

    final class LayoutAdjustmentButton: UIButton {
        var adjustment: LayoutAdjustment = .bodyLineSpacing
        var delta: Double = 0
    }

    enum Layout {
        static let settingsPanelContentHeight: CGFloat = 315
        static let settingsPanelHorizontalInset: CGFloat = 20
        static let settingsPanelTopInset: CGFloat = 22
        static let settingsControlHeight: CGFloat = 34
        static let settingsFontButtonHeight: CGFloat = 32
    }

    enum MenuStyle {
        static let barBackgroundColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let primaryTextColor = UIColor(white: 0.82, alpha: 1)
        static let secondaryTextColor = UIColor(white: 0.58, alpha: 1)
        static let settingsControlBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
        static let settingsControlSelectedColor = UIColor(red: 0.314, green: 0.314, blue: 0.314, alpha: 1)
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
