import UIKit

struct ReaderScrollSection {
    var chapterIndex: Int
    var title: String
    var timestamp: Date
    var items: [NSAttributedString]
    var heights: [CGFloat]
    var pageModels: [ReaderPageModel]
    var fullProgresses: [Double]
    var sourceRanges: [NSRange] = []
    var sourceLengths: [Int] = []
    var bookTitle: String = ""
}

@MainActor
final class ReaderScrollContainer: UIViewController, ReaderContainerProtocol {
    private let backgroundPageView = ReaderPageBackgroundView(frame: .zero)
    let tableView = UITableView(frame: .zero, style: .plain)
    let headerOverlayView = ReaderPageBackgroundView(frame: .zero)
    let bottomOverlayView = ReaderPageBackgroundView(frame: .zero)
    let chapterTitleLabel = UILabel()
    let bottomWidgetView = ReaderBottomWidgetView()

    private(set) var sections: [ReaderScrollSection] = []
    private(set) var currentPageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var widgetVisibility = ReaderSettings.WidgetVisibility.default
    private var isProgrammaticScroll = false
    private var lastTableInsets = UIEdgeInsets.zero
    private weak var prioritizedReturnGesture: UIGestureRecognizer?

    var makePageController: (@MainActor (ReaderPageModel) -> ReaderPageViewController?)?
    var adjacentPageModel: (@MainActor (ReaderPageModel, Int) -> ReaderPageModel?)?
    var onPageTurnCompleted: (@MainActor (ReaderPageModel) -> Void)?
    var onLoadPreviousChapter: (() -> Void)?
    var onLoadNextChapter: (() -> Void)?
    var onScrollBegan: (() -> Void)?

    var turnPageType: ReaderTurnPageType {
        .verticalContinuous
    }

    var viewController: UIViewController {
        self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureWidgets()
        updateWidgetAppearance()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWidgetFrames()
        updateTableInsets()
    }

    func reload(
        sections: [ReaderScrollSection],
        layout: ReaderLayout,
        theme: ReaderTheme,
        widgetVisibility: ReaderSettings.WidgetVisibility = .default,
        preservesVisualPosition: Bool = false
    ) {
        let oldContentHeight = tableView.contentSize.height
        let oldOffset = tableView.contentOffset

        self.sections = sections
        self.layout = layout
        self.theme = theme
        self.widgetVisibility = widgetVisibility
        view.backgroundColor = theme.backgroundColor
        backgroundPageView.apply(theme: theme)
        headerOverlayView.apply(theme: theme)
        bottomOverlayView.apply(theme: theme)
        tableView.backgroundColor = .clear
        tableView.layer.mask = nil
        updateWidgetAppearance()
        updateTableInsets()
        tableView.reloadData()
        tableView.layoutIfNeeded()

        if preservesVisualPosition {
            let delta = tableView.contentSize.height - oldContentHeight
            let nextOffset = CGPoint(x: oldOffset.x, y: oldOffset.y + delta)
            tableView.setContentOffset(clampedContentOffset(nextOffset), animated: false)
        }
        updateCurrentWidgetContent()
    }

    func appendSections(
        _ newSections: [ReaderScrollSection],
        completion: (() -> Void)? = nil
    ) {
        guard newSections.isEmpty == false else {
            completion?()
            return
        }
        let start = sections.count
        sections.append(contentsOf: newSections)
        updateTableInsets()
        tableView.performBatchUpdates {
            tableView.insertSections(
                IndexSet(integersIn: start..<(start + newSections.count)),
                with: .none
            )
        } completion: { [weak self] _ in
            self?.tableView.layoutIfNeeded()
            self?.updateCurrentWidgetContent()
            completion?()
        }
    }

    func prependSections(
        _ newSections: [ReaderScrollSection],
        completion: (() -> Void)? = nil
    ) {
        guard newSections.isEmpty == false else {
            completion?()
            return
        }
        let oldContentHeight = tableView.contentSize.height
        let oldOffset = tableView.contentOffset
        sections.insert(contentsOf: newSections, at: 0)
        updateTableInsets()
        tableView.performBatchUpdates {
            tableView.insertSections(
                IndexSet(integersIn: 0..<newSections.count),
                with: .none
            )
        } completion: { [weak self] _ in
            guard let self else {
                return
            }
            self.tableView.layoutIfNeeded()
            let delta = self.tableView.contentSize.height - oldContentHeight
            let nextOffset = CGPoint(x: oldOffset.x, y: oldOffset.y + delta)
            self.tableView.setContentOffset(self.clampedContentOffset(nextOffset), animated: false)
            self.updateCurrentWidgetContent()
            completion?()
        }
    }

