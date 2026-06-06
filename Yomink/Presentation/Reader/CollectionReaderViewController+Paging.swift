import UIKit

@MainActor
extension CollectionReaderViewController {
    enum TapPageDirection {
        case previous
        case next
    }

    struct PagingLayoutSnapshot: @unchecked Sendable {
        let viewportSize: CGSize
        let safeAreaInsets: UIEdgeInsets
        let widgetInsets: UIEdgeInsets
        let isVerticalViewport: Bool

        func isMeaningfullyDifferent(from other: PagingLayoutSnapshot) -> Bool {
            isVerticalViewport != other.isVerticalViewport
                || Self.differs(viewportSize.width, other.viewportSize.width, tolerance: 1)
                || Self.differs(viewportSize.height, other.viewportSize.height, tolerance: 1)
                || Self.insetsDiffer(safeAreaInsets, other.safeAreaInsets, tolerance: 0.5)
                || Self.insetsDiffer(widgetInsets, other.widgetInsets, tolerance: 0.5)
        }

        func canProvideHorizontalFallback(for current: PagingLayoutSnapshot) -> Bool {
            !isVerticalViewport
                && !current.isVerticalViewport
                && !Self.differs(viewportSize.width, current.viewportSize.width, tolerance: 1)
                && !Self.differs(viewportSize.height, current.viewportSize.height, tolerance: 1)
                && !Self.insetsDiffer(widgetInsets, current.widgetInsets, tolerance: 0.5)
        }

        private static func differs(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat) -> Bool {
            abs(lhs - rhs) > tolerance
        }

        private static func insetsDiffer(
            _ lhs: UIEdgeInsets,
            _ rhs: UIEdgeInsets,
            tolerance: CGFloat
        ) -> Bool {
            differs(lhs.top, rhs.top, tolerance: tolerance)
                || differs(lhs.left, rhs.left, tolerance: tolerance)
                || differs(lhs.bottom, rhs.bottom, tolerance: tolerance)
                || differs(lhs.right, rhs.right, tolerance: tolerance)
        }
    }

    func currentPagingLayoutSnapshot() -> PagingLayoutSnapshot? {
        let viewportSize = collectionView.bounds.size
        guard viewportSize.width > 1,
              viewportSize.height > 1 else {
            return nil
        }
        return PagingLayoutSnapshot(
            viewportSize: viewportSize,
            safeAreaInsets: view.safeAreaInsets,
            widgetInsets: widgetContentInsets(),
            isVerticalViewport: usesVerticalScrolling
        )
    }

    private func pagingLayoutSnapshotForPageLoad() -> PagingLayoutSnapshot? {
        guard let currentSnapshot = currentPagingLayoutSnapshot() else {
            return nil
        }
        if !isReaderActiveTopController,
           let stableSnapshot = stableHorizontalPagingLayoutSnapshot,
           stableSnapshot.canProvideHorizontalFallback(for: currentSnapshot) {
            return stableSnapshot
        }
        return currentSnapshot
    }

    private func rememberPagingLayoutSnapshot(_ snapshot: PagingLayoutSnapshot) {
        guard !isMenuVisible else {
            return
        }
        lastPagingLayoutSnapshot = snapshot
        if !snapshot.isVerticalViewport {
            stableHorizontalPagingLayoutSnapshot = snapshot
        }
    }

