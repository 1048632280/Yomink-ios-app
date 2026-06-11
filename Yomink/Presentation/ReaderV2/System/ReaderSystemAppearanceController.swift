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
        refreshStatusBarPreferences()
    }

    func refresh() {
        UIApplication.shared.isIdleTimerDisabled = state.isViewVisible
            && (state.settings.normalized.keepScreenAwake || state.isAutoReading)
        notifyStatusBarHiddenIfNeeded(forceValue: nil)
        refreshStatusBarPreferences()
    }

    static func shouldHideStatusBar(for state: ReaderSystemAppearanceState) -> Bool {
        guard state.isViewVisible else {
            return false
        }
        guard state.settings.normalized.autoHideStatusBar else {
            return false
        }
        if state.isAutoReading || state.isAutoReadPanelVisible {
            return true
        }
        if state.isSettingsPanelVisible {
            return true
        }
        return !state.isMenuVisible
    }

    private func notifyStatusBarHiddenIfNeeded(forceValue: Bool?) {
        let isHidden = forceValue ?? prefersStatusBarHidden
        guard isHidden != lastStatusBarHidden else {
            return
        }
        lastStatusBarHidden = isHidden
        onStatusBarHiddenChange(isHidden)
    }

    private func refreshStatusBarPreferences() {
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
        }
    }
}
