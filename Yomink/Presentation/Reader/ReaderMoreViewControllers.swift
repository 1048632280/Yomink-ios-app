import UIKit

@MainActor
final class ReaderBookDetailViewController: UIViewController {
    private var book: Book
    private let repository: any LibraryRepository
    private let fileStore: AppFileStore
    private let chapters: [Chapter]
    private let selectedChapterIndex: Int
    private let onBookUpdated: (Book) -> Void
    private let onShowCatalog: () -> Void
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let introLabel = UILabel()

    init(
        book: Book,
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        chapters: [Chapter],
        selectedChapterIndex: Int,
        onBookUpdated: @escaping (Book) -> Void,
        onShowCatalog: @escaping () -> Void
    ) {
        self.book = book
        self.repository = repository
        self.fileStore = fileStore
        self.chapters = chapters
        self.selectedChapterIndex = selectedChapterIndex
        self.onBookUpdated = onBookUpdated
        self.onShowCatalog = onShowCatalog
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.bookDetail.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.back", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.edit", comment: ""),
            style: .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        configureLayout()
        render()
        loadIntroFallbackIfNeeded()
    }

    private func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func render() {
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stackView.addArrangedSubview(headerCard())
        stackView.addArrangedSubview(introCard())
        stackView.addArrangedSubview(catalogCard())
    }

    private func headerCard() -> UIView {
        let cover = ReaderBookCoverView()
        cover.configure(title: book.title, fontSize: 44)
        cover.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = book.title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        let authorLabel = UILabel()
        authorLabel.text = book.author?.isEmpty == false
            ? book.author
            : NSLocalizedString("reader.bookDetail.unknownAuthor", comment: "")
        authorLabel.font = .preferredFont(forTextStyle: .subheadline)
        authorLabel.textColor = .secondaryLabel

        let wordCountLabel = UILabel()
        wordCountLabel.text = String(
            format: NSLocalizedString("reader.bookDetail.wordCount", comment: ""),
            book.wordCount
        )
        wordCountLabel.font = .preferredFont(forTextStyle: .footnote)
        wordCountLabel.textColor = .secondaryLabel

        let textStack = UIStackView(arrangedSubviews: [
            titleLabel,
            authorLabel,
            UIView(),
            wordCountLabel
        ])
        textStack.axis = .vertical
        textStack.spacing = 6

        let row = UIStackView(arrangedSubviews: [cover, textStack])
        row.axis = .horizontal
        row.alignment = .fill
        row.spacing = 14
        NSLayoutConstraint.activate([
            cover.widthAnchor.constraint(equalToConstant: 86),
            cover.heightAnchor.constraint(equalToConstant: 116)
        ])

        return card(containing: row)
    }

    private func introCard() -> UIView {
        let titleLabel = sectionTitle(NSLocalizedString("reader.bookDetail.intro", comment: ""))
        introLabel.text = displayedIntro
        introLabel.textColor = .secondaryLabel
        introLabel.font = .preferredFont(forTextStyle: .body)
        introLabel.adjustsFontForContentSizeCategory = true
        introLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, introLabel])
        stack.axis = .vertical
        stack.spacing = 8
        return card(containing: stack)
    }

    private func catalogCard() -> UIView {
        let title = String(
            format: NSLocalizedString("reader.bookDetail.catalogCount", comment: ""),
            chapters.count
        )
        let titleLabel = sectionTitle(title)

        let latestLabel = secondaryLabel(
            String(
                format: NSLocalizedString("reader.bookDetail.latestChapter", comment: ""),
                chapters.last?.title ?? NSLocalizedString("reader.catalog.empty", comment: "")
            )
        )
        let currentTitle = chapters.indices.contains(selectedChapterIndex)
            ? chapters[selectedChapterIndex].title
            : NSLocalizedString("reader.catalog.empty", comment: "")
        let currentLabel = secondaryLabel(
            String(
                format: NSLocalizedString("reader.bookDetail.readingChapter", comment: ""),
                currentTitle
            )
        )

        let allCatalogButton = UIButton(type: .system)
        allCatalogButton.setTitle(NSLocalizedString("reader.bookDetail.showAllCatalog", comment: ""), for: .normal)
        allCatalogButton.contentHorizontalAlignment = .leading
        allCatalogButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        allCatalogButton.addTarget(self, action: #selector(showCatalogButtonTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            latestLabel,
            currentLabel,
            allCatalogButton
        ])
        stack.axis = .vertical
        stack.spacing = 8
        return card(containing: stack)
    }

    private func card(containing content: UIView) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        return container
    }

    private func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func secondaryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }

    private var displayedIntro: String {
        let intro = book.intro?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if intro.isEmpty {
            return chapters.isEmpty
                ? NSLocalizedString("reader.bookDetail.emptyIntro", comment: "")
                : NSLocalizedString("reader.bookDetail.loadingIntro", comment: "")
        }
        return intro
    }

    private func loadIntroFallbackIfNeeded() {
        guard (book.intro ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chapter = chapters.first
        else {
            return
        }

        let book = book
        let fileStore = fileStore
        Task { [weak self] in
            let text = (try? await ReaderBookDetailViewController.readChapterText(
                book: book,
                chapter: chapter,
                fileStore: fileStore
            )) ?? ""
            let intro = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            await MainActor.run {
                guard let self else {
                    return
                }
                guard (self.book.intro ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                self.book.intro = intro
                self.introLabel.text = intro.isEmpty
                    ? NSLocalizedString("reader.bookDetail.emptyIntro", comment: "")
                    : intro
            }
        }
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func editButtonTapped() {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.bookDetail.editTitle", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.bookDetail.name", comment: "")
            textField.text = self.book.title
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.bookDetail.author", comment: "")
            textField.text = self.book.author
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.bookDetail.intro", comment: "")
            textField.text = self.book.intro
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.save", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let fields = alert?.textFields
            else {
                return
            }
            self.saveBookDetails(
                title: fields[safe: 0]?.text ?? self.book.title,
                author: fields[safe: 1]?.text,
                intro: fields[safe: 2]?.text
            )
        })
        present(alert, animated: true)
    }

    private func saveBookDetails(title: String, author: String?, intro: String?) {
        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let updated = try await repository.updateBookDetails(
                    id: book.id,
                    title: title,
                    author: author,
                    intro: intro
                )
                await MainActor.run {
                    self.book = updated
                    self.onBookUpdated(updated)
                    self.render()
                    self.loadIntroFallbackIfNeeded()
                }
            } catch {
                await MainActor.run {
                    self.showError(error)
                }
            }
        }
    }

    @objc private func showCatalogButtonTapped() {
        onShowCatalog()
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

    private nonisolated static func readChapterText(
        book: Book,
        chapter: Chapter,
        fileStore: AppFileStore
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let relativePath = book.normalizedPath ?? book.sourcePath
            let url = try fileStore.url(forRelativePath: relativePath)
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: UInt64(chapter.startOffset))
            let data = handle.readData(ofLength: chapter.byteLength)
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}

