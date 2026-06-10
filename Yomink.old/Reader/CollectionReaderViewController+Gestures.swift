import UIKit

@MainActor
extension CollectionReaderViewController {
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }
        let location = gesture.location(in: view)
        if shouldSuppressNextTapForTextSelection {
            shouldSuppressNextTapForTextSelection = false
            return
        }
        if handleTapForTextSelection(at: location) {
            return
        }
        if isAutoReading {
            if shouldSuppressNextAutoReadTap {
                shouldSuppressNextAutoReadTap = false
                return
            }
            guard !autoReadPanel.frame.contains(location) else {
                return
            }
            guard tapAction(at: location) == .menu else {
                return
            }
            setAutoReadPanelVisible(!isAutoReadPanelVisible, animated: true)
            return
        }
        if isSettingsPanelVisible {
            guard !settingsPanel.frame.contains(location) else {
                return
            }
            setSettingsPanelVisible(false, animated: true)
            return
        }

        if isMenuVisible {
            if isMoreMenuVisible,
               !moreMenuContainer.frame.contains(location),
               !moreButton.convert(moreButton.bounds, to: view).contains(location) {
                setMoreMenuVisible(false, animated: true)
                return
            }
            guard !topBar.frame.contains(location),
                  !bottomBar.frame.contains(location),
                  !floatingActionStack.frame.contains(location) else {
                return
            }
            setMenuVisible(false, animated: true)
            return
        }

        switch tapAction(at: location) {
        case .menu:
            setMenuVisible(!isMenuVisible, animated: true)
        case .previousPage:
            moveToPreviousPage()
        case .nextPage:
            moveToNextPage()
        case .none:
            break
        }
    }

    @objc func handleMoreMenuDismissTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              isMoreMenuVisible else {
            return
        }
        setMoreMenuVisible(false, animated: true)
    }

    @objc func handlePageSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended,
              readerSettings.pageMode == .curl,
              !isMenuVisible,
              !isSettingsPanelVisible,
              !isAutoReading else {
            return
        }
        if gesture.direction == .left {
            moveToNextPage()
        } else if gesture.direction == .right {
            moveToPreviousPage()
        }
    }

    func tapAction(at location: CGPoint) -> ReaderSettings.TouchAreaAction {
        let width = max(view.bounds.width, 1)
        let height = max(view.bounds.height, 1)
        let column = min(max(Int(location.x / (width / 3)), 0), 2)
        let row = min(max(Int(location.y / (height / 3)), 0), 2)
        let index = row * 3 + column
        let map = readerSettings.normalized.touchAreaMap
        guard map.indices.contains(index) else {
            return ReaderSettings.default.touchAreaMap[index]
        }
        return map[index]
    }

    @objc func handleEdgeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard navigationController == nil,
              readerSettings.edgeSwipeBackEnabled,
              gesture.state == .ended else {
            return
        }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        guard translation.x > view.bounds.width * 0.18 || velocity.x > 520 else {
            return
        }
        closeButtonTapped()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === textSelectionLongPressGesture {
            return allowsTextSelectionInteraction
        }
        if isTextSelectionActive,
           gestureRecognizer is UISwipeGestureRecognizer {
            return false
        }
        if isTextSelectionActive,
           gestureRecognizer === collectionView.panGestureRecognizer {
            return false
        }
        if gestureRecognizer === moreMenuDismissTapGesture {
            guard isMoreMenuVisible else {
                return false
            }
            let location = gestureRecognizer.location(in: view)
            let isInReaderChrome = topBar.frame.contains(location)
                || bottomBar.frame.contains(location)
                || floatingActionStack.frame.contains(location)
            return isInReaderChrome
                && !moreMenuContainer.frame.contains(location)
                && !moreButton.convert(moreButton.bounds, to: view).contains(location)
        }
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           settingsControlPanRecognizers.contains(where: { $0 === panGesture }) {
            let velocity = panGesture.velocity(in: settingsPanelScrollView)
            return abs(velocity.y) >= abs(velocity.x)
        }
        if let interactivePopGesture = navigationController?.interactivePopGestureRecognizer,
           gestureRecognizer === interactivePopGesture {
            guard (navigationController?.viewControllers.count ?? 0) > 1 else {
                return false
            }

            if let topViewController = navigationController?.topViewController,
               let readerStackController = navigationStackControllerForReader(),
               topViewController !== readerStackController {
                return true
            }

            return readerSettings.edgeSwipeBackEnabled
        }
        if gestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return navigationController == nil && readerSettings.edgeSwipeBackEnabled
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === autoReadTouchResetGesture
            || otherGestureRecognizer === autoReadTouchResetGesture {
            return true
        }
        return settingsControlPanRecognizers.contains { $0 === gestureRecognizer || $0 === otherGestureRecognizer }
    }
}
