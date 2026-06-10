import SwiftUI
import UIKit

@MainActor
final class ReaderContentSearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private enum SearchState {
        case idle
        case scanning
        case canLoadMore
        case finished
    }

    private let book: Book
    private let fileStore: AppFileStore
    private let chapters: [Chapter]
    private let filterRules: [TextFilterRule]
    private let initialKeyword: String?
    private let onSelect: (ReaderContentTarget) -> Void
    private let searchBar = UISearchBar(frame: .zero)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let footerButton = UIButton(type: .system)
    private let footerHeight: CGFloat = 52
    private lazy var emptyResultsLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    private var results: [ReaderSearchResult] = []
    private var resultSections: [SearchResultSection] = []
    private var searchTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var keyword = ""
    private var resultHighlightKeyword = ""
    private var nextScanPosition = SearchPosition.start
    private var state: SearchState = .idle
    private var isClearingSearchTextForCancel = false
    private var scannedChapterCache: SearchChapterCache?
    private var lastSearchError: Error?

    private struct SearchResultSection {
        let chapterID: UUID
        let chapterTitle: String
        var results: [ReaderSearchResult]
    }

    init(
        book: Book,
        fileStore: AppFileStore,
        chapters: [Chapter],
        filterRules: [TextFilterRule],
        initialKeyword: String? = nil,
        onSelect: @escaping (ReaderContentTarget) -> Void
    ) {
        self.book = book
        self.fileStore = fileStore
        self.chapters = chapters
        self.filterRules = filterRules
        self.initialKeyword = initialKeyword?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.search.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        configureCloseButtonIfNeeded()
        configureViews()
        updateFooter()
        applyInitialKeywordIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutFooter()
    }

    deinit {
        searchTask?.cancel()
        searchDebounceTask?.cancel()
    }

    private func configureCloseButtonIfNeeded() {
        guard navigationController?.viewControllers.first === self else {
            return
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.back", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }

    private func configureViews() {
        view.backgroundColor = .systemBackground

        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("reader.search.placeholder", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .systemBackground
        searchBar.barTintColor = .systemBackground
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.backgroundColor = .systemBackground
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        tableView.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.sectionHeaderTopPadding = 0
        tableView.translatesAutoresizingMaskIntoConstraints = false

        footerButton.addTarget(self, action: #selector(loadMoreButtonTapped), for: .touchUpInside)
        footerButton.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 0)
        tableView.tableFooterView = footerButton

        view.addSubview(searchBar)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func applyInitialKeywordIfNeeded() {
        guard let initialKeyword,
              !initialKeyword.isEmpty else {
            return
        }
        keyword = initialKeyword
        searchBar.text = initialKeyword
        resultHighlightKeyword = initialKeyword
        restartSearch()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        resultSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        resultSections[section].results.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ReaderSearchResultCell.reuseIdentifier
        ) as? ReaderSearchResultCell
            ?? ReaderSearchResultCell(
                style: .default,
                reuseIdentifier: ReaderSearchResultCell.reuseIdentifier
            )
        let result = resultSections[indexPath.section].results[indexPath.row]
        cell.configure(snippet: result.snippet, keyword: resultHighlightKeyword)
        cell.accessoryType = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let result = resultSections[indexPath.section].results[indexPath.row]
        onSelect(ReaderContentTarget(chapterID: result.chapterID, offset: result.offset))
    }

    func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        guard resultSections.indices.contains(section) else {
            return nil
        }

        let label = UILabel()
        label.text = resultSections[section].chapterTitle
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = .systemBackground
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: ReaderSearchResultCell.textHorizontalInset,
            bottom: 0,
            trailing: ReaderSearchResultCell.textHorizontalInset
        )
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(
        _ tableView: UITableView,
        heightForHeaderInSection section: Int
    ) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(
        _ tableView: UITableView,
        estimatedHeightForHeaderInSection section: Int
    ) -> CGFloat {
        36
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard state == .canLoadMore,
              scrollView.isDragging
        else {
            return
        }
        guard scrollView.contentSize.height > scrollView.bounds.height else {
            return
        }

        let bottomOffset = scrollView.contentSize.height
            - scrollView.bounds.height
            + scrollView.adjustedContentInset.bottom
        if scrollView.contentOffset.y > bottomOffset + 24 {
            loadNextBatch()
        }
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        updateSearchCancelButton(animated: true)
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSearchCancelButton(animated: true)
        guard !isClearingSearchTextForCancel else {
            return
        }
        scheduleSearchRestart()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        updateSearchCancelButton(animated: true)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchDebounceTask?.cancel()
        searchTask?.cancel()
        keyword = ""
        lastSearchError = nil
        isClearingSearchTextForCancel = true
        searchBar.text = nil
        isClearingSearchTextForCancel = false
        searchBar.resignFirstResponder()
        state = .idle
        updateSearchCancelButton(animated: true)
        updateFooter()
        updateBackgroundView()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        updateSearchCancelButton(animated: true)
    }

    private func restartSearch() {
        searchDebounceTask?.cancel()
        searchTask?.cancel()
        results = []
        resultSections = []
        scannedChapterCache = nil
        lastSearchError = nil
        nextScanPosition = .start
        tableView.reloadData()
        guard !keyword.isEmpty else {
            resultHighlightKeyword = ""
            state = .idle
            updateFooter()
            updateBackgroundView()
            return
        }
        resultHighlightKeyword = keyword
        loadNextBatch()
    }

    private func scheduleSearchRestart() {
        searchDebounceTask?.cancel()
        searchTask?.cancel()
        let keyword = keyword
        searchDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self,
                          self.keyword == keyword
                    else {
                        return
                    }
                    self.restartSearch()
                }
            } catch {
            }
        }
    }

    @objc private func loadMoreButtonTapped() {
        guard state == .canLoadMore else {
            return
        }
        loadNextBatch()
    }

    private func loadNextBatch() {
        guard state != .scanning,
              !keyword.isEmpty,
              nextScanPosition.chapterIndex < chapters.count
        else {
            return
        }

        state = .scanning
        updateFooter()
        updateBackgroundView()
        let startPosition = nextScanPosition
        let keyword = keyword
        let chapters = chapters
        let book = book
        let fileStore = fileStore
        let filterRules = filterRules
        let cachedChapter = scannedChapterCache
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            do {
                let batch = try await Self.scanBatch(
                    book: book,
                    chapters: chapters,
                    startPosition: startPosition,
                    limit: 20,
                    keyword: keyword,
                    filterRules: filterRules,
                    cachedChapter: cachedChapter,
                    fileStore: fileStore
                )
                await MainActor.run {
                    guard let self,
                          self.keyword == keyword
                    else {
                        return
                    }
                    self.nextScanPosition = batch.nextPosition
                    self.scannedChapterCache = batch.cachedChapter
                    self.results.append(contentsOf: batch.results)
                    self.resultSections = Self.groupedSections(from: self.results)
                    self.tableView.reloadData()
                    self.state = batch.nextPosition.chapterIndex >= chapters.count
                        ? .finished
                        : .canLoadMore
                    self.updateFooter()
                    self.updateBackgroundView()
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    guard let self,
                          self.keyword == keyword
                    else {
                        return
                    }
                    self.lastSearchError = error
                    self.state = .finished
                    self.updateFooter()
                    self.updateBackgroundView()
                    self.showError(error)
                }
            }
        }
    }

    private func updateSearchCancelButton(animated: Bool) {
        searchBar.setShowsCancelButton(
            searchBar.isFirstResponder && !(searchBar.text ?? "").isEmpty,
            animated: animated
        )
    }

    private static func groupedSections(from results: [ReaderSearchResult]) -> [SearchResultSection] {
        var sections: [SearchResultSection] = []
        for result in results {
            if sections.last?.chapterID == result.chapterID {
                sections[sections.count - 1].results.append(result)
            } else {
                sections.append(
                    SearchResultSection(
                        chapterID: result.chapterID,
                        chapterTitle: result.chapterTitle,
                        results: [result]
                    )
                )
            }
        }
        return sections
    }

    private func updateFooter() {
        switch state {
        case .idle:
            footerButton.setTitle(nil, for: .normal)
            footerButton.isHidden = true
        case .scanning:
            footerButton.setTitle(NSLocalizedString("reader.search.loadingMore", comment: ""), for: .normal)
            footerButton.isHidden = false
        case .canLoadMore:
            footerButton.setTitle(NSLocalizedString("reader.search.loadMore", comment: ""), for: .normal)
            footerButton.isHidden = false
        case .finished:
            footerButton.setTitle(NSLocalizedString("reader.search.allLoaded", comment: ""), for: .normal)
            footerButton.isHidden = keyword.isEmpty
        }
        layoutFooter()
    }

    private func updateBackgroundView() {
        guard lastSearchError == nil else {
            tableView.backgroundView = nil
            return
        }
        guard state == .finished,
              results.isEmpty,
              !resultHighlightKeyword.isEmpty
        else {
            tableView.backgroundView = nil
            return
        }

        emptyResultsLabel.text = String(
            format: NSLocalizedString("reader.search.empty", comment: ""),
            resultHighlightKeyword
        )
        tableView.backgroundView = emptyResultsLabel
    }

    private func layoutFooter() {
        let targetHeight = state == .idle ? 0 : footerHeight
        let targetFrame = CGRect(
            x: 0,
            y: 0,
            width: tableView.bounds.width,
            height: targetHeight
        )
        guard footerButton.frame != targetFrame else {
            return
        }
        footerButton.frame = targetFrame
        tableView.tableFooterView = footerButton
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private nonisolated static func scanBatch(
        book: Book,
        chapters: [Chapter],
        startPosition: SearchPosition,
        limit: Int,
        keyword: String,
        filterRules: [TextFilterRule],
        cachedChapter: SearchChapterCache?,
        fileStore: AppFileStore
    ) async throws -> (
        results: [ReaderSearchResult],
        nextPosition: SearchPosition,
        cachedChapter: SearchChapterCache?
    ) {
        var results: [ReaderSearchResult] = []
        var position = startPosition
        var cachedChapter = cachedChapter
        while position.chapterIndex < chapters.count,
              results.count < limit,
              !Task.isCancelled {
            try Task.checkCancellation()
            let chapter = chapters[position.chapterIndex]
            let loadedChapter = try await filteredChapter(
                at: position.chapterIndex,
                book: book,
                chapter: chapter,
                filterRules: filterRules,
                fileStore: fileStore,
                cache: cachedChapter
            )
            cachedChapter = loadedChapter.cachedChapter

            if let filtered = loadedChapter.filtered {
                try Task.checkCancellation()
                let matchBatch = matches(
                    keyword: keyword,
                    filtered: filtered,
                    chapter: chapter,
                    startDisplayUTF16Index: position.displayUTF16Index,
                    remainingLimit: limit - results.count
                )
                results.append(contentsOf: matchBatch.results)
                if matchBatch.reachedChapterEnd {
                    position = SearchPosition(
                        chapterIndex: position.chapterIndex + 1,
                        displayUTF16Index: 0
                    )
                } else {
                    position = SearchPosition(
                        chapterIndex: position.chapterIndex,
                        displayUTF16Index: matchBatch.nextDisplayUTF16Index
                    )
                }
            } else {
                position = SearchPosition(
                    chapterIndex: position.chapterIndex + 1,
                    displayUTF16Index: 0
                )
            }
        }
        return (results, position, cachedChapter)
    }

    private nonisolated static func filteredChapter(
        at index: Int,
        book: Book,
        chapter: Chapter,
        filterRules: [TextFilterRule],
        fileStore: AppFileStore,
        cache: SearchChapterCache?
    ) async throws -> (
        filtered: FilteredReaderText?,
        cachedChapter: SearchChapterCache?
    ) {
        if let cache,
           cache.chapterIndex == index {
            return (cache.filtered, cache)
        }

        let text = try await ReaderChapterTextReader.readTextAsync(
            book: book,
            chapter: chapter,
            fileStore: fileStore
        )
        try Task.checkCancellation()

        let filtered = filterRules.isEmpty
            ? ReaderTextFilter.identityFilteredText(for: text)
            : ReaderTextFilter.apply(rules: filterRules, to: text)
        let cache = SearchChapterCache(
            chapterIndex: index,
            filtered: filtered
        )
        return (filtered, cache)
    }

    private nonisolated static func matches(
        keyword: String,
        filtered: FilteredReaderText,
        chapter: Chapter,
        startDisplayUTF16Index: Int,
        remainingLimit: Int
    ) -> SearchMatchBatch {
        guard remainingLimit > 0,
              !keyword.isEmpty
        else {
            return SearchMatchBatch(
                results: [],
                nextDisplayUTF16Index: startDisplayUTF16Index,
                reachedChapterEnd: false
            )
        }

        let text = filtered.displayText
        var searchStart = stringIndex(
            in: text,
            atUTF16Offset: startDisplayUTF16Index
        )
        var results: [ReaderSearchResult] = []
        while searchStart < text.endIndex,
              results.count < remainingLimit {
            guard let range = text.range(
                of: keyword,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
            ) else {
                return SearchMatchBatch(
                    results: results,
                    nextDisplayUTF16Index: text.utf16.count,
                    reachedChapterEnd: true
                )
            }
            let utf16Index = range.lowerBound.utf16Offset(in: text)
            let offset = filtered.originalByteOffset(atDisplayUTF16Index: utf16Index)
            results.append(
                ReaderSearchResult(
                    chapterID: chapter.id,
                    chapterTitle: chapter.title,
                    offset: offset,
                    snippet: snippet(in: text, around: range)
                )
            )
            searchStart = range.upperBound
        }
        return SearchMatchBatch(
            results: results,
            nextDisplayUTF16Index: searchStart.utf16Offset(in: text),
            reachedChapterEnd: searchStart >= text.endIndex
        )
    }

    private nonisolated static func stringIndex(
        in text: String,
        atUTF16Offset offset: Int
    ) -> String.Index {
        let clampedOffset = min(max(offset, 0), text.utf16.count)
        var candidateOffset = clampedOffset
        while candidateOffset <= text.utf16.count {
            let utf16Index = text.utf16.index(
                text.utf16.startIndex,
                offsetBy: candidateOffset
            )
            if let index = String.Index(utf16Index, within: text) {
                return index
            }
            candidateOffset += 1
        }
        return text.endIndex
    }

    private nonisolated static func snippet(
        in text: String,
        around range: Range<String.Index>
    ) -> String {
        let start = text.index(range.lowerBound, offsetBy: -36, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 72, limitedBy: text.endIndex) ?? text.endIndex
        return text[start..<end]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func highlightedSnippet(
        _ snippet: String,
        keyword: String
    ) -> NSAttributedString {
        let headlineSize = UIFont.preferredFont(forTextStyle: .headline).pointSize
        let baseFont = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: headlineSize, weight: .regular)
        )
        let attributed = NSMutableAttributedString(
            string: snippet,
            attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label
            ]
        )
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return attributed
        }

        var searchRange = snippet.startIndex..<snippet.endIndex
        while let matchRange = snippet.range(
            of: keyword,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            let nsRange = NSRange(matchRange, in: snippet)
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor.systemRed,
                range: nsRange
            )
            searchRange = matchRange.upperBound..<snippet.endIndex
        }
        return attributed
    }

}

