import UIKit

@MainActor
extension CollectionReaderViewController {
    var isTextSelectionActive: Bool {
        textSelectionOverlay.hasSelection
    }

    var allowsTextSelectionInteraction: Bool {
        !isAutoReading
            && !isSettingsPanelVisible
            && !isAutoReadPanelVisible
            && !isMoreMenuVisible
            && pageTask == nil
    }

    func configureTextSelection() {
        textSelectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        textSelectionOverlay.onCopy = { [weak self] in
            self?.copySelectedText()
        }
        textSelectionOverlay.onSearch = { [weak self] in
            self?.searchSelectedText()
        }
        textSelectionOverlay.onFilter = { [weak self] in
            self?.filterSelectedText()
        }
        view.addSubview(textSelectionOverlay)
        NSLayoutConstraint.activate([
            textSelectionOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            textSelectionOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textSelectionOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textSelectionOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let longPressGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleTextSelectionLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.45
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.delegate = self
        collectionView.addGestureRecognizer(longPressGesture)
        textSelectionLongPressGesture = longPressGesture
    }

    func clearTextSelection() {
        textSelectionOverlay.clearSelection()
    }

    func handleTapForTextSelection(at location: CGPoint) -> Bool {
        guard isTextSelectionActive else {
            return false
        }
        if textSelectionOverlay.selectionContains(location) {
            textSelectionOverlay.showMenu(animated: true)
        } else {
            clearTextSelection()
        }
        return true
    }

    @objc func handleTextSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              allowsTextSelectionInteraction else {
            return
        }

        let locationInView = gesture.location(in: view)
        guard !topBar.frame.contains(locationInView),
              !bottomBar.frame.contains(locationInView),
              !floatingActionStack.frame.contains(locationInView),
              !settingsPanel.frame.contains(locationInView),
              !autoReadPanel.frame.contains(locationInView) else {
            return
        }

        let locationInCollection = gesture.location(in: collectionView)
        guard let selectionTarget = textSelectionTarget(at: locationInCollection),
              let boundary = selectionTarget.context.characterBoundary(
                at: selectionTarget.locationInCell
              ),
              let range = selectionTarget.context.paragraphRange(containingUTF16Index: boundary) else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        shouldSuppressNextTapForTextSelection = true
        setMenuVisible(false, animated: false)
        setMoreMenuVisible(false, animated: false)
        let pageFrame = selectionTarget.cell.convert(
            selectionTarget.cell.bounds,
            to: view
        )
        textSelectionOverlay.showSelection(
            pageFrame: pageFrame,
            context: selectionTarget.context,
            range: range
        )
        refreshReaderOverlayOrdering()
    }

    private func textSelectionTarget(
        at locationInCollection: CGPoint
    ) -> (
        cell: UICollectionViewCell,
        context: ReaderTextSelectionPageContext,
        locationInCell: CGPoint
    )? {
        guard let indexPath = collectionView.indexPathForItem(at: locationInCollection),
              pages.indices.contains(indexPath.item),
              let cell = collectionView.cellForItem(at: indexPath) else {
            return nil
        }

        let page = pages[indexPath.item]
        let locationInCell = collectionView.convert(locationInCollection, to: cell)
        let layout = usesVerticalScrolling
            ? displayLayoutForCurrentMode()
            : page.contentLayout
        let context = ReaderTextSelectionPageContext(
            text: page.text,
            attributedText: page.attributedText,
            layout: layout,
            pageBounds: cell.bounds
        )

        guard context.contentRect.insetBy(dx: 0, dy: -10).contains(locationInCell) else {
            return nil
        }
        return (cell, context, locationInCell)
    }

    private func copySelectedText() {
        let text = textSelectionOverlay.selectedText
        guard !text.isEmpty else {
            clearTextSelection()
            return
        }
        UIPasteboard.general.string = text
        clearTextSelection()
    }

    private func searchSelectedText() {
        let text = textSelectionOverlay.selectedText
        guard !text.isEmpty else {
            clearTextSelection()
            return
        }
        clearTextSelection()
        showContentSearch(initialKeyword: text)
    }

    private func filterSelectedText() {
        let text = textSelectionOverlay.selectedText
        guard !text.isEmpty else {
            clearTextSelection()
            return
        }
        clearTextSelection()
        showFilterRules(initialSource: text)
    }
}
