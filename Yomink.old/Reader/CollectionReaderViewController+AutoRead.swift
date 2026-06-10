import QuartzCore
import UIKit

@MainActor
extension CollectionReaderViewController {
    func makeAutoReadSliderThumbImage(diameter: CGFloat) -> UIImage {
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

    func configureAutoReadPanel() {
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

    func autoReadIcon(named imageName: String, fallbackName: String) -> UIImageView {
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

    func currentAutoReadBaseSpeed() -> CGFloat {
        let value = min(
            max(readerSettings.normalized.autoReadSpeed, ReaderSettings.minimumAutoReadSpeed),
            ReaderSettings.maximumAutoReadSpeed
        )
        return CGFloat(value)
    }

    func isAutoReadVelocityAtBaseSpeed() -> Bool {
        guard isAutoReading else {
            return false
        }
        let baseSpeed = currentAutoReadBaseSpeed()
        let tolerance = max(baseSpeed * 0.02, 1)
        return abs(autoReadVelocity - baseSpeed) <= tolerance
    }

    func resetAutoReadVelocityToBaseSpeed() {
        guard isAutoReading else {
            return
        }
        autoReadVelocity = currentAutoReadBaseSpeed()
        lastAutoReadTimestamp = nil
    }

    func startAutoReading() {
        guard !isAutoReading else {
            setAutoReadPanelVisible(true, animated: true)
            return
        }
        guard !pages.isEmpty else {
            return
        }
        clearTextSelection()
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

    func stopAutoReading(restoreLayout: Bool, animated: Bool) {
        guard isAutoReading || autoReadDisplayLink != nil else {
            return
        }
        clearTextSelection()
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

    func pauseAutoReadingForBackground() {
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

    func pauseAutoReadingForInteractiveReturn() {
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

    func resumeAutoReadingAfterBackgroundIfNeeded() {
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

    func resumeAutoReadingAfterInteractiveReturnCancellationIfNeeded() {
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

    func finishAutoReadingAfterInteractiveReturnCompletion() {
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

    func startAutoReadDisplayLink() {
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

    func invalidateAutoReadDisplayLink() {
        autoReadDisplayLink?.invalidate()
        autoReadDisplayLink = nil
        lastAutoReadTimestamp = nil
    }

    @objc func autoReadDisplayLinkDidTick(_ displayLink: CADisplayLink) {
        guard isAutoReading else {
            invalidateAutoReadDisplayLink()
            return
        }
        let previous = lastAutoReadTimestamp ?? displayLink.timestamp
        let interval = max(0, min(1.0 / 15.0, displayLink.timestamp - previous))
        lastAutoReadTimestamp = displayLink.timestamp
        advanceAutoRead(by: interval)
    }

    func advanceAutoRead(by interval: TimeInterval) {
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

    func displayNeedsProgressSave() -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastAutoReadProgressUpdateTimestamp >= 0.35 else {
            return false
        }
        lastAutoReadProgressUpdateTimestamp = now
        return true
    }

    @objc func autoReadButtonTapped() {
        setMoreMenuVisible(false, animated: true)
        if isAutoReading {
            setAutoReadPanelVisible(!isAutoReadPanelVisible, animated: true)
        } else {
            startAutoReading()
        }
    }

    @objc func autoReadSpeedChanged() {
        var settings = readerSettings
        settings.autoReadSpeed = Double(autoReadSpeedSlider.value)
        readerSettings = settings.normalized
        scheduleSettingsSave()
    }

    @objc func autoReadExitTapped() {
        stopAutoReading(restoreLayout: true, animated: true)
    }

    @objc func handleAutoReadTouchReset(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              isAutoReading else {
            return
        }
        shouldSuppressNextAutoReadTap = !isAutoReadVelocityAtBaseSpeed()
        resetAutoReadVelocityToBaseSpeed()
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
        // 方向中 +y 对应 contentOffset.y 增大(向下翻),与自动阅读方向一致。
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
}
