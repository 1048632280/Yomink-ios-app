import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

private let readerContentsLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Yomink",
    category: "ReaderContents"
)

final class ReaderContentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private enum Mode: Int, CaseIterable {
        case chapters
        case bookmarks
    }

    private enum CatalogJumpTarget {
        case top
        case bottom

        var titleKey: String {
            switch self {
            case .top:
                return "reader.catalog.jumpTop"
            case .bottom:
                return "reader.catalog.jumpBottom"
            }
        }

        var opposite: CatalogJumpTarget {
            switch self {
            case .top:
                return .bottom
            case .bottom:
                return .top
            }
        }

        var scrollPosition: UITableView.ScrollPosition {
            switch self {
            case .top:
                return .top
            case .bottom:
                return .bottom
            }
        }

        func rowIndex(itemCount: Int) -> Int {
            switch self {
            case .top:
                return 0
            case .bottom:
                return max(itemCount - 1, 0)
            }
        }
    }

    private enum Layout {
        static let searchHeaderHeight: CGFloat = 56
        static let catalogEstimatedRowHeight: CGFloat = 52
        static let bookmarkEstimatedRowHeight: CGFloat = 118
        static let segmentedControlMinimumWidth: CGFloat = 128
        static let catalogDirectionVelocityThreshold: CGFloat = 20
    }

    private struct ChapterListItem {
        let chapter: Chapter
        let originalIndex: Int
    }

    private let bookID: UUID
    private let repository: any LibraryRepository
    private let chapters: [Chapter]
    private let selectedChapterIndex: Int
    private let onBookmarksChanged: ([Bookmark]) -> Void
    private let onSelect: (ReaderContentTarget) -> Void
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchHeaderView = UIView(
        frame: CGRect(
            x: 0,
            y: 0,
            width: 0,
            height: Layout.searchHeaderHeight
        )
    )
    private let searchBar = UISearchBar(frame: .zero)
    private lazy var emptyBookmarksLabel: UILabel = {
        let label = UILabel()
        label.text = NSLocalizedString("reader.bookmarks.empty", comment: "")
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        return label
    }()
    private lazy var segmentedControl = UISegmentedControl(items: [
        NSLocalizedString("reader.catalog.title", comment: ""),
        NSLocalizedString("reader.bookmarks.title", comment: "")
    ])
    private var bookmarks: [Bookmark] = []
    private var currentMode: Mode = .chapters
    private var catalogJumpTarget: CatalogJumpTarget = .bottom
    private var ignoresCatalogScrollDirection = false
    private var searchText = ""
    private var needsSelectedChapterScroll = true

    private var displayedChapterItems: [ChapterListItem] {
        let allItems = chapters.enumerated().map { index, chapter in
            ChapterListItem(chapter: chapter, originalIndex: index)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return allItems
        }
        return allItems.filter { item in
            item.chapter.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var isCatalogSearchActive: Bool {
        searchBar.isFirstResponder || searchText.isEmpty == false
    }

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        chapters: [Chapter],
        selectedChapterIndex: Int,
        onBookmarksChanged: @escaping ([Bookmark]) -> Void,
        onSelect: @escaping (ReaderContentTarget) -> Void
    ) {
        self.bookID = bookID
        self.repository = repository
        self.chapters = chapters
        self.selectedChapterIndex = selectedChapterIndex
        self.onBookmarksChanged = onBookmarksChanged
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.contents.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        configureNavigationBar()
        configureSearchBar()
        configureTableView()
        updateModeChrome()

        reloadBookmarks()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateSearchHeaderFrame()
        guard needsSelectedChapterScroll else {
            return
        }

        needsSelectedChapterScroll = false
        scrollToSelectedChapter(animated: false)
    }

    private func configureNavigationBar() {
        if navigationController?.viewControllers.first === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: NSLocalizedString("common.back", comment: ""),
                style: .plain,
                target: self,
                action: #selector(closeButtonTapped)
            )
        }

        segmentedControl.selectedSegmentIndex = currentMode.rawValue
        segmentedControl.addTarget(
            self,
            action: #selector(segmentChanged),
            for: .valueChanged
        )
        segmentedControl.setTitleTextAttributes(
            [.font: UIFont.preferredFont(forTextStyle: .footnote)],
            for: .normal
        )
        segmentedControl.widthAnchor.constraint(
            greaterThanOrEqualToConstant: Layout.segmentedControlMinimumWidth
        ).isActive = true
        navigationItem.titleView = segmentedControl

        updateCatalogJumpButton()
    }

    private func configureSearchBar() {
        searchHeaderView.backgroundColor = .systemBackground

        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("reader.catalog.search.placeholder", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.barTintColor = .systemBackground
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = .systemBackground
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchHeaderView.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: searchHeaderView.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: searchHeaderView.trailingAnchor, constant: -8),
            searchBar.topAnchor.constraint(equalTo: searchHeaderView.topAnchor, constant: 4),
            searchBar.bottomAnchor.constraint(equalTo: searchHeaderView.bottomAnchor, constant: -4)
        ])
    }

    private func configureTableView() {
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = Layout.catalogEstimatedRowHeight
        tableView.keyboardDismissMode = .onDrag
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    @objc private func segmentChanged() {
        guard let mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else {
            return
        }

        currentMode = mode
        catalogJumpTarget = .bottom
        if mode == .bookmarks {
            clearCatalogSearch(animated: true)
        }
        updateModeChrome()
        tableView.reloadData()
        updateBackgroundView()
        if mode == .chapters {
            scrollToSelectedChapter()
        }
    }

    @objc private func catalogJumpButtonTapped() {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false
        else {
            return
        }

        let target = catalogJumpTarget
        catalogJumpTarget = target.opposite
        ignoresCatalogScrollDirection = true
        scrollToChapterRow(
            target.rowIndex(itemCount: displayedChapterItems.count),
            at: target.scrollPosition,
            animated: true
        )
        updateCatalogJumpButton()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ignoresCatalogScrollDirection = false
        }
    }

    @MainActor
    private func reloadBookmarks() {
        Task {
            do {
                bookmarks = try await repository.fetchBookmarks(bookID: bookID)
            } catch {
                bookmarks = []
            }
            if currentMode == .bookmarks {
                tableView.reloadData()
            }
            updateBackgroundView()
            onBookmarksChanged(bookmarks)
        }
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        let originalBookmarks = bookmarks
        bookmarks.removeAll { $0.id == bookmark.id }
        tableView.reloadData()
        updateBackgroundView()
        onBookmarksChanged(bookmarks)
        let repository = repository
        Task { [weak self] in
            do {
                try await repository.deleteBookmark(id: bookmark.id)
            } catch is CancellationError {
            } catch {
                readerContentsLogger.error("Failed to delete bookmark from contents: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.bookmarks = originalBookmarks
                    self.tableView.reloadData()
                    self.updateBackgroundView()
                    self.onBookmarksChanged(self.bookmarks)
                    self.showError(error)
                }
            }
        }
    }

    private func updateCatalogJumpButton() {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false
        else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString(
                catalogJumpTarget.titleKey,
                comment: ""
            ),
            style: .plain,
            target: self,
            action: #selector(catalogJumpButtonTapped)
        )
    }

    private func updateCatalogJumpTarget(_ target: CatalogJumpTarget) {
        guard catalogJumpTarget != target else {
            return
        }
        catalogJumpTarget = target
        updateCatalogJumpButton()
    }

    private func updateModeChrome() {
        updateSearchHeaderAvailability()
        updateCatalogJumpButton()
        updateBackgroundView()
    }

    private func updateSearchHeaderAvailability() {
        switch currentMode {
        case .chapters:
            if tableView.tableHeaderView !== searchHeaderView {
                tableView.tableHeaderView = searchHeaderView
            }
            updateSearchHeaderFrame()
        case .bookmarks:
            tableView.tableHeaderView = nil
        }
    }

    private func updateSearchHeaderFrame() {
        guard tableView.tableHeaderView === searchHeaderView else {
            return
        }

        var frame = searchHeaderView.frame
        let targetSize = CGSize(
            width: tableView.bounds.width,
            height: Layout.searchHeaderHeight
        )
        guard abs(frame.width - targetSize.width) > 0.5
            || abs(frame.height - targetSize.height) > 0.5
        else {
            return
        }

        frame.size = targetSize
        searchHeaderView.frame = frame
        tableView.tableHeaderView = searchHeaderView
    }

    private func clearCatalogSearch(animated: Bool) {
        searchText = ""
        searchBar.text = nil
        searchBar.resignFirstResponder()
        searchBar.setShowsCancelButton(false, animated: animated)
    }

    private func updateBackgroundView() {
        tableView.backgroundView = currentMode == .bookmarks && bookmarks.isEmpty
            ? emptyBookmarksLabel
            : nil
    }

    private func scrollToSelectedChapter(animated: Bool = false) {
        guard currentMode == .chapters,
              displayedChapterItems.isEmpty == false,
              let row = displayedChapterItems.firstIndex(where: { item in
                  item.originalIndex == selectedChapterIndex
              })
        else {
            hideSearchHeaderIfNeeded(animated: false)
            return
        }

        scrollToChapterRow(row, at: .middle, animated: animated)
    }

    private func scrollToChapterRow(
        _ row: Int,
        at position: UITableView.ScrollPosition,
        animated: Bool
    ) {
        guard displayedChapterItems.indices.contains(row) else {
            return
        }

        tableView.layoutIfNeeded()
        tableView.scrollToRow(
            at: IndexPath(row: row, section: 0),
            at: position,
            animated: animated
        )
        guard isCatalogSearchActive == false else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.hideSearchHeaderIfNeeded(animated: false)
        }
    }

    private func hideSearchHeaderIfNeeded(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView,
              isCatalogSearchActive == false
        else {
            return
        }

        let hiddenOffset = -tableView.adjustedContentInset.top + Layout.searchHeaderHeight
        guard tableView.contentOffset.y < hiddenOffset else {
            return
        }

        tableView.setContentOffset(
            CGPoint(x: 0, y: hiddenOffset),
            animated: animated
        )
    }

    private func collapseSearchHeaderToCatalogTop(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView
        else {
            return
        }

        tableView.layoutIfNeeded()
        let hiddenOffset = -tableView.adjustedContentInset.top + Layout.searchHeaderHeight
        tableView.setContentOffset(
            CGPoint(x: 0, y: hiddenOffset),
            animated: animated
        )
    }

    private func revealSearchHeader(animated: Bool) {
        guard currentMode == .chapters,
              tableView.tableHeaderView === searchHeaderView
        else {
            return
        }

        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top),
            animated: animated
        )
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch currentMode {
        case .chapters:
            return max(displayedChapterItems.count, 1)
        case .bookmarks:
            return bookmarks.count
        }
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch currentMode {
        case .chapters:
            guard chapters.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.catalog.empty", comment: "")
                )
            }
            guard displayedChapterItems.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.catalog.search.empty", comment: "")
                )
            }
            return chapterCell(for: indexPath)
        case .bookmarks:
            guard bookmarks.isEmpty == false else {
                return emptyCell(
                    text: NSLocalizedString("reader.bookmarks.empty", comment: "")
                )
            }
            return bookmarkCell(for: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch currentMode {
        case .chapters:
            let items = displayedChapterItems
            guard items.indices.contains(indexPath.row) else {
                return
            }
            let chapter = items[indexPath.row].chapter
            onSelect(ReaderContentTarget(chapterID: chapter.id, offset: 0))
        case .bookmarks:
            guard bookmarks.indices.contains(indexPath.row) else {
                return
            }
            let bookmark = bookmarks[indexPath.row]
            guard let chapterID = bookmark.chapterID,
                  chapters.contains(where: { $0.id == chapterID })
            else {
                showMissingBookmarkChapterAlert()
                return
            }
            onSelect(ReaderContentTarget(chapterID: chapterID, offset: bookmark.offset))
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard currentMode == .bookmarks,
              bookmarks.indices.contains(indexPath.row)
        else {
            return nil
        }

        let action = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("library.delete", comment: "")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }

            let bookmark = self.bookmarks[indexPath.row]
            self.deleteBookmark(bookmark)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(
        _ tableView: UITableView,
        estimatedHeightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        switch currentMode {
        case .chapters:
            return Layout.catalogEstimatedRowHeight
        case .bookmarks:
            return Layout.bookmarkEstimatedRowHeight
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView,
              currentMode == .chapters,
              displayedChapterItems.isEmpty == false,
              scrollView.isDragging,
              ignoresCatalogScrollDirection == false
        else {
            return
        }

        let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
        if velocityY > Layout.catalogDirectionVelocityThreshold {
            updateCatalogJumpTarget(.top)
        } else if velocityY < -Layout.catalogDirectionVelocityThreshold {
            updateCatalogJumpTarget(.bottom)
        }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else {
            return
        }
        ignoresCatalogScrollDirection = false
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        revealSearchHeader(animated: true)
    }

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        self.searchText = searchText
        catalogJumpTarget = .bottom
        tableView.reloadData()
        updateCatalogJumpButton()
        revealSearchHeader(animated: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        if searchText.isEmpty {
            searchBar.setShowsCancelButton(false, animated: true)
            collapseSearchHeaderToCatalogTop(animated: true)
        }
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        clearCatalogSearch(animated: true)
        catalogJumpTarget = .bottom
        tableView.reloadData()
        updateCatalogJumpButton()
        collapseSearchHeaderToCatalogTop(animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        guard searchText.isEmpty else {
            return
        }

        searchBar.setShowsCancelButton(false, animated: true)
        collapseSearchHeaderToCatalogTop(animated: true)
    }

    private func emptyCell(text: String) -> UITableViewCell {
        let reuseIdentifier = "empty"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
        cell.textLabel?.text = text
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .none
        cell.accessoryType = .none
        return cell
    }

    private func chapterCell(for indexPath: IndexPath) -> UITableViewCell {
        let reuseIdentifier = "chapter"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .default, reuseIdentifier: reuseIdentifier)
        let item = displayedChapterItems[indexPath.row]
        cell.textLabel?.text = "\(item.originalIndex + 1).\(item.chapter.title)"
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.textLabel?.textColor = item.originalIndex == selectedChapterIndex
            ? .systemRed
            : .label
        cell.accessoryType = .none
        cell.selectionStyle = .default
        return cell
    }

    private func bookmarkCell(for indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReaderBookmarkCell.reuseIdentifier
        ) as? ReaderBookmarkCell
            ?? ReaderBookmarkCell(
                style: .default,
                reuseIdentifier: ReaderBookmarkCell.reuseIdentifier
            )
        let bookmark = bookmarks[indexPath.row]
        let chapterTitle = bookmark.chapterID
            .flatMap { chapterID in chapters.first { $0.id == chapterID }?.title }
            ?? NSLocalizedString("reader.bookmark.unknownChapter", comment: "")
        let isAvailable = bookmark.chapterID
            .map { chapterID in chapters.contains { $0.id == chapterID } }
            ?? false
        cell.configure(
            chapterTitle,
            time: Self.dateFormatter.string(from: bookmark.createdAt),
            preview: bookmark.preview,
            isAvailable: isAvailable
        )
        return cell
    }

    private func showMissingBookmarkChapterAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: NSLocalizedString("reader.bookmark.missingChapter", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func showError(_ error: Error) {
        guard presentedViewController == nil else {
            readerContentsLogger.error("Reader contents error while another controller is presented: \(error.localizedDescription, privacy: .public)")
            return
        }
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private final class ReaderBookmarkCell: UITableViewCell {
    static let reuseIdentifier = "readerBookmark"

    private let chapterLabel = UILabel()
    private let timeLabel = UILabel()
    private let previewLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        chapterLabel.text = nil
        timeLabel.text = nil
        previewLabel.text = nil
        chapterLabel.textColor = .label
        previewLabel.textColor = .secondaryLabel
    }

    func configure(
        _ chapterTitle: String,
        time: String,
        preview: String,
        isAvailable: Bool
    ) {
        chapterLabel.text = chapterTitle
        timeLabel.text = time
        previewLabel.text = preview
        chapterLabel.textColor = isAvailable ? .label : .tertiaryLabel
        previewLabel.textColor = isAvailable ? .secondaryLabel : .tertiaryLabel
        isUserInteractionEnabled = true
    }

    private func configureViews() {
        selectionStyle = .default
        accessoryType = .none

        chapterLabel.font = .preferredFont(forTextStyle: .subheadline)
        chapterLabel.adjustsFontForContentSizeCategory = true
        chapterLabel.textColor = .label
        chapterLabel.numberOfLines = 1
        chapterLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = .preferredFont(forTextStyle: .caption1)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = .secondaryLabel
        timeLabel.textAlignment = .right
        timeLabel.numberOfLines = 1
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        previewLabel.font = .preferredFont(forTextStyle: .callout)
        previewLabel.adjustsFontForContentSizeCategory = true
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 3
        previewLabel.lineBreakMode = .byTruncatingTail

        let headerStackView = UIStackView(arrangedSubviews: [
            chapterLabel,
            timeLabel
        ])
        headerStackView.axis = .horizontal
        headerStackView.alignment = .firstBaseline
        headerStackView.spacing = 12

        let contentStackView = UIStackView(arrangedSubviews: [
            headerStackView,
            previewLabel
        ])
        contentStackView.axis = .vertical
        contentStackView.spacing = 6
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        let guide = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            contentStackView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            contentStackView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 6),
            contentStackView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -6)
        ])
    }
}
