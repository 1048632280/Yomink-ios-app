import UIKit

struct ReaderSystemAppearanceState {
    var settings: ReaderSettings
    var theme: ReaderTheme
    var isViewVisible: Bool
    var isMenuVisible: Bool
    var isSettingsPanelVisible: Bool
    var isAutoReadPanelVisible: Bool
    var isAutoReading: Bool

    static let initial = ReaderSystemAppearanceState(
        settings: .default,
        theme: .standard,
        isViewVisible: false,
        isMenuVisible: false,
        isSettingsPanelVisible: false,
        isAutoReadPanelVisible: false,
        isAutoReading: false
    )
}

@MainActor
final class ReaderSystemAppearanceController {
    weak var hostViewController: UIViewController?
    private let onStatusBarHiddenChange: (Bool) -> Void
    private(set) var state = ReaderSystemAppearanceState.initial
    private(set) var lastStatusBarHidden = false

    init(
        hostViewController: UIViewController? = nil,
        onStatusBarHiddenChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.hostViewController = hostViewController
        self.onStatusBarHiddenChange = onStatusBarHiddenChange
    }

    var prefersStatusBarHidden: Bool {
        Self.shouldHideStatusBar(for: state)
    }

    var preferredStatusBarStyle: UIStatusBarStyle {
        state.theme.isDark ? .lightContent : .darkContent
    }

    var prefersHomeIndicatorAutoHidden: Bool {
        false
    }

    var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        state.settings.normalized.autoHideHomeIndicator ? .bottom : []
    }

    func update(
        settings: ReaderSettings,
        theme: ReaderTheme,
        isViewVisible: Bool,
        isMenuVisible: Bool,
        isSettingsPanelVisible: Bool,
        isAutoReadPanelVisible: Bool,
        isAutoReading: Bool
    ) {
        state = ReaderSystemAppearanceState(
            settings: settings.normalized,
            theme: theme,
            isViewVisible: isViewVisible,
            isMenuVisible: isMenuVisible,
            isSettingsPanelVisible: isSettingsPanelVisible,
            isAutoReadPanelVisible: isAutoReadPanelVisible,
            isAutoReading: isAutoReading
        )
        refresh()
    }

    func reset() {
        state = .initial
        UIApplication.shared.isIdleTimerDisabled = false
        notifyStatusBarHiddenIfNeeded(forceValue: false)
        refreshControllerPreferences()
    }

    func refresh() {
        UIApplication.shared.isIdleTimerDisabled = state.isViewVisible
            && (state.settings.normalized.keepScreenAwake || state.isAutoReading)
        notifyStatusBarHiddenIfNeeded(forceValue: nil)
        refreshControllerPreferences()
    }

    static func shouldHideStatusBar(for state: ReaderSystemAppearanceState) -> Bool {
        guard state.isViewVisible else {
            return false
        }
        if state.isAutoReading {
            return true
        }
        guard state.settings.normalized.autoHideStatusBar else {
            return false
        }
        if state.isMenuVisible,
           !state.isSettingsPanelVisible,
           !state.isAutoReadPanelVisible {
            return false
        }
        return true
    }

    private func notifyStatusBarHiddenIfNeeded(forceValue: Bool?) {
        let isHidden = forceValue ?? prefersStatusBarHidden
        guard isHidden != lastStatusBarHidden else {
            return
        }
        lastStatusBarHidden = isHidden
        onStatusBarHiddenChange(isHidden)
    }

    private func refreshControllerPreferences() {
        var controllers: [UIViewController] = []
        if let hostViewController {
            controllers.append(hostViewController)
            if let navigationController = hostViewController.navigationController {
                controllers.append(navigationController)
            }

            var ancestor = hostViewController.parent
            while let current = ancestor {
                controllers.append(current)
                ancestor = current.parent
            }

            if let rootViewController = hostViewController.view.window?.rootViewController {
                controllers.append(rootViewController)
            }
        }

        var visited = Set<ObjectIdentifier>()
        for controller in controllers {
            guard visited.insert(ObjectIdentifier(controller)).inserted else {
                continue
            }
            controller.setNeedsStatusBarAppearanceUpdate()
            controller.setNeedsUpdateOfHomeIndicatorAutoHidden()
            controller.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }
}
