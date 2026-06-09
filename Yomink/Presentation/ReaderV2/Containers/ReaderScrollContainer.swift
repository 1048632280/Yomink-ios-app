import UIKit

struct ReaderScrollSection {
    var chapterIndex: Int
    var title: String
    var timestamp: Date
    var items: [NSAttributedString]
    var heights: [CGFloat]
    var pageModels: [ReaderPageModel]
}

@MainActor
final class ReaderScrollContainer: UIViewController, ReaderContainerProtocol {
    let tableView = UITableView(frame: .zero, style: .plain)
    private(set) var sections: [ReaderScrollSection] = []
    private(set) var currentPageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var isProgrammaticScroll = false

    var makePageController: (@MainActor (ReaderPageModel) -> ReaderPageViewController?)?
    var adjacentPageModel: (@MainActor (ReaderPageModel, Int) -> ReaderPageModel?)?
    var onPageTurnCompleted: (@MainActor (ReaderPageModel) -> Void)?

    var turnPageType: ReaderTurnPageType {
        .verticalContinuous
    }

    var viewController: UIViewController {
        self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.backgroundColor = theme.backgroundColor
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            ReaderScrollPageCell.self,
            forCellReuseIdentifier: ReaderScrollPageCell.reuseIdentifier
        )
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func reload(
        sections: [ReaderScrollSection],
        layout: ReaderLayout,
        theme: ReaderTheme
    ) {
        self.sections = sections
        self.layout = layout
        self.theme = theme
        view.backgroundColor = theme.backgroundColor
        tableView.backgroundColor = theme.backgroundColor
        tableView.reloadData()
    }

    func display(
        pageModel: ReaderPageModel,
        pageController _: ReaderPageViewController,
        direction _: ReaderPageTurnDirection,
        animated: Bool
    ) {
        currentPageModel = pageModel
        guard isViewLoaded,
              let indexPath = indexPath(for: pageModel) else {
            return
        }

        isProgrammaticScroll = true
        tableView.scrollToRow(
            at: indexPath,
            at: .top,
            animated: animated
        )
        if !animated {
            isProgrammaticScroll = false
        }
    }

    func apply(theme: ReaderTheme) {
        self.theme = theme
        view.backgroundColor = theme.backgroundColor
        tableView.backgroundColor = theme.backgroundColor
        tableView.visibleCells.forEach { cell in
            cell.backgroundColor = .clear
        }
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
        let visibleIndexPaths = tableView.indexPathsForVisibleRows ?? []
        let target = visibleIndexPaths.sorted {
            if $0.section == $1.section {
                return $0.row < $1.row
            }
            return $0.section < $1.section
        }.first
            ?? tableView.indexPathForRow(at: CGPoint(x: tableView.bounds.midX, y: tableView.contentOffset.y + 1))
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

    private func notifyVisiblePageIfNeeded() {
        guard !isProgrammaticScroll,
              let pageModel = visiblePageModel(),
              pageModel != currentPageModel else {
            return
        }
        currentPageModel = pageModel
        onPageTurnCompleted?(pageModel)
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
            theme: theme
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
    }
}