    func openPage(
        absoluteOffset: Int,
        generation: Int? = nil,
        fileStore: AppFileStore? = nil,
        showsLoadingIndicator: Bool = true
    ) {
        guard !chapters.isEmpty else {
            showLoading(false)
            return
        }
        guard let layoutSnapshot = pagingLayoutSnapshotForPageLoad() else {
            pendingRestoreAbsoluteOffset = absoluteOffset
            if showsLoadingIndicator {
                showLoading(true)
            }
            return
        }

        pendingRestoreAbsoluteOffset = nil
        pageTask?.cancel()
        pendingPagePrepends.removeAll()
        pendingTapTargetPageIndex = nil
        let activeGeneration = generation ?? {
            pagingGeneration += 1
            return pagingGeneration
        }()
        let requestOffset = min(max(absoluteOffset, 0), max(chapters.last?.endOffset ?? 1, 1) - 1)
        let targetBook = book
        let loadedChapters = chapters
        let activeRules = filterRules
        let settings = readerSettings.normalized
        let viewportSize = layoutSnapshot.viewportSize
        let safeAreaInsets = layoutSnapshot.safeAreaInsets
        let widgetInsets = layoutSnapshot.widgetInsets
        let isVerticalViewport = layoutSnapshot.isVerticalViewport
        let appFileStore = fileStore ?? self.fileStore
        didReachEndOfBook = false
        isLoadingNextPage = true
        if showsLoadingIndicator {
            showLoading(true)
        }

        pageTask = Task { [weak self] in
            do {
                let page = try await CollectionReaderPaginator.makePage(
                    book: targetBook,
                    chapters: loadedChapters,
                    absoluteOffset: requestOffset,
                    settings: settings,
                    filterRules: activeRules,
                    viewportSize: viewportSize,
                    safeAreaInsets: safeAreaInsets,
                    widgetInsets: widgetInsets,
                    isVerticalViewport: isVerticalViewport,
                    fileStore: appFileStore
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.pages = [page]
                    self.currentPage = page
                    self.collectionView.reloadData()
                    self.collectionView.layoutIfNeeded()
                    self.collectionView.setContentOffset(self.contentOffset(forPageAt: 0), animated: false)
                    if self.isReaderActiveTopController {
                        self.rememberPagingLayoutSnapshot(layoutSnapshot)
                    }
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                    self.recordBookOpenedIfNeeded()
                    self.prefetchPagesNearCurrent()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == activeGeneration else {
                        return
                    }
                    self.pageTask = nil
                    self.showLoading(false)
                    self.updateSessionState(isLoadingNextPage: false)
                    self.showError(error)
                }
            }
        }
    }