    func display(
        pageModel: ReaderPageModel,
        pageController _: ReaderPageViewController,
        direction _: ReaderPageTurnDirection,
        animated: Bool
    ) {
        currentPageModel = pageModel
        updateCurrentWidgetContent()
        guard isViewLoaded,
              let indexPath = indexPath(for: pageModel) else {
            return
        }

        isProgrammaticScroll = true
        tableView.layoutIfNeeded()
        let rowRect = tableView.rectForRow(at: indexPath)
        let targetOffset = clampedContentOffset(
            CGPoint(
                x: tableView.contentOffset.x,
                y: rowRect.minY - tableView.adjustedContentInset.top
            )
        )
        tableView.setContentOffset(targetOffset, animated: animated)
        if !animated {
            isProgrammaticScroll = false
        }
    }

    func apply(theme: ReaderTheme) {
        self.theme = theme
        view.backgroundColor = theme.backgroundColor
        backgroundPageView.apply(theme: theme)
        tableView.backgroundColor = .clear
        tableView.visibleCells.forEach { cell in
            cell.backgroundColor = .clear
            (cell as? ReaderScrollPageCell)?.apply(theme: theme)
        }
        headerOverlayView.apply(theme: theme)
        bottomOverlayView.apply(theme: theme)
        updateWidgetAppearance()
    }

    func indexPath(for pageModel: ReaderPageModel) -> IndexPath? {
        for sectionIndex in sections.indices {
            let section = sections[sectionIndex]
            guard section.chapterIndex == pageModel.chapterIndex else {
                continue
            }
            if let row = section.pageModels.firstIndex(where: {
                $0.chapterIndex == pageModel.chapterIndex && $0.pageIndex == pageModel.pageIndex
            }) {
                return IndexPath(row: row, section: sectionIndex)
            }
        }
        return nil
    }

    func visiblePageModel() -> ReaderPageModel? {
        let anchorPoint = CGPoint(
            x: tableView.bounds.midX,
            y: tableView.contentOffset.y
                + tableView.adjustedContentInset.top
                + readableViewportHeight() * 0.48
        )
        let target = tableView.indexPathForRow(at: anchorPoint)
            ?? (tableView.indexPathsForVisibleRows ?? []).sorted {
                if $0.section == $1.section {
                    return $0.row < $1.row
                }
                return $0.section < $1.section
            }.first

        guard let target,
              sections.indices.contains(target.section),
              sections[target.section].pageModels.indices.contains(target.row) else {
            return currentPageModel
        }
        let pageModel = sections[target.section].pageModels[target.row]
        guard pageModel.isNormal else {
            return currentPageModel?.isNormal == true ? currentPageModel : nil
        }
        return pageModel
    }

    func topVisiblePageModel() -> ReaderPageModel? {
        guard isViewLoaded,
              tableView.bounds.width > 0,
              tableView.bounds.height > 0 else {
            return visiblePageModel()
        }

        let topY = tableView.contentOffset.y + tableView.adjustedContentInset.top + 1
        let visibleRows = (tableView.indexPathsForVisibleRows ?? []).sorted {
            if $0.section == $1.section {
                return $0.row < $1.row
            }
            return $0.section < $1.section
        }

        for indexPath in visibleRows {
            let rect = tableView.rectForRow(at: indexPath)
            guard rect.maxY >= topY else {
                continue
            }
            let localY = min(max(topY - rect.minY, 0), max(rect.height - 1, 0))
            if let pageModel = anchoredPageModel(at: indexPath, localY: localY) {
                return pageModel
            }
        }

        if let target = tableView.indexPathForRow(
            at: CGPoint(x: tableView.bounds.midX, y: topY)
        ),
           let pageModel = anchoredPageModel(at: target, localY: 0) {
            return pageModel
        }

        return visiblePageModel()
    }

    func notifyVisiblePageFromAutoRead() {
        notifyVisiblePageIfNeeded(preferredPageModel: topVisiblePageModel())
    }

    func maybeLoadMoreForAutoRead() {
        guard tableView.contentSize.height > 0 else {
            return
        }
        let maxOffsetY = max(
            -tableView.adjustedContentInset.top,
            tableView.contentSize.height
                + tableView.adjustedContentInset.bottom
                - tableView.bounds.height
        )
        let threshold = maxOffsetY - tableView.bounds.height * 2.5
        if tableView.contentOffset.y >= threshold {
            onLoadNextChapter?()
        }
    }

