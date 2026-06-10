import QuartzCore
import UIKit

@MainActor
final class ReaderAutoReadController {
    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var lastProgressSaveTimestamp: CFTimeInterval = 0
    private(set) var isReading = false
    private(set) var isPausedForBackground = false
    private(set) var isPausedForContentLoad = false
    private(set) var speed: CGFloat = CGFloat(ReaderSettings.default.autoReadSpeed)

    var onScrollTick: (() -> Void)?
    var onProgressSaveNeeded: (() -> Void)?
    var onReachedEnd: (() -> Bool)?

    var hasDisplayLink: Bool {
        displayLink != nil
    }

    deinit {
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
        isPausedForContentLoad = false
        startDisplayLinkIfNeeded()
    }

    func stop() {
        invalidateDisplayLink()
        isReading = false
        isPausedForBackground = false
        isPausedForContentLoad = false
        scrollView = nil
    }

    func pauseForBackground() {
        guard isReading else {
            return
        }
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
        if !isPausedForContentLoad {
            startDisplayLinkIfNeeded()
        }
    }

    func resumeAfterContentLoadIfNeeded(scrollView: UIScrollView) {
        guard isReading,
              isPausedForContentLoad else {
            return
        }
        self.scrollView = scrollView
        isPausedForContentLoad = false
        if !isPausedForBackground {
            startDisplayLinkIfNeeded()
        }
    }

    func updateSpeed(_ speed: Double) {
        self.speed = Self.normalizedSpeed(speed)
    }

    func advance(by interval: TimeInterval) {
        guard isReading,
              let scrollView,
              !scrollView.isDragging,
              !scrollView.isTracking,
              !scrollView.isDecelerating else {
            return
        }

        let clampedInterval = max(0, min(1.0 / 15.0, interval))
        let distance = speed * CGFloat(clampedInterval)
        guard distance > 0 else {
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

        let updatedMaxOffsetY = Self.maxOffsetY(for: scrollView)
        if scrollView.contentOffset.y >= updatedMaxOffsetY,
           proposedY >= updatedMaxOffsetY {
            pauseForContentLoad()
            let shouldKeepReading = onReachedEnd?() ?? false
            if !shouldKeepReading {
                stop()
            }
        }
    }

    private func pauseForContentLoad() {
        guard isReading else {
            return
        }
        invalidateDisplayLink()
        isPausedForContentLoad = true
    }

    private static func minOffsetY(for scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private static func maxOffsetY(for scrollView: UIScrollView) -> CGFloat {
        max(
            minOffsetY(for: scrollView),
            scrollView.contentSize.height
                + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
        )
    }

    static func normalizedSpeed(_ speed: Double) -> CGFloat {
        CGFloat(
            min(
                max(speed, ReaderSettings.minimumAutoReadSpeed),
                ReaderSettings.maximumAutoReadSpeed
            )
        )
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil else {
            return
        }
        lastTimestamp = nil
        lastProgressSaveTimestamp = 0
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
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func invalidateDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    @objc private func displayLinkDidTick(_ displayLink: CADisplayLink) {
        guard isReading else {
            invalidateDisplayLink()
            return
        }
        let previous = lastTimestamp ?? displayLink.timestamp
        let interval = displayLink.timestamp - previous
        lastTimestamp = displayLink.timestamp
        advance(by: interval)
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
