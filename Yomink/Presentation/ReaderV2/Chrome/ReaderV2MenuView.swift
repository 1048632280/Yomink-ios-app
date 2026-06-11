import UIKit

@MainActor
final class ReaderV2MenuView: UIView {
    let closeButton = UIButton(type: .system)
    let bookmarkButton = UIButton(type: .system)
    let moreButton = UIButton(type: .system)
    let previousChapterButton = UIButton(type: .system)
    let nextChapterButton = UIButton(type: .system)
    let progressSlider = ReaderV2MenuSlider()
    let catalogButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let autoReadButton = UIButton(type: .system)
    let darkModeButton = UIButton(type: .system)
    let moreBookDetailButton = UIButton(type: .system)
    let moreContentSearchButton = UIButton(type: .system)
    let moreContentFilterButton = UIButton(type: .system)
    let morePageTouchAreasButton = UIButton(type: .system)

    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressTooltipView = UIView()
    private let progressTooltipLabel = UILabel()
    private let floatingActionStack = UIStackView()
    private let moreMenuContainer = UIView()
    private let moreMenuStack = UIStackView()

    private var isTrackingProgressSlider = false
    private var lastChapterTitle = ""
    private var lastChapterProgress: Double = 0
    private var lastGlobalProgress: Double = 0
    private var lastPageIndex = 0
    private var lastPageCount = 1

    private(set) var isMenuVisible = false
    private(set) var isMoreMenuVisible = false
    private(set) var isTopBarVisible = false
    private var isBottomBarVisible = false
    private var isFloatingActionStackVisible = false