    func selectableTextView(
        at location: CGPoint,
        from coordinateView: UIView
    ) -> TextReadView? {
        let tableLocation = tableView.convert(location, from: coordinateView)
        guard let indexPath = tableView.indexPathForRow(at: tableLocation),
              let cell = tableView.cellForRow(at: indexPath) as? ReaderScrollPageCell else {
            return nil
        }

        let textLocation = cell.textView.convert(location, from: coordinateView)
        guard cell.textView.bounds.contains(textLocation) else {
            return nil
        }
        return cell.textView
    }

    func prioritizeReturnGesture(_ returnGesture: UIGestureRecognizer) {
        guard prioritizedReturnGesture !== returnGesture else {
            return
        }

        prioritizedReturnGesture = returnGesture
        tableView.panGestureRecognizer.require(toFail: returnGesture)
    }

    private func configureTableView() {
        view.backgroundColor = theme.backgroundColor
        backgroundPageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundPageView.apply(theme: theme)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.isOpaque = false
        tableView.showsVerticalScrollIndicator = false
        tableView.scrollsToTop = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            ReaderScrollPageCell.self,
            forCellReuseIdentifier: ReaderScrollPageCell.reuseIdentifier
        )
        view.addSubview(backgroundPageView)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            backgroundPageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundPageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundPageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundPageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureWidgets() {
        headerOverlayView.backgroundColor = .clear
        headerOverlayView.apply(theme: theme)
        headerOverlayView.isUserInteractionEnabled = false
        bottomOverlayView.backgroundColor = .clear
        bottomOverlayView.apply(theme: theme)
        bottomOverlayView.isUserInteractionEnabled = false
        chapterTitleLabel.backgroundColor = .clear
        chapterTitleLabel.textAlignment = .left
        chapterTitleLabel.font = ReaderPageWidgetLayout.font
        chapterTitleLabel.numberOfLines = 1
        chapterTitleLabel.lineBreakMode = .byTruncatingTail
        chapterTitleLabel.isUserInteractionEnabled = false
        bottomWidgetView.isUserInteractionEnabled = false
        view.addSubview(headerOverlayView)
        view.addSubview(bottomOverlayView)
        view.addSubview(chapterTitleLabel)
        view.addSubview(bottomWidgetView)
    }

