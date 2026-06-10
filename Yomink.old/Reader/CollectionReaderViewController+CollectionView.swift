import UIKit

@MainActor
extension CollectionReaderViewController {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard pages.indices.contains(indexPath.item),
              let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CollectionReaderPageCell.reuseIdentifier,
                for: indexPath
              ) as? CollectionReaderPageCell else {
            return UICollectionViewCell()
        }
        cell.configure(
            page: pages[indexPath.item],
            settings: readerSettings.normalized,
            layout: displayLayoutForCurrentMode(),
            widgetSnapshot: pageWidgetSnapshot(for: pages[indexPath.item]),
            widgetLayout: widgetLayoutConfiguration(),
            showsWidgets: !usesVerticalScrolling
        )
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard collectionView.isDragging || collectionView.isDecelerating || isAutoReading else {
            return
        }
        if indexPath.item <= 1 {
            loadPreviousPageIfNeeded()
        }
        if indexPath.item >= pages.count - 2 {
            loadNextPageIfNeeded()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView,
              !isApplyingProgrammaticScroll else {
            return
        }
        updateCurrentPageFromVisiblePage()
        if !isAutoReading {
            prefetchPagesNearCurrent()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else {
            return
        }
        finishPageTurn()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        clearTextSelection()
        flushPendingPageInsertions()
        snapToNearestHorizontalPageIfNeeded()
        pendingTapTargetPageIndex = nil
        updateCurrentPageFromVisiblePage()
        if isAutoReading {
            lastAutoReadTimestamp = nil
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        if usesVerticalScrolling {
            return CGSize(
                width: collectionView.bounds.width,
                height: verticalExtentForPage(at: indexPath.item)
            )
        }
        return collectionView.bounds.size
    }
}