struct ReaderSearchResult: Sendable {
    let chapterID: UUID
    let chapterTitle: String
    let offset: Int
    let snippet: String
}

private struct SearchChapterCache: Sendable {
    let chapterIndex: Int
    let filtered: FilteredReaderText
}

private final class ReaderSearchResultCell: UITableViewCell {
    static let reuseIdentifier = "readerSearchResult"
    static let textHorizontalInset: CGFloat = 20

    private let snippetLabel = UILabel()

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
        snippetLabel.attributedText = nil
    }

    func configure(
        snippet: String,
        keyword: String
    ) {
        snippetLabel.attributedText = ReaderContentSearchViewController.highlightedSnippet(
            snippet,
            keyword: keyword
        )
    }

    private func configureViews() {
        selectionStyle = .default
        backgroundColor = .systemBackground
        contentView.backgroundColor = .systemBackground
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 8,
            leading: Self.textHorizontalInset,
            bottom: 8,
            trailing: Self.textHorizontalInset
        )

        snippetLabel.numberOfLines = 2
        snippetLabel.adjustsFontForContentSizeCategory = true
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(snippetLabel)

        let guide = contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            snippetLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: guide.topAnchor, constant: 4),
            snippetLabel.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -4)
        ])
    }
}

private struct SearchPosition: Sendable {
    var chapterIndex: Int
    var displayUTF16Index: Int

    static let start = SearchPosition(chapterIndex: 0, displayUTF16Index: 0)
}

private struct SearchMatchBatch: Sendable {
    var results: [ReaderSearchResult]
    var nextDisplayUTF16Index: Int
    var reachedChapterEnd: Bool
}