    private func updateWidgetFrames() {
        let titleFrame = ReaderPageWidgetLayout.titleFrame(
            screenSize: view.bounds.size,
            layout: layout
        )
        let topInset = topReadingInset()
        let bottomInset = bottomReadingInset()
        headerOverlayView.frame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: topInset
        )
        chapterTitleLabel.frame = titleFrame
        bottomWidgetView.frame = ReaderPageWidgetLayout.bottomFrame(
            screenSize: view.bounds.size,
            layout: layout
        )
        bottomOverlayView.frame = CGRect(
            x: 0,
            y: max(0, view.bounds.height - bottomInset),
            width: view.bounds.width,
            height: bottomInset
        )
        bottomWidgetView.updateWidgetLayout(
            screenSize: bottomWidgetView.bounds.size,
            layoutConfig: layout
        )
    }

    private func updateTableInsets() {
        let topInset = topReadingInset()
        let bottomInset = bottomReadingInset()
        let insets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        guard insets != lastTableInsets else {
            return
        }
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
        lastTableInsets = insets
    }

    private func topReadingInset() -> CGFloat {
        if widgetVisibility.chapterTitle {
            return ReaderPageWidgetLayout.titleFrame(
                screenSize: view.bounds.size,
                layout: layout
            ).maxY
        }
        return layout.topMargin
    }

    private func bottomReadingInset() -> CGFloat {
        let hasBottomWidget = widgetVisibility.time
            || widgetVisibility.batteryIcon
            || widgetVisibility.batteryPercentage
            || widgetVisibility.chapterPageProgress
            || widgetVisibility.globalProgress
        if hasBottomWidget {
            let bottomFrame = ReaderPageWidgetLayout.bottomFrame(
                screenSize: view.bounds.size,
                layout: layout
            )
            return max(0, view.bounds.height - bottomFrame.minY)
        }
        return layout.bottomMargin
    }

    private func readableViewportHeight() -> CGFloat {
        max(
            1,
            tableView.bounds.height
                - tableView.adjustedContentInset.top
                - tableView.adjustedContentInset.bottom
        )
    }

    private func updateWidgetAppearance() {
        chapterTitleLabel.textColor = theme.headerColor
        chapterTitleLabel.font = ReaderPageWidgetLayout.font
        chapterTitleLabel.isHidden = !widgetVisibility.chapterTitle
        bottomWidgetView.updateTheme(headerColor: theme.headerColor)
        bottomWidgetView.updateFont(ReaderPageWidgetLayout.font)
        bottomWidgetView.updateSettings(
            showTime: widgetVisibility.time,
            showBatteryView: widgetVisibility.batteryIcon,
            showBatteryLabel: widgetVisibility.batteryPercentage,
            showChapterTitle: widgetVisibility.chapterTitle,
            showPageProgress: widgetVisibility.chapterPageProgress,
            showFullProgress: widgetVisibility.globalProgress
        )
        updateCurrentWidgetContent()
        updateWidgetFrames()
    }

    private func updateCurrentWidgetContent() {
        guard let pageModel = currentPageModel,
              let section = section(forChapterAt: pageModel.chapterIndex) else {
            chapterTitleLabel.text = nil
            bottomWidgetView.updateContent(
                chapterTitle: "",
                pageIndex: 0,
                pageCount: 1,
                fullProgress: 0
            )
            return
        }

        let fullProgress = section.fullProgresses.indices.contains(pageModel.pageIndex)
            ? section.fullProgresses[pageModel.pageIndex]
            : 0
        chapterTitleLabel.text = ReaderPageWidgetLayout.headerTitle(
            bookTitle: section.bookTitle,
            chapterTitle: section.title,
            pageIndex: pageModel.pageIndex,
            prefersBookTitleOnFirstPage: false
        )
        bottomWidgetView.updateContent(
            chapterTitle: section.title,
            pageIndex: pageModel.pageIndex,
            pageCount: pageModel.pageCount,
            fullProgress: fullProgress
        )
    }

    private func section(forChapterAt chapterIndex: Int) -> ReaderScrollSection? {
        sections.first { $0.chapterIndex == chapterIndex }
    }

    private func anchoredPageModel(
        at indexPath: IndexPath,
        localY: CGFloat
    ) -> ReaderPageModel? {
        guard sections.indices.contains(indexPath.section) else {
            return nil
        }
        let section = sections[indexPath.section]
        guard section.pageModels.indices.contains(indexPath.row) else {
            return nil
        }

        let baseModel = section.pageModels[indexPath.row]
        guard baseModel.isNormal else {
            return currentPageModel?.isNormal == true ? currentPageModel : nil
        }

        let sourceRange = section.sourceRanges.indices.contains(indexPath.row)
            ? section.sourceRanges[indexPath.row]
            : NSRange(location: 0, length: 0)
        let sourceLength = section.sourceLengths.indices.contains(indexPath.row)
            ? section.sourceLengths[indexPath.row]
            : 0
        guard sourceLength > 0,
              sourceRange.length > 0 else {
            return baseModel
        }

        let sourceLocation = sourceLocationFromVisibleCell(
            at: indexPath,
            sourceRange: sourceRange,
            localY: localY
        ) ?? fallbackSourceLocation(
            sourceRange: sourceRange,
            rowHeight: max(tableView.rectForRow(at: indexPath).height, 1),
            localY: localY
        )
        let progress = ReaderPageModel.clampedProgress(
            Double(sourceLocation) / Double(sourceLength)
        )
        return ReaderPageModel(
            chapterCount: baseModel.chapterCount,
            chapterIndex: baseModel.chapterIndex,
            pageCount: baseModel.pageCount,
            pageIndex: baseModel.pageIndex,
            chapterProgress: progress,
            usesPageIndex: false,
            pageStatus: baseModel.pageStatus
        )
    }

    private func sourceLocationFromVisibleCell(
        at indexPath: IndexPath,
        sourceRange: NSRange,
        localY: CGFloat
    ) -> Int? {
        guard let cell = tableView.cellForRow(at: indexPath) as? ReaderScrollPageCell else {
            return nil
        }
        cell.layoutIfNeeded()

        let textView = cell.textView
        let localPointInCell = CGPoint(x: cell.bounds.midX, y: localY)
        let startPoint = textView.convert(localPointInCell, from: cell)
        let contentRect = textView.activeContentRect
        let edgeProbe = min(24, max(contentRect.width * 0.2, 0))
        let xCandidates = [
            contentRect.midX,
            contentRect.minX + edgeProbe,
            contentRect.maxX - edgeProbe
        ]
        let startY = min(max(startPoint.y, contentRect.minY), contentRect.maxY)
        let maxScanY = min(contentRect.maxY, startY + max(80, layout.fontSize * 3))
        var y = startY
        while y <= maxScanY {
            for x in xCandidates {
                if let localIndex = textView.characterIndex(at: CGPoint(x: x, y: y)) {
                    return sourceRange.location + min(max(localIndex, 0), sourceRange.length)
                }
            }
            y += max(4, layout.fontSize / 2)
        }
        return nil
    }

    private func fallbackSourceLocation(
        sourceRange: NSRange,
        rowHeight: CGFloat,
        localY: CGFloat
    ) -> Int {
        let fraction = min(max(localY / max(rowHeight, 1), 0), 1)
        let offset = Int((Double(sourceRange.length) * Double(fraction)).rounded(.down))
        return sourceRange.location + min(max(offset, 0), max(sourceRange.length - 1, 0))
    }

    private func notifyVisiblePageIfNeeded(
        preferredPageModel: ReaderPageModel? = nil,
        allowsProgressChange: Bool = false
    ) {
        guard !isProgrammaticScroll,
              let pageModel = preferredPageModel ?? visiblePageModel(),
              pageModel.isNormal,
              shouldNotifyVisiblePage(
                  pageModel,
                  currentPageModel,
                  allowsProgressChange: allowsProgressChange
              ) else {
            return
        }
        currentPageModel = pageModel
        updateCurrentWidgetContent()
        onPageTurnCompleted?(pageModel)
    }

    private func shouldNotifyVisiblePage(
        _ pageModel: ReaderPageModel,
        _ currentPageModel: ReaderPageModel?,
        allowsProgressChange: Bool
    ) -> Bool {
        guard let currentPageModel else {
            return true
        }
        if allowsProgressChange {
            return pageModel != currentPageModel
        }
        return !isSameVisiblePage(pageModel, currentPageModel)
    }

    private func isSameVisiblePage(
        _ lhs: ReaderPageModel,
        _ rhs: ReaderPageModel?
    ) -> Bool {
        guard let rhs else {
            return false
        }
        return lhs.chapterIndex == rhs.chapterIndex
            && lhs.pageIndex == rhs.pageIndex
            && lhs.pageStatus == rhs.pageStatus
    }

    private func clampedContentOffset(_ offset: CGPoint) -> CGPoint {
        let minOffsetY = -tableView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            tableView.contentSize.height
                + tableView.adjustedContentInset.bottom
                - tableView.bounds.height
        )
        return CGPoint(
            x: offset.x,
            y: min(max(offset.y, minOffsetY), maxOffsetY)
        )
    }
}

