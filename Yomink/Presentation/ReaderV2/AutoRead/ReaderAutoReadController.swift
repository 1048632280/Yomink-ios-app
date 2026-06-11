import QuartzCore
import UIKit

@MainActor
final class ReaderAutoReadController {
    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var lastProgressSaveTimestamp: CFTimeInterval = 0
    private var pendingStartTask: Task<Void, Never>?
    private var updateCounter = 0
    private var updateInterval = 0
    private var updatePixels: CGFloat = 0
    private(set) var isReading = false
    private(set) var isPausedForBackground = false
    private(set) var isPausedForUserInteraction = false
    private(set) var speed: CGFloat = CGFloat(ReaderSettings.default.autoReadSpeed)

    var onScrollTick: (() -> Void)?
    var onProgressSaveNeeded: (() -> Void)?
    var onReachedEnd: (() -> Void)?

    var hasDisplayLink: Bool {
        displayLink != nil
    }

    deinit {
        pendingStartTask?.cancel()
        displayLink?.invalidate()
    }

    func start(
        scrollView: UIScrollView,
        speed: Double
    ) {
        self.scrollView = scrollView
        self.speed = Self.normalizedSpeed(speed)
        isReading = true
        isPausedForBackground = false
        isPausedForUserInteraction = false
        rebuildAutoReadStep()
        scheduleDisplayLinkStart()
    }

    func stop() {
        pendingStartTask?.cancel()
        pendingStartTask = nil
        invalidateDisplayLink()
        isReading = false
        isPausedForBackground = false
        isPausedForUserInteraction = false
        scrollView = nil
    }

    func pauseForBackground() {
        guard isReading else {
            return
        }
        pendingStartTask?.cancel()
        pendingStartTask = nil
        invalidateDisplayLink()
        isPausedForBackground = true
        onProgressSaveNeeded?()
    }

    func resumeAfterBackgroundIfNeeded(scrollView: UIScrollView) {
        guard isReading,
              isPausedForBackground else {
            return
        }
        self.scrollView = scrollView
        isPausedForBackground = false
        if !isPausedForUserInteraction {
            startDisplayLinkIfNeeded()
        }
    }

    func pauseForUserInteraction() {
        guard isReading else {
            return
        }
        isPausedForUserInteraction = true
    }

    func resumeAfterUserInteractionIfNeeded(scrollView: UIScrollView) {
        guard isReading,
              isPausedForUserInteraction else {
            return
        }
        self.scrollView = scrollView
        isPausedForUserInteraction = false
        if !isPausedForBackground {
            startDisplayLinkIfNeeded()
        }
    }

    func updateSpeed(_ speed: Double) {
        self.speed = Self.normalizedSpeed(speed)
        rebuildAutoReadStep()
    }

    func advance() {
        guard isReading,
              let scrollView,
              !isPausedForUserInteraction,
              !scrollView.isDragging,
              !scrollView.isTracking,
              !scrollView.isDecelerating else {
            return
        }

        if updateInterval > 0 {
            updateCounter += 1
            let mod = updateInterval + 1
            guard updateCounter % mod == 1 else {
                return
            }
        }

        let distance = updatePixels
        guard distance > 0,
              scrollView.contentSize.height > 0 else {
            return
        }

        let minOffsetY = Self.minOffsetY(for: scrollView)
        let maxOffsetY = Self.maxOffsetY(for: scrollView)
        let proposedY = scrollView.contentOffset.y + distance
        let nextOffsetY = min(maxOffsetY, max(minOffsetY, proposedY))
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: nextOffsetY),
            animated: false
        )
        onScrollTick?()

        if needsProgressSave() {
            onProgressSaveNeeded?()
        }

        let pageHeight = Self.autoReadPageHeight(for: scrollView)
        let nearBottom = nextOffsetY + pageHeight >= scrollView.contentSize.height
        if nearBottom {
            onReachedEnd?()
        }
    }

    private static func minOffsetY(for scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private static func maxOffsetY(for scrollView: UIScrollView) -> CGFloat {
        let pageHeight = autoReadPageHeight(for: scrollView)
        max(
            minOffsetY(for: scrollView),
            scrollView.contentSize.height - pageHeight
        )
    }

    private static func autoReadPageHeight(for scrollView: UIScrollView) -> CGFloat {
        let footerHeight = (scrollView as? UITableView)?.tableFooterView?.bounds.height ?? 0
        return max(1, scrollView.bounds.height - footerHeight - 5)
    }

    static func normalizedSpeed(_ speed: Double) -> CGFloat {
        CGFloat(ReaderSettings.normalizedAutoReadSpeed(speed))
    }

    private func scheduleDisplayLinkStart() {
        pendingStartTask?.cancel()
        pendingStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.isReading,
                  !self.isPausedForBackground,
                  !self.isPausedForUserInteraction else {
                return
            }
            self.startDisplayLinkIfNeeded()
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else {
            return
        }
        lastProgressSaveTimestamp = 0
        rebuildAutoReadStep()
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidTick(_:)))
        if #available(iOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: 60,
                preferred: 60
            )
        } else {
            displayLink.preferredFramesPerSecond = 60
        }
        displayLink.add(to: .main, forMode: .default)
        self.displayLink = displayLink
    }

    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkDidTick(_: CADisplayLink) {
        guard isReading else {
            invalidateDisplayLink()
            return
        }
        advance()
    }

    private func rebuildAutoReadStep() {
        let grade = Int(floor(Self.normalizedSpeed(Double(speed))))
        let onePixel = 1.0 / max(UIScreen.main.scale, 1)
        updateCounter = 0
        if grade <= 4 {
            updateInterval = 5 - grade
            updatePixels = onePixel
        } else {
            updateInterval = 0
            updatePixels = CGFloat(grade - 4) * onePixel
        }
    }

    private func needsProgressSave() -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastProgressSaveTimestamp >= 0.35 else {
            return false
        }
        lastProgressSaveTimestamp = now
        return true
    }
}