    func reopen(atAbsoluteOffset offset: Int, enforceChapterBoundary _: Bool) {
        guard didStartOpening else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: offset, generation: pagingGeneration)
    }

    func loadNextPageIfNeeded(scrollAfterLoading: Bool = false) {
        guard pageTask == nil,
              !didReachEndOfBook,
              let lastPage = pages.last else {
            return
        }
        guard lastPage.endAbsoluteOffset < (chapters.last?.endOffset ?? 0) else {
            didReachEndOfBook = true
            updateSessionState(isLoadingNextPage: false)
            return
        }
        if scrollAfterLoading {
            pendingTapTargetPageIndex = lastPage.pageIndex + 1
        }
        let targetLocalPageIndex = lastPage.localPageIndex + 1 < lastPage.chapterPageCount
            ? lastPage.localPageIndex + 1
            : nil
        loadPage(
            absoluteOffset: lastPage.endAbsoluteOffset,
            pageIndex: lastPage.pageIndex + 1,
            insertingAtEnd: true,
            targetLocalPageIndex: targetLocalPageIndex
        )
    }

    func loadPreviousPageIfNeeded(scrollAfterLoading: Bool = false) {
        guard pageTask == nil,
              let firstPage = leadingBoundaryPage(),
              firstPage.startAbsoluteOffset > 0 else {
            return
        }

        if scrollAfterLoading {
            pendingTapTargetPageIndex = firstPage.pageIndex - 1
        }
        let targetLocalPageIndex = firstPage.localPageIndex > 0
            ? firstPage.localPageIndex - 1
            : nil
        let targetOffset = previousPageStartOffset(before: firstPage.startAbsoluteOffset)
        loadPage(
            absoluteOffset: targetOffset,
            pageIndex: firstPage.pageIndex - 1,
            insertingAtEnd: false,
            targetLocalPageIndex: targetLocalPageIndex
        )
    }

    private func loadPage(
        absoluteOffset: Int,
        pageIndex: Int,
        insertingAtEnd: Bool,
        targetLocalPageIndex: Int? = nil
    ) {
        let requestOffset = min(max(absoluteOffset, 0), max(chapters.last?.endOffset ?? 1, 1) - 1)
        let generation = pagingGeneration
        let targetBook = book
        let loadedChapters = chapters
        let activeRules = filterRules
        let settings = readerSettings.normalized
        guard let layoutSnapshot = pagingLayoutSnapshotForPageLoad() else {
            return
        }
        let viewportSize = layoutSnapshot.viewportSize
        let safeAreaInsets = layoutSnapshot.safeAreaInsets
        let widgetInsets = layoutSnapshot.widgetInsets
        let isVerticalViewport = layoutSnapshot.isVerticalViewport
        let appFileStore = fileStore
        isLoadingNextPage = insertingAtEnd
        updateSessionState(isLoadingNextPage: insertingAtEnd)

        pageTask = Task { [weak self] in
            do {
                let page = try await CollectionReaderPaginator.makePage(
                    book: targetBook,
                    chapters: loadedChapters,
                    absoluteOffset: requestOffset,
                    forcedPageIndex: pageIndex,
                    settings: settings,
                    filterRules: activeRules,
                    viewportSize: viewportSize,
                    safeAreaInsets: safeAreaInsets,
                    widgetInsets: widgetInsets,
                    isVerticalViewport: isVerticalViewport,
                    targetLocalPageIndex: targetLocalPageIndex,
                    fileStore: appFileStore
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == generation else {
                        return
                    }
                    self.pageTask = nil
                    if self.isReaderActiveTopController {
                        self.rememberPagingLayoutSnapshot(layoutSnapshot)
                    }
                    if insertingAtEnd {
                        self.appendPage(page)
                    } else {
                        self.prependPage(page)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.pagingGeneration == generation else {
                        return
                    }
                    self.pageTask = nil
                    if !(error is CancellationError) {
                        self.showError(error)
                    }
                    self.updateSessionState(isLoadingNextPage: false)
                }
            }
        }
    }

    private func appendPage(_ page: CollectionReaderPage) {
        if pages.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset })
            || pendingPagePrepends.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset }) {
            updateSessionState(isLoadingNextPage: false)
            return
        }
        // 尾部 append 立即提交,但用 performWithoutAnimation 关闭默认渐入,
        // 避免快速滑动时刚追到新 cell 还没 fade 完就被瞄到半透明状态。
        // insertItems 只为新增的 indexPath 生成布局属性,不动 contentOffset、不改已有 cell 的 indexPath,
        // paging snap 锚点保持不变,pages 在滑动期间可连续增长。
        let newIndexPath = IndexPath(item: pages.count, section: 0)
        UIView.performWithoutAnimation {
            self.pages.append(page)
            self.collectionView.insertItems(at: [newIndexPath])
        }
        // 头部修剪在 defer 窗口里跳过(它会平移 contentOffset 并改 cell indexPath,
        // 是"前一页瞬变 + 卡半页"的直接元凶)。flush 时统一补做。
        if !shouldDeferPageMutationForActivePaging,
           let plan = planPrefixTrim() {
            applyPrefixTrim(plan)
        }
        updateSessionState(isLoadingNextPage: false)
        if pendingTapTargetPageIndex == page.pageIndex,
           let index = pages.firstIndex(of: page) {
            pendingTapTargetPageIndex = nil
            turnToPage(at: index, direction: .next)
        }
        // 静止状态下显式接力预取:scrollViewDidScroll 此刻不会被触发,
        // 必须主动延伸链条,否则目录跳转 / 点击翻页后只会装载单张邻页。
        if !shouldDeferPageMutationForActivePaging {
            prefetchPagesNearCurrent()
        }
    }

    private func prependPage(_ page: CollectionReaderPage) {
        if pages.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset })
            || pendingPagePrepends.contains(where: { $0.startAbsoluteOffset == page.startAbsoluteOffset }) {
            updateSessionState(isLoadingNextPage: false)
            return
        }
        // 头部 prepend 必然要平移 contentOffset(把所有已有 cell 往后挪一页),
        // 拖动中做这件事一定会破坏 paging snap;挂起到静止时再做。
        if shouldDeferPageMutationForActivePaging {
            pendingPagePrepends.append(page)
            updateSessionState(isLoadingNextPage: false)
            prefetchPagesNearCurrent()
            return
        }
        let extent = usesVerticalScrolling
            ? verticalExtent(for: page)
            : pageExtentForCurrentMode()
        let preservedCurrentPage = currentPage
        // 用 insertItems + 同帧 setContentOffset 替代 reloadData:
        // 不销毁已有可见 cell,杜绝快速点击 / 横滑回弹时的瞬白闪烁。
        // performWithoutAnimation 同时关闭默认插入动画和 contentOffset 平移动画,保证视觉上原页面不动。
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.insert(page, at: 0)
                self.collectionView.insertItems(at: [IndexPath(item: 0, section: 0)])
                if let plan = self.planSuffixTrim() {
                    self.applySuffixTrim(plan)
                }
                if extent > 0 {
                    let adjusted = self.usesVerticalScrolling
                        ? CGPoint(
                            x: self.collectionView.contentOffset.x,
                            y: self.collectionView.contentOffset.y + extent
                        )
                        : CGPoint(
                            x: self.collectionView.contentOffset.x + extent,
                            y: self.collectionView.contentOffset.y
                        )
                    self.collectionView.setContentOffset(adjusted, animated: false)
                }
            }
        }
        restoreCurrentPageAfterProgrammaticMutation(preservedCurrentPage)
        updateSessionState(isLoadingNextPage: false)
        if pendingTapTargetPageIndex == page.pageIndex,
           let index = pages.firstIndex(of: page) {
            pendingTapTargetPageIndex = nil
            turnToPage(at: index, direction: .previous)
        }
        // 同 appendPage:静止状态下接力预取另一方向(或同方向再装一张),
        // 是修复目录跳转后链条断裂的关键。
        prefetchPagesNearCurrent()
    }

    private var shouldDeferPageMutationForActivePaging: Bool {
        guard !isAutoReading,
              readerSettings.pageMode == .paged || readerSettings.pageMode == .curl else {
            return false
        }
        return collectionView.isDragging
            || collectionView.isTracking
            || collectionView.isDecelerating
    }

    func flushPendingPageInsertions() {
        if !pages.isEmpty,
           let plan = planPrefixTrim() {
            applyPrefixTrim(plan)
        }
        guard !pendingPagePrepends.isEmpty else {
            return
        }
        let pending = Array(pendingPagePrepends.reversed())
        pendingPagePrepends.removeAll()

        let extent = pending.reduce(CGFloat(0)) { result, page in
            result + (
                usesVerticalScrolling
                    ? verticalExtent(for: page)
                    : pageExtentForCurrentMode()
            )
        }
        let insertedIndexPaths = pending.indices.map { IndexPath(item: $0, section: 0) }
        let preservedCurrentPage = currentPage
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.insert(contentsOf: pending, at: 0)
                self.collectionView.insertItems(at: insertedIndexPaths)
                if let plan = self.planSuffixTrim() {
                    self.applySuffixTrim(plan)
                }
                if extent > 0 {
                    let adjusted = self.usesVerticalScrolling
                        ? CGPoint(
                            x: self.collectionView.contentOffset.x,
                            y: self.collectionView.contentOffset.y + extent
                        )
                        : CGPoint(
                            x: self.collectionView.contentOffset.x + extent,
                            y: self.collectionView.contentOffset.y
                        )
                    self.collectionView.setContentOffset(adjusted, animated: false)
                }
            }
        }
        restoreCurrentPageAfterProgrammaticMutation(preservedCurrentPage)
        updateSessionState(isLoadingNextPage: false)
    }

    private func previousPageStartOffset(before absoluteOffset: Int) -> Int {
        max(0, absoluteOffset - 1)
    }

    private struct PrefixTrimPlan {
        let removeCount: Int
        let removedDistance: CGFloat
    }

    private func planPrefixTrim() -> PrefixTrimPlan? {
        guard pages.count > Layout.maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage),
              currentIndex > 3 else {
            return nil
        }
        let overflow = pages.count - Layout.maximumResidentPages
        let removableBeforeCurrent = max(0, currentIndex - 3)
        let removeCount = min(overflow, removableBeforeCurrent)
        guard removeCount > 0 else {
            return nil
        }
        let removedDistance = usesVerticalScrolling
            ? pages.prefix(removeCount).reduce(CGFloat(0)) { result, page in
                result + verticalExtent(for: page)
            }
            : CGFloat(removeCount) * pageExtentForCurrentMode()
        return PrefixTrimPlan(removeCount: removeCount, removedDistance: removedDistance)
    }

    private func applyPrefixTrim(_ plan: PrefixTrimPlan) {
        let removedIndexPaths = (0..<plan.removeCount).map { IndexPath(item: $0, section: 0) }
        UIView.performWithoutAnimation {
            self.performProgrammaticPageMutation {
                self.pages.removeFirst(plan.removeCount)
                self.collectionView.deleteItems(at: removedIndexPaths)
                self.adjustContentOffsetAfterRemovingPrefix(distance: plan.removedDistance)
            }
        }
    }

    private struct SuffixTrimPlan {
        let removeCount: Int
    }

    private func planSuffixTrim() -> SuffixTrimPlan? {
        guard pages.count > Layout.maximumResidentPages,
              let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return nil
        }
        let overflow = pages.count - Layout.maximumResidentPages
        let removableAfterCurrent = max(0, pages.count - currentIndex - 4)
        let removeCount = min(overflow, removableAfterCurrent)
        guard removeCount > 0 else {
            return nil
        }
        return SuffixTrimPlan(removeCount: removeCount)
    }

    private func applySuffixTrim(_ plan: SuffixTrimPlan) {
        let startIndex = pages.count - plan.removeCount
        let removedIndexPaths = (startIndex..<pages.count).map { IndexPath(item: $0, section: 0) }
        UIView.performWithoutAnimation {
            self.pages.removeLast(plan.removeCount)
            self.collectionView.deleteItems(at: removedIndexPaths)
        }
    }

    private func adjustContentOffsetAfterRemovingPrefix(distance: CGFloat) {
        guard distance > 0 else {
            return
        }
        let minimumY = -collectionView.contentInset.top
        let adjusted = usesVerticalScrolling
            ? CGPoint(x: collectionView.contentOffset.x, y: max(minimumY, collectionView.contentOffset.y - distance))
            : CGPoint(x: max(0, collectionView.contentOffset.x - distance), y: collectionView.contentOffset.y)
        collectionView.setContentOffset(adjusted, animated: false)
    }

    private func performProgrammaticPageMutation(_ mutation: () -> Void) {
        let wasApplyingProgrammaticScroll = isApplyingProgrammaticScroll
        isApplyingProgrammaticScroll = true
        defer {
            isApplyingProgrammaticScroll = wasApplyingProgrammaticScroll
        }
        mutation()
    }

    private func restoreCurrentPageAfterProgrammaticMutation(_ page: CollectionReaderPage?) {
        guard let page,
              pages.contains(page) else {
            updateCurrentPageFromVisiblePage()
            return
        }
        currentPage = page
    }

    func prefetchPagesNearCurrent() {
        guard let currentPage,
              let index = pages.firstIndex(of: currentPage) else {
            return
        }
        let leadingCount = index + pendingPagePrepends.count
        let trailingCount = pages.count - index - 1

        let needsLeading = leadingCount <= Layout.horizontalPrefetchDistance
        let needsTrailing = trailingCount <= Layout.horizontalPrefetchDistance

        if needsLeading && needsTrailing {
            if trailingCount <= leadingCount {
                loadNextPageIfNeeded()
                if pageTask != nil {
                    return
                }
                loadPreviousPageIfNeeded()
            } else {
                loadPreviousPageIfNeeded()
                if pageTask != nil {
                    return
                }
                loadNextPageIfNeeded()
            }
            return
        }

        if needsLeading {
            loadPreviousPageIfNeeded()
            if pageTask != nil {
                return
            }
        }
        if needsTrailing {
            loadNextPageIfNeeded()
        }
    }

    private func leadingBoundaryPage() -> CollectionReaderPage? {
        pendingPagePrepends.last ?? pages.first
    }

    func configureCollectionViewForActiveSettings() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        if isAutoReading {
            configureCollectionViewForAutoReading()
            updateFixedWidgetOverlay()
            return
        }
        let contentInsets: UIEdgeInsets
        switch readerSettings.pageMode {
        case .paged:
            layout.scrollDirection = .horizontal
            collectionView.isScrollEnabled = true
            collectionView.isPagingEnabled = true
            collectionView.alwaysBounceVertical = false
            contentInsets = .zero
        case .curl:
            layout.scrollDirection = .horizontal
            collectionView.isScrollEnabled = false
            collectionView.isPagingEnabled = true
            collectionView.alwaysBounceVertical = false
            contentInsets = .zero
        case .scroll:
            layout.scrollDirection = .vertical
            collectionView.isScrollEnabled = true
            collectionView.isPagingEnabled = false
            collectionView.alwaysBounceVertical = true
            contentInsets = verticalContinuousInsets()
        }
        collectionView.contentInset = contentInsets
        collectionView.scrollIndicatorInsets = contentInsets
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        updateVerticalContentCovers()
        updateFixedWidgetOverlay()
    }

    func configureCollectionViewForAutoReading() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        layout.scrollDirection = .vertical
        collectionView.isScrollEnabled = true
        collectionView.isPagingEnabled = false
        collectionView.alwaysBounceVertical = true
        let contentInsets = verticalContinuousInsets()
        collectionView.contentInset = contentInsets
        collectionView.scrollIndicatorInsets = contentInsets
        collectionView.showsVerticalScrollIndicator = false
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        updateVerticalContentCovers()
        updateFixedWidgetOverlay()
    }

    private func effectiveReaderLayout() -> ReaderLayoutConfiguration {
        var layout = readerSettings.normalized.effectiveLayoutConfiguration
        let safeAreaInsets = view.safeAreaInsets
        let widgetInsets = widgetContentInsets()
        if safeAreaInsets.top > 0 {
            layout.topMargin = max(layout.topMargin, safeAreaInsets.top + 12)
        }
        if safeAreaInsets.bottom > 0 {
            layout.bottomMargin = max(layout.bottomMargin, safeAreaInsets.bottom + 2)
        }
        if safeAreaInsets.left > 0 {
            layout.leftMargin = max(layout.leftMargin, safeAreaInsets.left + 12)
        }
        if safeAreaInsets.right > 0 {
            layout.rightMargin = max(layout.rightMargin, safeAreaInsets.right + 12)
        }
        layout.topMargin = max(layout.topMargin, widgetInsets.top)
        layout.bottomMargin = max(layout.bottomMargin, widgetInsets.bottom)
        return layout
    }

    func displayLayoutForCurrentMode() -> ReaderLayoutConfiguration {
        var layout = effectiveReaderLayout()
        if usesVerticalScrolling {
            layout.topMargin = 0
            layout.bottomMargin = 0
        }
        return layout
    }

    func verticalContinuousInsets() -> UIEdgeInsets {
        let widgetInsets = widgetContentInsets()
        return UIEdgeInsets(
            top: widgetInsets.top,
            left: 0,
            bottom: widgetInsets.bottom,
            right: 0
        )
    }

    private func verticalContinuousPageHeight() -> CGFloat {
        let insets = verticalContinuousInsets()
        return max(1, collectionView.bounds.height - insets.top - insets.bottom)
    }

    private func widgetContentInsets() -> UIEdgeInsets {
        let values = readerSettings.normalized.effectiveLayoutValues
        let visibility = readerSettings.normalized.widgetVisibility
        let hasTopWidget = visibility.chapterTitle
        let hasBottomWidget = visibility.batteryPercentage
            || visibility.batteryIcon
            || visibility.time
            || visibility.chapterPageProgress
            || visibility.globalProgress
        let widgetFont = UIFont.preferredFont(forTextStyle: .caption1)
        let topWidgetHeight = ceil(widgetFont.lineHeight)
        let hasBottomTextWidget = visibility.batteryPercentage
            || visibility.time
            || visibility.chapterPageProgress
            || visibility.globalProgress
        let bottomTextHeight = hasBottomTextWidget ? widgetFont.lineHeight : 0
        let bottomIconHeight: CGFloat = visibility.batteryIcon ? 12 : 0
        let bottomWidgetHeight = ceil(max(bottomTextHeight, bottomIconHeight))
        return UIEdgeInsets(
            top: hasTopWidget ? CGFloat(values.widgetTitleTopMargin) + topWidgetHeight : 0,
            left: 0,
            bottom: hasBottomWidget ? CGFloat(values.widgetBottomMargin) + bottomWidgetHeight : 0,
            right: 0
        )
    }

    func pageWidgetSnapshot(for page: CollectionReaderPage) -> ReaderPageWidgetSnapshot {
        ReaderPageWidgetSnapshot(
            chapterTitle: page.containsChapterTitle ? book.title : page.chapterTitle,
            batteryLevel: UIDevice.current.batteryLevel,
            batteryState: UIDevice.current.batteryState,
            timeText: Self.widgetTimeFormatter.string(from: Date()),
            pageProgressText: "\(page.localPageIndex + 1)/\(max(page.chapterPageCount, 1))",
            globalProgressText: ReadingProgressFormatter.percentString(from: page.globalProgress)
        )
    }

    func widgetLayoutConfiguration() -> ReaderWidgetLayoutConfiguration {
        let values = readerSettings.normalized.effectiveLayoutValues
        return ReaderWidgetLayoutConfiguration(
            horizontalMargin: CGFloat(values.widgetHorizontalMargin),
            bottomMargin: CGFloat(values.widgetBottomMargin),
            titleTopMargin: CGFloat(values.widgetTitleTopMargin),
            titleLeftMargin: CGFloat(values.widgetTitleLeftMargin)
        )
    }

    func updateFixedWidgetOverlay() {
        guard usesVerticalScrolling,
              let currentPage else {
            fixedWidgetOverlay.isHidden = true
            return
        }

        fixedWidgetOverlay.isHidden = false
        fixedWidgetOverlay.configure(
            snapshot: pageWidgetSnapshot(for: currentPage),
            settings: readerSettings.normalized,
            layout: widgetLayoutConfiguration()
        )
    }

    func currentDisplayByteOffset() -> Int {
        updateCurrentPageFromVisiblePage()
        return currentPage?.startAbsoluteOffset ?? 0
    }

    func updateCurrentPageFromVisiblePage() {
        guard let visibleIndex = visiblePageIndex(),
              pages.indices.contains(visibleIndex) else {
            return
        }
        let page = pages[visibleIndex]
        guard currentPage != page else {
            return
        }
        currentPage = page
        updateCurrentProgress()
    }

    private func visiblePageIndex() -> Int? {
        guard !pages.isEmpty else {
            return nil
        }
        if usesVerticalScrolling {
            return visibleVerticalPageIndex()
        }
        let extent = pageExtentForCurrentMode()
        guard extent > 1 else {
            return nil
        }
        let rawIndex = collectionView.contentOffset.x / extent
        let visibleIndex = Int(round(rawIndex))
        return min(max(visibleIndex, 0), pages.count - 1)
    }

    private func visibleVerticalPageIndex() -> Int? {
        let y = collectionView.contentOffset.y
            + collectionView.contentInset.top
            + (isAutoReading ? autoReadPageHeight() * 0.5 : 0)
        var accumulatedHeight: CGFloat = 0

        for index in pages.indices {
            let pageHeight = verticalExtentForPage(at: index)
            if y < accumulatedHeight + pageHeight {
                return index
            }
            accumulatedHeight += pageHeight
        }

        return pages.indices.last
    }

    private func pageExtentForCurrentMode() -> CGFloat {
        if isAutoReading {
            return autoReadPageHeight()
        }
        return usesVerticalScrolling
            ? verticalContinuousPageHeight()
            : collectionView.bounds.width
    }

    func autoReadPageHeight() -> CGFloat {
        verticalContinuousPageHeight()
    }

    private func contentOffset(forPageAt index: Int) -> CGPoint {
        if usesVerticalScrolling {
            return CGPoint(
                x: 0,
                y: verticalOffset(forPageAt: index) - collectionView.contentInset.top
            )
        }
        return CGPoint(x: CGFloat(index) * pageExtentForCurrentMode(), y: 0)
    }

    private func verticalOffset(forPageAt index: Int) -> CGFloat {
        let safeIndex = min(max(index, 0), pages.count)
        return pages.prefix(safeIndex).reduce(CGFloat(0)) { result, page in
            result + verticalExtent(for: page)
        }
    }

    func verticalExtentForPage(at index: Int) -> CGFloat {
        guard pages.indices.contains(index) else {
            return verticalContinuousPageHeight()
        }
        return verticalExtent(for: pages[index])
    }

    private func verticalExtent(for page: CollectionReaderPage) -> CGFloat {
        max(1, page.verticalExtent)
    }

    private func scrollToPage(at index: Int, animated _: Bool) {
        guard pages.indices.contains(index) else {
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(contentOffset(forPageAt: index), animated: false)
        currentPage = pages[index]
        updateSessionState(isLoadingNextPage: pageTask != nil)
        prefetchPagesNearCurrent()
        scheduleProgressSave()
    }

    func topAnchorAbsoluteOffset() -> Int? {
        guard !pages.isEmpty else {
            return nil
        }
        if usesVerticalScrolling {
            let targetY = collectionView.contentOffset.y + collectionView.contentInset.top
            var accumulatedHeight: CGFloat = 0
            for index in pages.indices {
                let pageHeight = verticalExtentForPage(at: index)
                if targetY < accumulatedHeight + pageHeight {
                    let page = pages[index]
                    let localFrac: CGFloat
                    if pageHeight > 0 {
                        localFrac = max(0, min(1, (targetY - accumulatedHeight) / pageHeight))
                    } else {
                        localFrac = 0
                    }
                    let byteSpan = max(0, page.endAbsoluteOffset - page.startAbsoluteOffset)
                    let delta = Int((CGFloat(byteSpan) * localFrac).rounded(.down))
                    return page.startAbsoluteOffset + delta
                }
                accumulatedHeight += pageHeight
            }
            return pages.last?.startAbsoluteOffset
        } else {
            if let visibleIndex = visiblePageIndex(),
               pages.indices.contains(visibleIndex) {
                return pages[visibleIndex].startAbsoluteOffset
            }
            return pages.first?.startAbsoluteOffset
        }
    }

    func alignViewport(toAbsoluteOffset offset: Int) {
        guard !pages.isEmpty else {
            return
        }
        collectionView.layoutIfNeeded()
        let resolvedIndex = pages.firstIndex(where: { offset >= $0.startAbsoluteOffset && offset < $0.endAbsoluteOffset })
            ?? pages.firstIndex(where: { $0.startAbsoluteOffset >= offset })
            ?? (pages.count - 1)
        let page = pages[resolvedIndex]

        if usesVerticalScrolling {
            let pageStartY = verticalOffset(forPageAt: resolvedIndex)
            let pageHeight = verticalExtent(for: page)
            let byteSpan = max(0, page.endAbsoluteOffset - page.startAbsoluteOffset)
            let localFrac: CGFloat
            if byteSpan > 0 {
                localFrac = max(0, min(1, CGFloat(offset - page.startAbsoluteOffset) / CGFloat(byteSpan)))
            } else {
                localFrac = 0
            }
            let rawY = pageStartY + localFrac * pageHeight - collectionView.contentInset.top
            let maxY = max(
                -collectionView.contentInset.top,
                collectionView.contentSize.height + collectionView.contentInset.bottom - collectionView.bounds.height
            )
            let clampedY = max(-collectionView.contentInset.top, min(rawY, maxY))
            collectionView.setContentOffset(CGPoint(x: 0, y: clampedY), animated: false)
        } else {
            collectionView.setContentOffset(contentOffset(forPageAt: resolvedIndex), animated: false)
        }
        currentPage = page
        updateCurrentProgress()
        prefetchPagesNearCurrent()
    }

    func finishPageTurn() {
        flushPendingPageInsertions()
        snapToNearestHorizontalPageIfNeeded()
        updateCurrentPageFromVisiblePage()
        prefetchPagesNearCurrent()
        scheduleProgressSave()
    }

    func snapToNearestHorizontalPageIfNeeded() {
        guard !usesVerticalScrolling,
              !pages.isEmpty,
              let index = visiblePageIndex(),
              pages.indices.contains(index) else {
            return
        }

        let targetOffset = contentOffset(forPageAt: index)
        guard abs(collectionView.contentOffset.x - targetOffset.x) > 0.5
            || abs(collectionView.contentOffset.y - targetOffset.y) > 0.5 else {
            return
        }

        isApplyingProgrammaticScroll = true
        collectionView.setContentOffset(targetOffset, animated: false)
        isApplyingProgrammaticScroll = false
    }

    func moveToNextPage() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }
        let targetIndex = currentIndex + 1
        if pages.indices.contains(targetIndex) {
            turnToPage(at: targetIndex, direction: .next)
            return
        }
        loadNextPageIfNeeded(scrollAfterLoading: true)
    }

    func moveToPreviousPage() {
        updateCurrentPageFromVisiblePage()
        guard let currentPage,
              let currentIndex = pages.firstIndex(of: currentPage) else {
            return
        }
        let targetIndex = currentIndex - 1
        if pages.indices.contains(targetIndex) {
            turnToPage(at: targetIndex, direction: .previous)
            return
        }
        loadPreviousPageIfNeeded(scrollAfterLoading: true)
    }

    private func turnToPage(at index: Int, direction: TapPageDirection) {
        guard readerSettings.pageMode == .curl,
              !isAutoReading else {
            scrollToPage(at: index, animated: false)
            return
        }
        curlToPage(at: index, direction: direction)
    }

    private func curlToPage(at index: Int, direction: TapPageDirection) {
        guard pages.indices.contains(index) else {
            return
        }
        let transition: UIView.AnimationOptions = direction == .next
            ? .transitionCurlUp
            : .transitionCurlDown
        UIView.transition(
            with: collectionView,
            duration: 0.42,
            options: [transition, .curveEaseInOut, .allowUserInteraction],
            animations: {
                self.scrollToPage(at: index, animated: false)
            }
        )
    }

    func alignContentOffsetToCurrentPage() {
        guard let currentPage,
              let index = pages.firstIndex(of: currentPage) else {
            return
        }
        collectionView.layoutIfNeeded()
        collectionView.setContentOffset(contentOffset(forPageAt: index), animated: false)
    }

    func pageIndex(
        containingChapterOffset offset: Int,
        in page: CollectionReaderPage
    ) -> Int {
        let starts = page.chapterPageStartOffsets
        guard starts.isEmpty == false else {
            return min(max(page.localPageIndex, 0), max(page.chapterPageCount - 1, 0))
        }

        var lowerBound = 0
        var upperBound = starts.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if starts[middle] <= offset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return min(max(lowerBound - 1, 0), max(starts.count - 1, 0))
    }

    func chapter(containingAbsoluteOffset offset: Int) -> Chapter? {
        if let chapter = chapters.first(where: { offset >= $0.startOffset && offset < $0.endOffset }) {
            return chapter
        }
        return chapters.last
    }

    func indexOfChapter(containingAbsoluteOffset offset: Int) -> Int? {
        chapters.firstIndex { offset >= $0.startOffset && offset < $0.endOffset }
    }

    @objc func previousChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index - 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index - 1].startOffset, generation: pagingGeneration)
    }

    @objc func nextChapterButtonTapped() {
        stopAutoReading(restoreLayout: true, animated: false)
        guard let index = indexOfChapter(containingAbsoluteOffset: currentDisplayByteOffset()),
              chapters.indices.contains(index + 1) else {
            return
        }
        pagingGeneration += 1
        openPage(absoluteOffset: chapters[index + 1].startOffset, generation: pagingGeneration)
    }
}