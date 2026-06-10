import UIKit

struct ReaderScrollSection {
    var chapterIndex: Int
    var title: String
    var timestamp: Date
    var items: [NSAttributedString]
    var heights: [CGFloat]
    var pageModels: [ReaderPageModel]
    var fullProgresses: [Double]
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

    var makePageController: (@MainActor (ReaderPageModel) -> ReaderPageViewController?)?
    var adjacentPageModel: (@MainActor (ReaderPageModel, Int) -> ReaderPageModel?)?
    var onPageTurnCompleted: (@MainActor (ReaderPageModel) -> Void)?
    var onTextSelectionAction: (@MainActor (ReaderTextSelectionAction, String) -> Void)?
    var onLoadPreviousChapter: (() -> Void)?
    var onLoadNextChapter: (() -> Void)?

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
        return sections[target.section].pageModels[target.row]
    }

    func notifyVisiblePageFromAutoRead() {
        notifyVisiblePageIfNeeded()
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
        let threshold = maxOffsetY - tableView.bounds.height * 0.5
        if tableView.contentOffset.y >= threshold {
            onLoadNextChapter?()
        }
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
        let titleBottom = layout.widgetTitleTop + ReaderPageWidgetLayout.height + 8
        return widgetVisibility.chapterTitle
            ? max(layout.topMargin, titleBottom)
            : layout.topMargin
    }

    private func bottomReadingInset() -> CGFloat {
        max(
            layout.bottomMargin,
            layout.widgetBottom + ReaderPageWidgetLayout.height + 8
        )
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

    private func notifyVisiblePageIfNeeded() {
        guard !isProgrammaticScroll,
              let pageModel = visiblePageModel(),
              pageModel != currentPageModel else {
            return
        }
        currentPageModel = pageModel
        updateCurrentWidgetContent()
        onPageTurnCompleted?(pageModel)
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
        cell.onTextSelectionAction = onTextSelectionAction
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

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            notifyVisiblePageIfNeeded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        notifyVisiblePageIfNeeded()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isProgrammaticScroll = false
        notifyVisiblePageIfNeeded()
    }
}