@MainActor
final class ReaderFilterRulesViewController: UITableViewController {
    private let bookID: UUID
    private let repository: any LibraryRepository
    private var rules: [TextFilterRule]
    private let onRulesChanged: ([TextFilterRule]) -> Void

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        rules: [TextFilterRule],
        onRulesChanged: @escaping ([TextFilterRule]) -> Void
    ) {
        self.bookID = bookID
        self.repository = repository
        self.rules = rules
        self.onRulesChanged = onRulesChanged
        super.init(style: .plain)
        title = NSLocalizedString("reader.filter.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.back", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.add", comment: ""),
            style: .plain,
            target: self,
            action: #selector(addButtonTapped)
        )
        updateEmptyState()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rules.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let reuseIdentifier = "filterRule"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .value1, reuseIdentifier: reuseIdentifier)
        let rule = rules[indexPath.row]
        cell.textLabel?.text = rule.source
        cell.detailTextLabel?.text = rule.replacement ?? ""
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("library.delete", comment: "")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            let rule = self.rules[indexPath.row]
            self.rules.remove(at: indexPath.row)
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
            self.updateEmptyState()
            self.onRulesChanged(self.rules)
            Task {
                try? await self.repository.deleteFilterRule(id: rule.id)
            }
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }

    @objc private func addButtonTapped() {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.filter.addTitle", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.source", comment: "")
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.replacement", comment: "")
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let source = alert?.textFields?.first?.text
            else {
                return
            }
            let replacement = alert?.textFields?[safe: 1]?.text
            self.createRule(source: source, replacement: replacement)
        })
        present(alert, animated: true)
    }

    private func createRule(source: String, replacement: String?) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let rule = try await repository.createFilterRule(
                    bookID: bookID,
                    source: source,
                    replacement: replacement
                )
                await MainActor.run {
                    self.rules.append(rule)
                    self.tableView.insertRows(
                        at: [IndexPath(row: self.rules.count - 1, section: 0)],
                        with: .automatic
                    )
                    self.updateEmptyState()
                    self.onRulesChanged(self.rules)
                }
            } catch {
                await MainActor.run {
                    self.showError(error)
                }
            }
        }
    }

    private func updateEmptyState() {
        if rules.isEmpty {
            let label = UILabel()
            label.text = NSLocalizedString("reader.filter.empty", comment: "")
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
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
}

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
    private let onSelect: (ReaderContentTarget) -> Void
    private let searchBar = UISearchBar(frame: .zero)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let footerButton = UIButton(type: .system)
    private let footerHeight: CGFloat = 52
    private var results: [ReaderSearchResult] = []
    private var searchTask: Task<Void, Never>?
    private var keyword = ""
    private var nextScanPosition = SearchPosition.start
    private var state: SearchState = .idle

    init(
        book: Book,
        fileStore: AppFileStore,
        chapters: [Chapter],
        filterRules: [TextFilterRule],
        onSelect: @escaping (ReaderContentTarget) -> Void
    ) {
        self.book = book
        self.fileStore = fileStore
        self.chapters = chapters
        self.filterRules = filterRules
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.back", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
        configureViews()
        updateFooter()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutFooter()
    }

    deinit {
        searchTask?.cancel()
    }

    private func configureViews() {
        searchBar.delegate = self
        searchBar.placeholder = NSLocalizedString("reader.search.placeholder", comment: "")
        searchBar.searchBarStyle = .minimal
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 86
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let reuseIdentifier = "searchResult"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let result = results[indexPath.row]
        cell.textLabel?.text = result.chapterTitle
        cell.textLabel?.font = .preferredFont(forTextStyle: .headline)
        cell.detailTextLabel?.text = result.snippet
        cell.detailTextLabel?.numberOfLines = 3
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryType = .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let result = results[indexPath.row]
        onSelect(ReaderContentTarget(chapterID: result.chapterID, offset: result.offset))
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard state == .canLoadMore,
              scrollView.isDragging || scrollView.isDecelerating
        else {
            return
        }
        let threshold = max(scrollView.contentSize.height - scrollView.bounds.height - 80, 0)
        if scrollView.contentOffset.y >= threshold {
            loadNextBatch()
        }
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        restartSearch()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    private func restartSearch() {
        searchTask?.cancel()
        results = []
        nextScanPosition = .start
        tableView.reloadData()
        guard !keyword.isEmpty else {
            state = .idle
            updateFooter()
            return
        }
        loadNextBatch()
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
        let startPosition = nextScanPosition
        let keyword = keyword
        let chapters = chapters
        let book = book
        let fileStore = fileStore
        let filterRules = filterRules
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            let batch = await Self.scanBatch(
                book: book,
                chapters: chapters,
                startPosition: startPosition,
                limit: 20,
                keyword: keyword,
                filterRules: filterRules,
                fileStore: fileStore
            )
            await MainActor.run {
                guard let self,
                      self.keyword == keyword
                else {
                    return
                }
                self.nextScanPosition = batch.nextPosition
                self.results.append(contentsOf: batch.results)
                self.tableView.reloadData()
                self.state = batch.nextPosition.chapterIndex >= chapters.count
                    ? .finished
                    : .canLoadMore
                self.updateFooter()
            }
        }
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
        dismiss(animated: true)
    }

    private nonisolated static func scanBatch(
        book: Book,
        chapters: [Chapter],
        startPosition: SearchPosition,
        limit: Int,
        keyword: String,
        filterRules: [TextFilterRule],
        fileStore: AppFileStore
    ) async -> (results: [ReaderSearchResult], nextPosition: SearchPosition) {
        var results: [ReaderSearchResult] = []
        var position = startPosition
        while position.chapterIndex < chapters.count,
              results.count < limit,
              !Task.isCancelled {
            let chapter = chapters[position.chapterIndex]
            if let text = try? await readChapterText(
                book: book,
                chapter: chapter,
                fileStore: fileStore
            ) {
                let filtered = ReaderTextFilter.apply(rules: filterRules, to: text)
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
        return (results, position)
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

    private nonisolated static func readChapterText(
        book: Book,
        chapter: Chapter,
        fileStore: AppFileStore
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let relativePath = book.normalizedPath ?? book.sourcePath
            let url = try fileStore.url(forRelativePath: relativePath)
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: UInt64(chapter.startOffset))
            let data = handle.readData(ofLength: chapter.byteLength)
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}

struct ReaderSearchResult: Sendable {
    let chapterID: UUID
    let chapterTitle: String
    let offset: Int
    let snippet: String
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

final class ReaderBookCoverView: UIView {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 5
        backgroundColor = .systemGray5
        titleLabel.textColor = UIColor.darkGray.withAlphaComponent(0.62)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, fontSize: CGFloat) {
        titleLabel.text = title.firstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
        titleLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var firstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
    }
}