    var onClose: (() -> Void)?
    var onCatalog: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onSettings: (() -> Void)?
    var onPreviousChapter: (() -> Void)?
    var onNextChapter: (() -> Void)?
    var onAutoRead: (() -> Void)?
    var onDarkMode: (() -> Void)?
    var onMoreBookDetail: (() -> Void)?
    var onMoreContentSearch: (() -> Void)?
    var onMoreContentFilter: (() -> Void)?
    var onMorePageTouchAreas: (() -> Void)?
    var onProgressSliderBegan: (() -> Void)?
    var onProgressSliderChanged: ((Double) -> Void)?
    var onProgressSliderFinished: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        setMenuVisible(false, animated: false)
        setMoreMenuVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyMenuPosition()
    }

    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        guard isMenuVisible else {
            return false
        }
        return containsInteractiveContent(at: point)
    }

    func configure(bookTitle: String) {
        titleLabel.text = bookTitle
    }

    func updateProgress(
        chapterTitle: String,
        chapterProgress: Double,
        globalProgress: Double,
        pageIndex: Int,
        pageCount: Int
    ) {
        lastChapterTitle = chapterTitle
        lastChapterProgress = ReaderPageModel.clampedProgress(chapterProgress)
        lastGlobalProgress = ReaderPageModel.clampedProgress(globalProgress)
        lastPageIndex = max(pageIndex, 0)
        lastPageCount = max(pageCount, 1)
        progressLabel.text = progressText(
            chapterTitle: chapterTitle,
            chapterProgress: lastChapterProgress,
            globalProgress: lastGlobalProgress
        )
        progressTooltipLabel.text = progressTooltipText(
            chapterProgress: lastChapterProgress,
            pageIndex: lastPageIndex
        )
        progressSlider.accessibilityValue = ReadingProgressFormatter.percentString(from: lastChapterProgress)
        if !isTrackingProgressSlider {
            progressSlider.value = Float(lastChapterProgress)
        }
    }

    func updateProgressPreview(
        chapterProgress: Double,
        globalProgress: Double,
        pageIndex: Int
    ) {
        let chapterProgress = ReaderPageModel.clampedProgress(chapterProgress)
        let globalProgress = ReaderPageModel.clampedProgress(globalProgress)
        let pageIndex = max(pageIndex, 0)
        lastChapterProgress = chapterProgress
        lastGlobalProgress = globalProgress
        lastPageIndex = pageIndex
        progressLabel.text = progressText(
            chapterTitle: lastChapterTitle,
            chapterProgress: chapterProgress,
            globalProgress: globalProgress
        )
        progressTooltipLabel.text = progressTooltipText(
            chapterProgress: chapterProgress,
            pageIndex: pageIndex
        )
        progressSlider.accessibilityValue = ReadingProgressFormatter.percentString(from: chapterProgress)
    }

    func updateAutoRead(isReading: Bool) {
        autoReadButton.setImage(UIImage(systemName: "circle"), for: .normal)
        autoReadButton.isSelected = isReading
    }

    func updateDarkMode(isDark: Bool) {
        let imageName = isDark ? "sun.max.fill" : "moon.stars"
        darkModeButton.setImage(UIImage(systemName: imageName), for: .normal)
    }

    func updateBookmark(isBookmarked: Bool) {
        let imageName = isBookmarked ? "bookmark.fill" : "bookmark"
        bookmarkButton.setImage(UIImage(systemName: imageName), for: .normal)
        bookmarkButton.accessibilityLabel = NSLocalizedString(
            isBookmarked ? "reader.bookmark.remove" : "reader.bookmark.add",
            comment: ""
        )
    }

    func setBookmarkButtonEnabled(_ isEnabled: Bool) {
        bookmarkButton.isEnabled = isEnabled
        bookmarkButton.alpha = isEnabled ? 1 : 0.45
    }

    func updateChapterNavigation(
        canGoPrevious: Bool,
        canGoNext: Bool
    ) {
        setNavigationButton(previousChapterButton, enabled: canGoPrevious)
        setNavigationButton(nextChapterButton, enabled: canGoNext)
    }

    func apply(chromeTheme _: ReaderChromeTheme) {
        topBar.effect = nil
        topBar.backgroundColor = MenuStyle.barBackgroundColor
        topBar.contentView.backgroundColor = MenuStyle.barBackgroundColor
        bottomBar.effect = nil
        bottomBar.backgroundColor = MenuStyle.barBackgroundColor
        bottomBar.contentView.backgroundColor = MenuStyle.barBackgroundColor
        moreMenuContainer.backgroundColor = MenuStyle.barBackgroundColor
        moreMenuContainer.layer.borderColor = MenuStyle.separatorColor.cgColor
        progressTooltipView.backgroundColor = MenuStyle.progressTooltipBackgroundColor

        titleLabel.textColor = MenuStyle.secondaryTextColor
        progressLabel.textColor = MenuStyle.secondaryTextColor

        [
            closeButton,
            bookmarkButton,
            moreButton
        ].forEach { button in
            button.tintColor = MenuStyle.primaryTextColor
        }

        [
            previousChapterButton,
            nextChapterButton,
            catalogButton,
            settingsButton
        ].forEach { button in
            button.tintColor = MenuStyle.secondaryTextColor
            button.setTitleColor(MenuStyle.secondaryTextColor, for: .normal)
            button.setTitleColor(MenuStyle.primaryTextColor, for: .highlighted)
        }

        [
            autoReadButton,
            darkModeButton
        ].forEach { button in
            button.backgroundColor = MenuStyle.floatingButtonColor
            button.tintColor = MenuStyle.floatingButtonIconColor
        }

        [
            moreBookDetailButton,
            moreContentSearchButton,
            moreContentFilterButton,
            morePageTouchAreasButton
        ].forEach { button in
            button.backgroundColor = MenuStyle.barBackgroundColor
            button.tintColor = MenuStyle.primaryTextColor
            button.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
            button.setTitleColor(.white, for: .highlighted)
        }

        moreButton.tintColor = isMoreMenuVisible ? .white : MenuStyle.primaryTextColor
    }

    func setMenuVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        if !visible {
            setMoreMenuVisible(false, animated: animated)
        }

        isMenuVisible = visible
        isTopBarVisible = visible
        isBottomBarVisible = visible
        isFloatingActionStackVisible = visible
        updateMenuInteraction()
        isUserInteractionEnabled = visible
        isHidden = false
        layoutIfNeeded()

        let changes = {
            self.applyMenuPosition()
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

    func setBarsVisible(
        top: Bool,
        bottom: Bool,
        floatingActions: Bool,
        animated: Bool
    ) {
        if !top {
            setMoreMenuVisible(false, animated: animated)
        }

        isMenuVisible = top || bottom || floatingActions
        isTopBarVisible = top
        isBottomBarVisible = bottom
        isFloatingActionStackVisible = floatingActions
        updateMenuInteraction()
        isUserInteractionEnabled = isMenuVisible
        isHidden = false
        layoutIfNeeded()

        let changes = {
            self.applyMenuPosition()
        }
        let completion: (Bool) -> Void = { _ in
            self.isHidden = !self.isMenuVisible
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

    func setMoreMenuVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        guard visible != isMoreMenuVisible || moreMenuContainer.isHidden == visible else {
            moreButton.isSelected = visible
            moreButton.tintColor = visible ? .white : MenuStyle.primaryTextColor
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
            bringSubviewToFront(moreMenuContainer)
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

    func containsInteractiveContent(at point: CGPoint) -> Bool {
        guard isMenuVisible else {
            return false
        }
        return (isTopBarVisible && topBar.frame.contains(point))
            || (isBottomBarVisible && bottomBar.frame.contains(point))
            || (isFloatingActionStackVisible && floatingActionStack.frame.contains(point))
            || (isMoreMenuVisible && moreMenuContainer.frame.contains(point))
    }

    func containsMoreMenuOrButton(at point: CGPoint) -> Bool {
        guard isMenuVisible else {
            return false
        }
        let moreButtonFrame = moreButton.convert(moreButton.bounds, to: self)
        return moreButtonFrame.contains(point)
            || (isMoreMenuVisible && moreMenuContainer.frame.contains(point))
    }

    private func updateMenuInteraction() {
        topBar.isUserInteractionEnabled = isTopBarVisible
        bottomBar.isUserInteractionEnabled = isBottomBarVisible
        floatingActionStack.isUserInteractionEnabled = isFloatingActionStackVisible
    }

    private func configureViews() {
        backgroundColor = .clear
        alpha = 1

        topBar.effect = nil
        bottomBar.effect = nil
        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)
        addSubview(bottomBar)
        addMenuOverlay(to: topBar)
        addMenuOverlay(to: bottomBar)

        configureTopBar()
        configureBottomBar()
        configureProgressTooltip()
        configureFloatingActionButtons()
        configureMoreMenu()
        apply(chromeTheme: .standard)
    }

    private func configureTopBar() {
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("reader.close", comment: "")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        updateBookmark(isBookmarked: false)
        bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.accessibilityLabel = NSLocalizedString("reader.more", comment: "")
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
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
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.topBarContentHeight
            ),

            closeButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            closeButton.bottomAnchor.constraint(
                equalTo: topBar.contentView.bottomAnchor,
                constant: -Layout.topBarButtonBottomInset
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),

            actionStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            actionStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            bookmarkButton.widthAnchor.constraint(equalToConstant: 44),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configureBottomBar() {
        previousChapterButton.setTitle(NSLocalizedString("reader.previousChapter", comment: ""), for: .normal)
        previousChapterButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        previousChapterButton.accessibilityLabel = NSLocalizedString("reader.previousChapter", comment: "")
        previousChapterButton.addTarget(self, action: #selector(previousChapterTapped), for: .touchUpInside)
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false

        nextChapterButton.setTitle(NSLocalizedString("reader.nextChapter", comment: ""), for: .normal)
        nextChapterButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        nextChapterButton.accessibilityLabel = NSLocalizedString("reader.nextChapter", comment: "")
        nextChapterButton.addTarget(self, action: #selector(nextChapterTapped), for: .touchUpInside)
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
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
        progressLabel.numberOfLines = 2
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        catalogButton.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        catalogButton.setTitle(NSLocalizedString("reader.catalog", comment: ""), for: .normal)
        configureBottomActionButton(catalogButton)
        catalogButton.accessibilityLabel = NSLocalizedString("reader.catalog", comment: "")
        catalogButton.addTarget(self, action: #selector(catalogTapped), for: .touchUpInside)

        settingsButton.setImage(UIImage(systemName: "textformat"), for: .normal)
        settingsButton.setTitle(NSLocalizedString("reader.settings", comment: ""), for: .normal)
        configureBottomActionButton(settingsButton)
        settingsButton.accessibilityLabel = NSLocalizedString("reader.settings", comment: "")
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        let leftProgressSeparator = makeVerticalMenuSeparator()
        let rightProgressSeparator = makeVerticalMenuSeparator()
        let actionRowTopSeparator = makeHorizontalMenuSeparator()
        let progressSliderContainer = UIView()
        progressSliderContainer.clipsToBounds = false
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
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),

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
                equalTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.bottomBarSafeAreaInset
            ),
            actionRow.heightAnchor.constraint(equalToConstant: Layout.bottomActionRowHeight)
        ])
    }

    private func configureProgressTooltip() {
        progressTooltipView.layer.cornerRadius = 4
        progressTooltipView.layer.masksToBounds = true
        progressTooltipView.alpha = 0
        progressTooltipView.isHidden = true
        progressTooltipView.isUserInteractionEnabled = false
        progressTooltipView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressTooltipView)

        progressTooltipLabel.font = .systemFont(ofSize: 14, weight: .regular)
        progressTooltipLabel.textColor = .white
        progressTooltipLabel.textAlignment = .center
        progressTooltipLabel.numberOfLines = 1
        progressTooltipLabel.adjustsFontSizeToFitWidth = true
        progressTooltipLabel.minimumScaleFactor = 0.86
        progressTooltipLabel.translatesAutoresizingMaskIntoConstraints = false
        progressTooltipView.addSubview(progressTooltipLabel)

        NSLayoutConstraint.activate([
            progressTooltipView.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        addSubview(floatingActionStack)

        configureFloatingButton(autoReadButton, systemName: "circle", titleKey: "reader.autoRead.placeholder")
        autoReadButton.addTarget(self, action: #selector(autoReadTapped), for: .touchUpInside)

        configureFloatingButton(darkModeButton, systemName: "moon.stars", titleKey: "reader.darkMode.placeholder")
        darkModeButton.addTarget(self, action: #selector(darkModeTapped), for: .touchUpInside)

        floatingActionStack.addArrangedSubview(autoReadButton)
        floatingActionStack.addArrangedSubview(darkModeButton)

        NSLayoutConstraint.activate([
            floatingActionStack.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.floatingButtonTrailingInset
            ),
            floatingActionStack.bottomAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: -Layout.floatingButtonBottomInset
            ),
            autoReadButton.widthAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            autoReadButton.heightAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            darkModeButton.widthAnchor.constraint(equalToConstant: Layout.floatingButtonSize),
            darkModeButton.heightAnchor.constraint(equalToConstant: Layout.floatingButtonSize)
        ])
    }

    private func configureFloatingButton(
        _ button: UIButton,
        systemName: String,
        titleKey: String
    ) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        button.layer.cornerRadius = Layout.floatingButtonSize / 2
        button.layer.masksToBounds = true
        button.accessibilityLabel = NSLocalizedString(titleKey, comment: "")
        button.isUserInteractionEnabled = true
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureMoreMenu() {
        moreMenuContainer.layer.cornerRadius = Layout.moreMenuCornerRadius
        moreMenuContainer.layer.masksToBounds = true
        moreMenuContainer.layer.borderWidth = 1
        moreMenuContainer.alpha = 0
        moreMenuContainer.isHidden = true
        moreMenuContainer.isUserInteractionEnabled = false
        moreMenuContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(moreMenuContainer)

        moreMenuStack.axis = .vertical
        moreMenuStack.alignment = .fill
        moreMenuStack.distribution = .fill
        moreMenuStack.spacing = 0
        moreMenuStack.translatesAutoresizingMaskIntoConstraints = false
        moreMenuContainer.addSubview(moreMenuStack)

        let items: [(button: UIButton, titleKey: String, action: Selector)] = [
            (moreBookDetailButton, "reader.more.bookDetail", #selector(moreBookDetailTapped)),
            (moreContentSearchButton, "reader.more.contentSearch", #selector(moreContentSearchTapped)),
            (moreContentFilterButton, "reader.more.contentFilter", #selector(moreContentFilterTapped)),
            (morePageTouchAreasButton, "reader.more.pageTouchAreas", #selector(morePageTouchAreasTapped))
        ]
        let separatorCount = max(items.count - 1, 0)
        let menuHeight = CGFloat(items.count) * Layout.moreMenuRowHeight
            + CGFloat(separatorCount)

        for (index, item) in items.enumerated() {
            configureMoreMenuButton(item.button, titleKey: item.titleKey, action: item.action)
            moreMenuStack.addArrangedSubview(item.button)
            item.button.heightAnchor.constraint(equalToConstant: Layout.moreMenuRowHeight).isActive = true

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
                equalTo: safeAreaLayoutGuide.trailingAnchor,
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

    private func configureMoreMenuButton(
        _ button: UIButton,
        titleKey: String,
        action: Selector
    ) {
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
        button.addTarget(self, action: action, for: .touchUpInside)
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
        button.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular),
            forImageIn: .normal
        )
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.textAlignment = .center
        button.contentHorizontalAlignment = .center
        button.contentVerticalAlignment = .center
        alignImageAboveTitle(button, spacing: 4)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func alignImageAboveTitle(
        _ button: UIButton,
        spacing: CGFloat
    ) {
        guard let imageView = button.imageView,
              let titleLabel = button.titleLabel
        else {
            return
        }

        let imageSize = imageView.intrinsicContentSize
        let titleSize = titleLabel.intrinsicContentSize
        button.imageEdgeInsets = UIEdgeInsets(
            top: -(titleSize.height + spacing),
            left: 0,
            bottom: 0,
            right: -titleSize.width
        )
        button.titleEdgeInsets = UIEdgeInsets(
            top: 0,
            left: -imageSize.width,
            bottom: -(imageSize.height + spacing),
            right: 0
        )
    }

    private func applyMenuPosition() {
        let topTranslation = -(topBar.bounds.height + 1)
        let bottomTranslation = bottomBar.bounds.height + 1
        let floatingHiddenOffset = floatingActionStack.bounds.width
            + Layout.floatingButtonTrailingInset
            + safeAreaInsets.right
            + 1
        topBar.transform = isMenuVisible
            && isTopBarVisible ? .identity
            : CGAffineTransform(translationX: 0, y: topTranslation)
        bottomBar.transform = isMenuVisible
            && isBottomBarVisible ? .identity
            : CGAffineTransform(translationX: 0, y: bottomTranslation)
        floatingActionStack.transform = isMenuVisible
            && isFloatingActionStackVisible ? .identity
            : CGAffineTransform(translationX: floatingHiddenOffset, y: 0)
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

    private func estimatedPageIndex(for chapterProgress: Double) -> Int {
        let last = max(lastPageCount - 1, 0)
        guard last > 0 else {
            return 0
        }
        return min(max(Int((Double(last) * chapterProgress).rounded()), 0), last)
    }

    private func progressText(
        chapterTitle: String,
        chapterProgress: Double,
        globalProgress: Double
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.format", comment: ""),
            chapterTitle,
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

    private func setNavigationButton(
        _ button: UIButton,
        enabled: Bool
    ) {
        button.isEnabled = enabled
        button.alpha = enabled ? 1 : 0.45
    }

    @objc private func closeTapped() {
        setMoreMenuVisible(false, animated: true)
        onClose?()
    }

    @objc private func catalogTapped() {
        setMoreMenuVisible(false, animated: true)
        onCatalog?()
    }

    @objc private func bookmarkTapped() {
        setMoreMenuVisible(false, animated: true)
        onBookmark?()
    }

    @objc private func settingsTapped() {
        setMoreMenuVisible(false, animated: true)
        onSettings?()
    }

    @objc private func previousChapterTapped() {
        setMoreMenuVisible(false, animated: true)
        onPreviousChapter?()
    }

    @objc private func nextChapterTapped() {
        setMoreMenuVisible(false, animated: true)
        onNextChapter?()
    }

    @objc private func autoReadTapped() {
        setMoreMenuVisible(false, animated: true)
        onAutoRead?()
    }

    @objc private func darkModeTapped() {
        setMoreMenuVisible(false, animated: true)
        onDarkMode?()
    }

    @objc private func moreTapped() {
        setMoreMenuVisible(!isMoreMenuVisible, animated: true)
    }

    @objc private func moreBookDetailTapped() {
        setMoreMenuVisible(false, animated: true)
        onMoreBookDetail?()
    }

    @objc private func moreContentSearchTapped() {
        setMoreMenuVisible(false, animated: true)
        onMoreContentSearch?()
    }

    @objc private func moreContentFilterTapped() {
        setMoreMenuVisible(false, animated: true)
        onMoreContentFilter?()
    }

    @objc private func morePageTouchAreasTapped() {
        setMoreMenuVisible(false, animated: true)
        onMorePageTouchAreas?()
    }

    @objc private func progressSliderTouchBegan() {
        isTrackingProgressSlider = true
        let progress = ReaderPageModel.clampedProgress(Double(progressSlider.value))
        updateProgressPreview(
            chapterProgress: progress,
            globalProgress: lastGlobalProgress,
            pageIndex: estimatedPageIndex(for: progress)
        )
        setProgressTooltipVisible(true)
        onProgressSliderBegan?()
    }

    @objc private func progressSliderChanged() {
        let progress = ReaderPageModel.clampedProgress(Double(progressSlider.value))
        updateProgressPreview(
            chapterProgress: progress,
            globalProgress: lastGlobalProgress,
            pageIndex: estimatedPageIndex(for: progress)
        )
        setProgressTooltipVisible(true)
        onProgressSliderChanged?(progress)
    }

    @objc private func progressSliderTouchFinished() {
        isTrackingProgressSlider = false
        setProgressTooltipVisible(false)
        onProgressSliderFinished?(ReaderPageModel.clampedProgress(Double(progressSlider.value)))
    }
}

private extension ReaderV2MenuView {
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
        static let menuSeparatorThickness: CGFloat = 2
    }

    enum MenuStyle {
        static let barBackgroundColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let progressRowBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
        static let separatorColor = UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
        static let separatorEdgeColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
        static let primaryTextColor = UIColor(white: 0.82, alpha: 1)
        static let secondaryTextColor = UIColor(white: 0.58, alpha: 1)
        static let progressTooltipBackgroundColor = UIColor(red: 0.133, green: 0.133, blue: 0.133, alpha: 1)
        static let floatingButtonColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let floatingButtonIconColor = UIColor(white: 0.48, alpha: 1)
    }
}
