import UIKit

@MainActor
extension CollectionReaderViewController {
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

    func saveSettingsImmediately() {
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

    @objc func settingsButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        setMenuVisible(false, animated: true)
        setSettingsPanelVisible(true, animated: true)
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
}