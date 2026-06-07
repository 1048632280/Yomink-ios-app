import UIKit

@MainActor
extension CollectionReaderViewController {
    func configureVerticalContentCovers() {
        [verticalTopCoverView, verticalBottomCoverView].forEach { coverView in
            coverView.isUserInteractionEnabled = false
            coverView.isHidden = true
            view.addSubview(coverView)
        }
    }

    func configureFixedWidgetOverlay() {
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

    func refreshReaderOverlayOrdering() {
        [
            verticalTopCoverView,
            verticalBottomCoverView,
            fixedWidgetOverlay,
            progressTooltipView,
            topBar,
            bottomBar,
            floatingActionStack,
            moreMenuContainer,
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

    func configureMenus() {
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
        configureMoreMenu()
        configureSettingsPanel()
        configureAutoReadPanel()
        setMenuVisible(false, animated: false)
        setMoreMenuVisible(false, animated: false)
        setSettingsPanelVisible(false, animated: false)
        setAutoReadPanelVisible(false, animated: false)
    }

    func configureTopBar() {
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
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)
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

    func configureBottomBar() {
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

    func configureProgressTooltip() {
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

    func configureFloatingActionButtons() {
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

    func configureFloatingButton(_ button: UIButton, systemName: String, titleKey: String) {
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

    func configureMoreMenu() {
        moreMenuContainer.backgroundColor = MenuStyle.barBackgroundColor
        moreMenuContainer.layer.cornerRadius = Layout.moreMenuCornerRadius
        moreMenuContainer.layer.masksToBounds = true
        moreMenuContainer.layer.borderColor = MenuStyle.separatorColor.cgColor
        moreMenuContainer.layer.borderWidth = 1
        moreMenuContainer.alpha = 0
        moreMenuContainer.isHidden = true
        moreMenuContainer.isUserInteractionEnabled = false
        moreMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreMenuContainer)

        moreMenuStack.axis = .vertical
        moreMenuStack.alignment = .fill
        moreMenuStack.distribution = .fill
        moreMenuStack.spacing = 0
        moreMenuStack.translatesAutoresizingMaskIntoConstraints = false
        moreMenuContainer.addSubview(moreMenuStack)

        let items: [(titleKey: String, action: Selector)] = [
            ("reader.more.bookDetail", #selector(moreBookDetailButtonTapped)),
            ("reader.more.contentSearch", #selector(moreContentSearchButtonTapped)),
            ("reader.more.contentFilter", #selector(moreContentFilterButtonTapped)),
            ("reader.more.pageTouchAreas", #selector(morePageTouchAreasButtonTapped))
        ]
        let separatorCount = max(items.count - 1, 0)
        let menuHeight = CGFloat(items.count) * Layout.moreMenuRowHeight
            + CGFloat(separatorCount)

        for (index, item) in items.enumerated() {
            let button = makeMoreMenuButton(titleKey: item.titleKey, action: item.action)
            moreMenuStack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: Layout.moreMenuRowHeight).isActive = true

            guard index < items.count - 1 else {
                continue
            }
            let separator = makeHorizontalMenuSeparator()
            moreMenuStack.addArrangedSubview(separator)
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        }

        NSLayoutConstraint.activate([
            moreMenuContainer.topAnchor.constraint(
                equalTo: topBar.bottomAnchor,
                constant: Layout.moreMenuTopSpacing
            ),
            moreMenuContainer.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.moreMenuTrailingInset
            ),
            moreMenuContainer.widthAnchor.constraint(equalToConstant: Layout.moreMenuWidth),
            moreMenuContainer.heightAnchor.constraint(equalToConstant: menuHeight),

            moreMenuStack.leadingAnchor.constraint(equalTo: moreMenuContainer.leadingAnchor),
            moreMenuStack.trailingAnchor.constraint(equalTo: moreMenuContainer.trailingAnchor),
            moreMenuStack.topAnchor.constraint(equalTo: moreMenuContainer.topAnchor),
            moreMenuStack.bottomAnchor.constraint(equalTo: moreMenuContainer.bottomAnchor)
        ])
    }

    func makeMoreMenuButton(titleKey: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString(titleKey, comment: ""), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(
            top: 0,
            left: Layout.moreMenuHorizontalInset,
            bottom: 0,
            right: Layout.moreMenuHorizontalInset
        )
        button.tintColor = MenuStyle.primaryTextColor
        button.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
        button.setTitleColor(.white, for: .highlighted)
        button.backgroundColor = MenuStyle.barBackgroundColor
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    func addMenuOverlay(to visualEffectView: UIVisualEffectView) {
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

    func makeVerticalMenuSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = MenuStyle.separatorColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        return separator
    }

    func makeHorizontalMenuSeparator() -> UIView {
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

    func configureBottomActionButton(_ button: UIButton) {
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

    func makeSliderThumbImage(diameter: CGFloat) -> UIImage {
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

    func updateVerticalContentCovers() {
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

    func applyTheme() {
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

    func updateDarkModeButton() {
        let imageName = readerSettings.theme == .dark ? "sun.max.fill" : "moon.stars"
        darkModeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    func updateAutoReadButton() {
        autoReadButton.setImage(UIImage(systemName: "circle"), for: .normal)
    }

    func refreshSystemStatusBarVisibility() {
        let isHidden = shouldHideSystemStatusBar
        onStatusBarHiddenChange(isHidden)
        setNeedsStatusBarAppearanceUpdate()
        navigationController?.setNeedsStatusBarAppearanceUpdate()

        // 强制系统重新读取小横条隐藏状态和边缘手势延迟设置
        refreshHomeIndicatorDeferralPreferences()
    }

    func refreshHomeIndicatorDeferralPreferences() {
        var controllers: [UIViewController] = [self]

        if let navigationController {
            controllers.append(navigationController)
        }

        var ancestor = parent
        while let current = ancestor {
            controllers.append(current)
            ancestor = current.parent
        }

        if let rootViewController = view.window?.rootViewController {
            controllers.append(rootViewController)
        }

        var visited = Set<ObjectIdentifier>()
        for controller in controllers {
            guard visited.insert(ObjectIdentifier(controller)).inserted else {
                continue
            }
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }

    func refreshHomeIndicatorDeferralPreferencesOnNextRunLoop() {
        refreshHomeIndicatorDeferralPreferences()
        DispatchQueue.main.async { [weak self] in
            self?.refreshHomeIndicatorDeferralPreferences()
        }
    }

    func setMenuVisible(_ visible: Bool, animated: Bool) {
        if !visible {
            setMoreMenuVisible(false, animated: animated)
        }
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

    func applyMenuPosition(animated _: Bool) {
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

    func setMoreMenuVisible(_ visible: Bool, animated: Bool) {
        guard isMoreMenuVisible != visible || moreMenuContainer.isHidden == visible else {
            return
        }

        isMoreMenuVisible = visible
        moreMenuContainer.isUserInteractionEnabled = visible
        moreButton.isSelected = visible
        moreButton.tintColor = visible ? .white : MenuStyle.primaryTextColor

        if visible {
            moreMenuContainer.isHidden = false
            moreMenuContainer.alpha = 0
            moreMenuContainer.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                .translatedBy(x: 4, y: -4)
            refreshReaderOverlayOrdering()
        }

        let animations = {
            self.moreMenuContainer.alpha = visible ? 1 : 0
            self.moreMenuContainer.transform = visible
                ? .identity
                : CGAffineTransform(scaleX: 0.96, y: 0.96).translatedBy(x: 4, y: -4)
        }
        let completion: (Bool) -> Void = { _ in
            guard !visible,
                  !self.isMoreMenuVisible else {
                return
            }
            self.moreMenuContainer.isHidden = true
            self.moreMenuContainer.transform = .identity
            self.moreMenuContainer.isUserInteractionEnabled = false
        }

        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    func showLoading(_ isLoading: Bool) {
        if isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    @objc func darkModeButtonTapped() {
        setMoreMenuVisible(false, animated: true)
        var settings = readerSettings
        settings.theme = settings.theme == .dark ? .white : .dark
        applyReaderSettings(settings)
    }

    @objc func moreButtonTapped() {
        setMoreMenuVisible(!isMoreMenuVisible, animated: true)
    }

    @objc func moreBookDetailButtonTapped() {
        performMoreMenuAction { showBookDetail() }
    }

    @objc func moreContentSearchButtonTapped() {
        performMoreMenuAction { showContentSearch() }
    }

    @objc func moreContentFilterButtonTapped() {
        performMoreMenuAction { showFilterRules() }
    }

    @objc func morePageTouchAreasButtonTapped() {
        performMoreMenuAction { showPageTouchAreas() }
    }

    func performMoreMenuAction(_ action: () -> Void) {
        setMenuVisible(false, animated: true)
        action()
    }
}