extension ReaderScrollContainer: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReaderScrollPageCell.reuseIdentifier,
            for: indexPath
        ) as? ReaderScrollPageCell ?? ReaderScrollPageCell(
            style: .default,
            reuseIdentifier: ReaderScrollPageCell.reuseIdentifier
        )
        let section = sections[indexPath.section]
        cell.configure(
            attributedText: section.items[indexPath.row],
            pageModel: section.pageModels[indexPath.row],
            layout: layout,
            theme: theme,
            chapterTitle: section.title,
            bookTitle: section.bookTitle,
            fullProgress: section.fullProgresses.indices.contains(indexPath.row)
                ? section.fullProgresses[indexPath.row]
                : 0,
            widgetVisibility: widgetVisibility
        )
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        let section = sections[indexPath.section]
        guard section.heights.indices.contains(indexPath.row) else {
            return max(tableView.bounds.height, 1)
        }
        return max(section.heights[indexPath.row], 1)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let topThreshold = -scrollView.adjustedContentInset.top - 24
        if (scrollView.isDragging || scrollView.isTracking),
           scrollView.contentOffset.y <= topThreshold {
            onLoadPreviousChapter?()
        }
        maybeLoadMoreForAutoRead()
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        onScrollBegan?()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
        notifyVisiblePageIfNeeded(
            preferredPageModel: topVisiblePageModel(),
            allowsProgressChange: true
        )
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        notifyVisiblePageIfNeeded(
            preferredPageModel: topVisiblePageModel(),
            allowsProgressChange: true
        )
    }

    func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        isProgrammaticScroll = false
        notifyVisiblePageIfNeeded()
    }
}
