import SwiftUI
import UIKit

struct ReaderHostView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var book: Book
    let fileStore: AppFileStore
    let repository: any LibraryRepository

    init(
        book: Book,
        fileStore: AppFileStore,
        repository: any LibraryRepository
    ) {
        self.book = book
        self.fileStore = fileStore
        self.repository = repository
    }

    func makeUIViewController(context: Context) -> ReaderViewController {
        ReaderViewController(
            book: book,
            fileStore: fileStore,
            repository: repository,
            onClose: {
                dismiss()
            }
        )
    }

    func updateUIViewController(
        _ uiViewController: ReaderViewController,
        context: Context
    ) {
        uiViewController.update(book: book)
    }
}

@MainActor
final class ReaderViewController: UIViewController, UITextViewDelegate, UIGestureRecognizerDelegate {
    private let fileStore: AppFileStore
    private let repository: any LibraryRepository
    private let onClose: () -> Void

    private let textView = UITextView()
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleLabel = UILabel()
    private let bookmarkButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressSlider = UISlider()
    private let previousChapterButton = UIButton(type: .system)
    private let nextChapterButton = UIButton(type: .system)
    private let catalogButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private enum Layout {
        static let readerHorizontalInset: CGFloat = 24
        static let readerVerticalInset: CGFloat = 28
        static let topBarContentHeight: CGFloat = 52
        static let topBarButtonBottomInset: CGFloat = 8
        static let bottomBarTopInset: CGFloat = 12
        static let bottomBarSafeAreaInset: CGFloat = 10
        static let bottomBarHorizontalInset: CGFloat = 18
        static let bottomBarRowSpacing: CGFloat = 8
        static let progressRowHeight: CGFloat = 32
        static let bottomActionRowHeight: CGFloat = 34
        static let chapterButtonWidth: CGFloat = 44
    }

    private var book: Book
    private var chapters: [Chapter] = []
    private var bookmarks: [Bookmark] = []
    private var filterRules: [TextFilterRule] = []
    private var currentChapterIndex = 0
    private var originalChapterText = ""
    private var currentChapterText = ""
    private var currentFilteredText = FilteredReaderText(
        displayText: "",
        originalByteOffsetsByUTF16Index: [0]
    )
    private var currentPaginator: ChapterPaginator?
    private var currentPageIndex = 0
    private var currentProgress: ReadingProgress?
    private var pendingAnchorByteOffset: Int?
    private var loadTask: Task<Void, Never>?
    private var paginateTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var settingsRenderTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var bookmarkTask: Task<Void, Never>?
    private var saveGeneration = 0
    private var settingsSaveGeneration = 0
    private var settingsRenderGeneration = 0
    private var settingsRenderNeedsTrailingRender = false
    private var paginateGeneration = 0
    private var prefetchGeneration = 0
    private var readerSettings = ReaderSettings.default
    private var prefetchedChapter: PrefetchedChapter?
    private var prefetchingChapterID: UUID?
    private var currentBookmark: Bookmark?
    private var isMenuVisible = false
    private var isTrackingProgressSlider = false
    private var isApplyingProgrammaticScroll = false
    private var lastPaginationSize = CGSize.zero

    init(
        book: Book,
        fileStore: AppFileStore,
        repository: any LibraryRepository,
        onClose: @escaping () -> Void
    ) {
        self.book = book
        self.fileStore = fileStore
        self.repository = repository
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        paginateTask?.cancel()
        saveTask?.cancel()
        settingsSaveTask?.cancel()
        settingsRenderTask?.cancel()
        prefetchTask?.cancel()
        bookmarkTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureTextView()
        configureMenus()
        configureLoadingIndicator()
        configureGestures()
        applyTheme()
        startInitialLoad()
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let size = textView.bounds.size
        guard currentChapterText.isEmpty == false,
              size.width > 0,
              size.height > 0,
              (
                abs(size.width - lastPaginationSize.width) > 1
                    || abs(size.height - lastPaginationSize.height) > 1
              )
        else {
            return
        }

        lastPaginationSize = size
        let anchorByteOffset = currentDisplayByteOffset()
        invalidatePrefetch()
        if readerSettings.pageMode == .scroll {
            renderScrollContent(
                anchorByteOffset: anchorByteOffset,
                savingProgress: false
            )
        } else {
            rebuildPaginator(
                anchorByteOffset: anchorByteOffset,
                savingProgress: false
            )
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgressImmediately()
        saveSettingsImmediately()
    }

    func update(book: Book) {
        guard book.id != self.book.id else {
            return
        }

        self.book = book
        startInitialLoad()
    }

    private func configureTextView() {
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = true
        textView.delegate = self
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.readerHorizontalInset
            ),
            textView.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.readerHorizontalInset
            ),
            textView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Layout.readerVerticalInset
            ),
            textView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.readerVerticalInset
            )
        ])
    }

    private func configureMenus() {
        configureTopBar()
        configureBottomBar()
        setMenuVisible(false, animated: false)
    }

    private func configureTopBar() {
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("reader.close", comment: "")
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.text = book.title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bookmarkButton.setImage(UIImage(systemName: "bookmark"), for: .normal)
        bookmarkButton.accessibilityLabel = NSLocalizedString("reader.bookmark.add", comment: "")
        bookmarkButton.addTarget(self, action: #selector(bookmarkButtonTapped), for: .touchUpInside)
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false

        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.accessibilityLabel = NSLocalizedString("reader.more", comment: "")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.menu = makeMoreMenu()
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = UIStackView(arrangedSubviews: [
            bookmarkButton,
            moreButton
        ])
        actionStack.axis = .horizontal
        actionStack.alignment = .center
        actionStack.spacing = 4
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        topBar.contentView.addSubview(closeButton)
        topBar.contentView.addSubview(titleLabel)
        topBar.contentView.addSubview(actionStack)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Layout.topBarContentHeight
            ),

            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.bottomAnchor.constraint(
                equalTo: topBar.contentView.bottomAnchor,
                constant: -Layout.topBarButtonBottomInset
            ),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),

            actionStack.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            actionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            bookmarkButton.widthAnchor.constraint(equalToConstant: 44),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 36),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func makeMoreMenu() -> UIMenu {
        UIMenu(
            children: [
                UIAction(
                    title: NSLocalizedString("reader.more.bookDetail", comment: ""),
                    image: UIImage(systemName: "book")
                ) { [weak self] _ in
                    self?.showBookDetail()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.contentSearch", comment: ""),
                    image: UIImage(systemName: "magnifyingglass")
                ) { [weak self] _ in
                    self?.showContentSearch()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.contentFilter", comment: ""),
                    image: UIImage(systemName: "line.3.horizontal.decrease.circle")
                ) { [weak self] _ in
                    self?.showFilterRules()
                },
                UIAction(
                    title: NSLocalizedString("reader.more.pageTouchAreas", comment: ""),
                    image: UIImage(systemName: "square.grid.3x3")
                ) { [weak self] _ in
                    self?.showPageTouchAreas()
                }
            ]
        )
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        previousChapterButton.setImage(UIImage(systemName: "backward.end"), for: .normal)
        previousChapterButton.accessibilityLabel = NSLocalizedString("reader.previousChapter", comment: "")
        previousChapterButton.addTarget(self, action: #selector(previousChapterButtonTapped), for: .touchUpInside)
        previousChapterButton.translatesAutoresizingMaskIntoConstraints = false

        nextChapterButton.setImage(UIImage(systemName: "forward.end"), for: .normal)
        nextChapterButton.accessibilityLabel = NSLocalizedString("reader.nextChapter", comment: "")
        nextChapterButton.addTarget(self, action: #selector(nextChapterButtonTapped), for: .touchUpInside)
        nextChapterButton.translatesAutoresizingMaskIntoConstraints = false

        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.value = 0
        progressSlider.accessibilityLabel = NSLocalizedString("reader.progress.slider", comment: "")
        progressSlider.addTarget(self, action: #selector(progressSliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(progressSliderChanged), for: .valueChanged)
        progressSlider.addTarget(
            self,
            action: #selector(progressSliderTouchFinished),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        progressSlider.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = .preferredFont(forTextStyle: .footnote)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textAlignment = .center
        progressLabel.textColor = .secondaryLabel
        progressLabel.numberOfLines = 2
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        catalogButton.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        catalogButton.setTitle(NSLocalizedString("reader.catalog", comment: ""), for: .normal)
        catalogButton.accessibilityLabel = NSLocalizedString("reader.catalog", comment: "")
        catalogButton.addTarget(self, action: #selector(catalogButtonTapped), for: .touchUpInside)
        catalogButton.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.setImage(UIImage(systemName: "textformat.size"), for: .normal)
        settingsButton.setTitle(NSLocalizedString("reader.settings", comment: ""), for: .normal)
        settingsButton.accessibilityLabel = NSLocalizedString("reader.settings", comment: "")
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let progressRow = UIStackView(arrangedSubviews: [
            previousChapterButton,
            progressSlider,
            nextChapterButton
        ])
        progressRow.axis = .horizontal
        progressRow.alignment = .center
        progressRow.spacing = 12
        progressRow.translatesAutoresizingMaskIntoConstraints = false

        let actionRow = UIStackView(arrangedSubviews: [
            catalogButton,
            settingsButton
        ])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.distribution = .fillEqually
        actionRow.spacing = 12
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.contentView.addSubview(progressRow)
        bottomBar.contentView.addSubview(progressLabel)
        bottomBar.contentView.addSubview(actionRow)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            progressRow.topAnchor.constraint(
                equalTo: bottomBar.topAnchor,
                constant: Layout.bottomBarTopInset
            ),
            progressRow.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.bottomBarHorizontalInset
            ),
            progressRow.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.bottomBarHorizontalInset
            ),
            progressRow.heightAnchor.constraint(equalToConstant: Layout.progressRowHeight),

            previousChapterButton.widthAnchor.constraint(equalToConstant: Layout.chapterButtonWidth),
            nextChapterButton.widthAnchor.constraint(equalToConstant: Layout.chapterButtonWidth),

            progressLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.bottomBarHorizontalInset
            ),
            progressLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.bottomBarHorizontalInset
            ),
            progressLabel.topAnchor.constraint(
                equalTo: progressRow.bottomAnchor,
                constant: Layout.bottomBarRowSpacing
            ),

            actionRow.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.bottomBarHorizontalInset
            ),
            actionRow.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.bottomBarHorizontalInset
            ),
            actionRow.topAnchor.constraint(
                equalTo: progressLabel.bottomAnchor,
                constant: Layout.bottomBarRowSpacing
            ),
            actionRow.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.bottomBarSafeAreaInset
            ),
            actionRow.heightAnchor.constraint(equalToConstant: Layout.bottomActionRowHeight)
        ])
    }

    private func configureLoadingIndicator() {
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true

        view.addSubview(loadingIndicator)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 16)
        ])
    }

    private func configureGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)

        let edgeBackGesture = UIScreenEdgePanGestureRecognizer(
            target: self,
            action: #selector(handleEdgeBack(_:))
        )
        edgeBackGesture.edges = .left
        edgeBackGesture.delegate = self
        view.addGestureRecognizer(edgeBackGesture)
        panGesture.require(toFail: edgeBackGesture)
    }

    private func startInitialLoad() {
        loadTask?.cancel()
        paginateTask?.cancel()
        saveTask?.cancel()
        cancelSettingsRender()
        prefetchTask?.cancel()
        paginateGeneration += 1
        prefetchGeneration += 1
        chapters = []
        bookmarks = []
        filterRules = []
        originalChapterText = ""
        currentChapterText = ""
        currentFilteredText = FilteredReaderText(
            displayText: "",
            originalByteOffsetsByUTF16Index: [0]
        )
        currentPaginator = nil
        prefetchedChapter = nil
        prefetchingChapterID = nil
        currentBookmark = nil
        currentChapterIndex = 0
        currentPageIndex = 0
        currentProgress = nil
        pendingAnchorByteOffset = nil
        titleLabel.text = book.title
        updateBookmarkButton()
        textView.text = nil
        showLoading(true, message: NSLocalizedString("reader.loading", comment: ""))

        let book = book
        let fileStore = fileStore
        let repository = repository

        loadTask = Task { [weak self] in
            do {
                async let fetchedChapters = repository.fetchChapters(bookID: book.id)
                async let fetchedBookmarks = repository.fetchBookmarks(bookID: book.id)
                async let fetchedFilterRules = repository.fetchFilterRules(bookID: book.id)
                async let fetchedProgress = repository.fetchReadingProgress(bookID: book.id)
                async let fetchedSettings = repository.fetchReaderSettings()
                async let markOpened: Void = repository.markBookOpened(id: book.id, at: Date())

                let chapters = try await fetchedChapters
                let bookmarks = try await fetchedBookmarks
                let filterRules = try await fetchedFilterRules
                let progress = try await fetchedProgress
                let settings = try await fetchedSettings
                try? await markOpened
                try Task.checkCancellation()

                guard let selected = Self.selectedChapter(
                    from: chapters,
                    progress: progress
                ) else {
                    await self?.showEmptyReader()
                    return
                }

                let text = try await Self.readChapterText(
                    book: book,
                    chapter: selected.chapter,
                    fileStore: fileStore
                )
                try Task.checkCancellation()

                await self?.applyLoadedContent(
                    chapters: chapters,
                    bookmarks: bookmarks,
                    filterRules: filterRules,
                    chapterIndex: selected.index,
                    text: text,
                    startOffset: selected.offset,
                    settings: settings,
                    saveAfterRender: false
                )
            } catch is CancellationError {
            } catch {
                await self?.showError(error)
            }
        }
    }

    private func loadChapter(
        at index: Int,
        startOffset: Int,
        saveAfterRender: Bool
    ) {
        guard chapters.indices.contains(index) else {
            return
        }

        if let prefetchedChapter = takePrefetchedChapter(at: index) {
            applyPrefetchedChapter(
                prefetchedChapter,
                startOffset: startOffset,
                saveAfterRender: saveAfterRender
            )
            return
        }

        loadTask?.cancel()
        paginateTask?.cancel()
        cancelSettingsRender()
        prefetchTask?.cancel()
        paginateGeneration += 1
        prefetchGeneration += 1
        prefetchingChapterID = nil
        showLoading(true, message: NSLocalizedString("reader.loading", comment: ""))

        let book = book
        let chapter = chapters[index]
        let fileStore = fileStore
        let chapters = chapters

        loadTask = Task { [weak self] in
            do {
                let text = try await Self.readChapterText(
                    book: book,
                    chapter: chapter,
                    fileStore: fileStore
                )
                try Task.checkCancellation()

                await self?.applyLoadedContent(
                    chapters: chapters,
                    chapterIndex: index,
                    text: text,
                    startOffset: startOffset,
                    saveAfterRender: saveAfterRender
                )
            } catch is CancellationError {
            } catch {
                await self?.showError(error)
            }
        }
    }

    private func applyLoadedContent(
        chapters: [Chapter],
        bookmarks: [Bookmark]? = nil,
        filterRules: [TextFilterRule]? = nil,
        chapterIndex: Int,
        text: String,
        startOffset: Int,
        settings: ReaderSettings? = nil,
        saveAfterRender: Bool
    ) {
        self.chapters = chapters
        if let bookmarks {
            self.bookmarks = bookmarks
        }
        if let filterRules {
            self.filterRules = filterRules
        }
        if let settings = settings {
            readerSettings = settings.normalized
        }
        currentChapterIndex = chapterIndex
        originalChapterText = text
        applyCurrentFilters()
        currentPaginator = nil
        currentPageIndex = 0
        pendingAnchorByteOffset = startOffset
        setProvisionalProgress(chapterOffset: startOffset)
        refreshBookmarkState()
        if prefetchedChapter?.chapter.id != chapters[chapterIndex].id {
            prefetchedChapter = nil
            prefetchingChapterID = nil
        }
        lastPaginationSize = textView.bounds.size
        renderContent(anchorByteOffset: startOffset, savingProgress: saveAfterRender)
    }

    private func applyCurrentFilters() {
        currentFilteredText = ReaderTextFilter.apply(
            rules: filterRules,
            to: originalChapterText
        )
        currentChapterText = currentFilteredText.displayText
    }

    private func refreshCurrentChapterAfterFilterChange() {
        guard originalChapterText.isEmpty == false else {
            return
        }

        let anchorOffset = currentDisplayByteOffset()
        applyCurrentFilters()
        currentPaginator = nil
        currentPageIndex = 0
        invalidatePrefetch()
        renderContent(anchorByteOffset: anchorOffset, savingProgress: false)
    }

    private func renderContent(anchorByteOffset: Int, savingProgress: Bool) {
        applyTheme()
        textView.transform = .identity
        textView.alpha = 1

        switch readerSettings.pageMode {
        case .paged:
            textView.isScrollEnabled = false
            rebuildPaginator(
                anchorByteOffset: anchorByteOffset,
                savingProgress: savingProgress
            )
        case .scroll:
            paginateTask?.cancel()
            paginateGeneration += 1
            currentPaginator = nil
            renderScrollContent(
                anchorByteOffset: anchorByteOffset,
                savingProgress: savingProgress
            )
        }
    }

    private func takePrefetchedChapter(at index: Int) -> PrefetchedChapter? {
        guard let prefetchedChapter = prefetchedChapter,
              prefetchedChapter.index == index,
              prefetchContextMatches(prefetchedChapter)
        else {
            return nil
        }

        self.prefetchedChapter = nil
        prefetchingChapterID = nil
        return prefetchedChapter
    }

    private func applyPrefetchedChapter(
        _ prefetchedChapter: PrefetchedChapter,
        startOffset: Int,
        saveAfterRender: Bool
    ) {
        loadTask?.cancel()
        paginateTask?.cancel()
        prefetchTask?.cancel()
        paginateGeneration += 1
        prefetchGeneration += 1
        prefetchingChapterID = nil
        self.prefetchedChapter = nil

        currentChapterIndex = prefetchedChapter.index
        originalChapterText = prefetchedChapter.text
        applyCurrentFilters()
        currentPaginator = nil
        currentPageIndex = 0
        pendingAnchorByteOffset = startOffset
        setProvisionalProgress(chapterOffset: startOffset)
        refreshBookmarkState()
        lastPaginationSize = textView.bounds.size
        applyTheme()
        textView.transform = .identity
        textView.alpha = 1

        if readerSettings.pageMode == .paged,
           let paginator = prefetchedChapter.paginator {
            textView.isScrollEnabled = false
            currentPaginator = paginator
            currentPageIndex = paginator.pageIndex(
                containingDisplayUTF16Index: currentFilteredText
                    .displayUTF16Index(containingOriginalByteOffset: startOffset)
            )
            showLoading(false, message: nil)
            renderCurrentPage(savingProgress: saveAfterRender)
        } else {
            renderContent(anchorByteOffset: startOffset, savingProgress: saveAfterRender)
        }
    }

    private func prefetchAdjacentChapterIfNeeded() {
        guard currentChapterText.isEmpty == false,
              chapters.indices.contains(currentChapterIndex)
        else {
            return
        }

        let targetIndex: Int?
        switch readerSettings.pageMode {
        case .paged:
            guard let paginator = currentPaginator,
                  paginator.pageCount > 0
            else {
                return
            }

            if currentPageIndex + 2 >= paginator.pageCount {
                targetIndex = currentChapterIndex + 1
            } else if currentPageIndex <= 1 {
                targetIndex = currentChapterIndex - 1
            } else {
                targetIndex = nil
            }
        case .scroll:
            let maxOffset = max(textView.contentSize.height - textView.bounds.height, 0)
            if textView.contentOffset.y >= maxOffset - textView.bounds.height * 1.2 {
                targetIndex = currentChapterIndex + 1
            } else if textView.contentOffset.y <= textView.bounds.height * 0.4 {
                targetIndex = currentChapterIndex - 1
            } else {
                targetIndex = nil
            }
        }

        guard let targetIndex = targetIndex,
              chapters.indices.contains(targetIndex)
        else {
            return
        }

        startPrefetchingChapter(at: targetIndex)
    }

    private func startPrefetchingChapter(at index: Int) {
        let chapter = chapters[index]
        if let prefetchedChapter = prefetchedChapter,
           prefetchedChapter.chapter.id == chapter.id,
           prefetchContextMatches(prefetchedChapter) {
            return
        }
        guard prefetchingChapterID != chapter.id else {
            return
        }

        prefetchTask?.cancel()
        prefetchGeneration += 1
        let generation = prefetchGeneration
        let book = book
        let fileStore = fileStore
        let settings = readerSettings.normalized
        let filterRules = filterRules
        let fittingSize = textView.bounds.size
        let typography = ReaderTypography(settings: settings)
        prefetchingChapterID = chapter.id

        prefetchTask = Task { [weak self] in
            do {
                let text = try await Self.readChapterText(
                    book: book,
                    chapter: chapter,
                    fileStore: fileStore
                )
                try Task.checkCancellation()

                let paginator: ChapterPaginator?
                if settings.pageMode == .paged {
                    paginator = try await Task.detached(priority: .utility) {
                        try Task.checkCancellation()
                        let filteredText = ReaderTextFilter
                            .apply(rules: filterRules, to: text)
                            .displayText
                        let paginator = ChapterPaginator(
                            text: filteredText,
                            typography: typography,
                            fittingSize: fittingSize
                        )
                        try Task.checkCancellation()
                        return paginator
                    }.value
                } else {
                    paginator = nil
                }
                try Task.checkCancellation()

                await self?.storePrefetchedChapter(
                    PrefetchedChapter(
                        index: index,
                        chapter: chapter,
                        text: text,
                        paginator: paginator,
                        settings: settings,
                        filterRules: filterRules,
                        fittingSize: fittingSize
                    ),
                    generation: generation
                )
            } catch {
                await self?.clearPrefetchingChapter(
                    id: chapter.id,
                    generation: generation
                )
            }
        }
    }

    private func storePrefetchedChapter(
        _ prefetchedChapter: PrefetchedChapter,
        generation: Int
    ) {
        guard generation == prefetchGeneration,
              chapters.indices.contains(prefetchedChapter.index),
              chapters[prefetchedChapter.index].id == prefetchedChapter.chapter.id,
              prefetchContextMatches(prefetchedChapter)
        else {
            clearPrefetchingChapter(
                id: prefetchedChapter.chapter.id,
                generation: generation
            )
            return
        }

        self.prefetchedChapter = prefetchedChapter
        prefetchingChapterID = nil
        prefetchTask = nil
    }

    private func clearPrefetchingChapter(id: UUID, generation: Int) {
        guard generation == prefetchGeneration,
              prefetchingChapterID == id
        else {
            return
        }

        prefetchingChapterID = nil
        prefetchTask = nil
    }

    private func prefetchContextMatches(_ prefetchedChapter: PrefetchedChapter) -> Bool {
        prefetchedChapter.settings == readerSettings.normalized
            && prefetchedChapter.filterRules == filterRules
            && abs(prefetchedChapter.fittingSize.width - textView.bounds.width) < 1
            && abs(prefetchedChapter.fittingSize.height - textView.bounds.height) < 1
    }

    private func showEmptyReader() {
        showLoading(false, message: nil)
        textView.text = NSLocalizedString("reader.emptyChapter", comment: "")
        progressLabel.text = nil
    }

    private func showError(_ error: Error) {
        showLoading(false, message: nil)
        textView.text = nil
        statusLabel.text = error.localizedDescription
        statusLabel.isHidden = false
    }

    private func showLoading(_ isLoading: Bool, message: String?) {
        statusLabel.text = message
        statusLabel.isHidden = message == nil
        textView.isHidden = isLoading

        if isLoading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
    }

    private func rebuildPaginator(anchorByteOffset: Int, savingProgress: Bool) {
        paginateGeneration += 1
        let generation = paginateGeneration
        let text = currentChapterText
        let fittingSize = textView.bounds.size
        let typography = ReaderTypography(settings: readerSettings)

        paginateTask?.cancel()
        paginateTask = Task { [weak self] in
            let buildTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let paginator = ChapterPaginator(
                    text: text,
                    typography: typography,
                    fittingSize: fittingSize
                )
                try Task.checkCancellation()
                return paginator
            }

            do {
                let paginator = try await buildTask.value

                await self?.applyPaginator(
                    paginator,
                    anchorByteOffset: anchorByteOffset,
                    generation: generation,
                    savingProgress: savingProgress
                )
            } catch {
                buildTask.cancel()
            }
        }
    }

    private func applyPaginator(
        _ paginator: ChapterPaginator,
        anchorByteOffset: Int,
        generation: Int,
        savingProgress: Bool
    ) {
        guard generation == paginateGeneration else {
            return
        }

        currentPaginator = paginator
        currentPageIndex = paginator.pageIndex(
            containingDisplayUTF16Index: currentFilteredText
                .displayUTF16Index(containingOriginalByteOffset: anchorByteOffset)
        )
        paginateTask = nil
        showLoading(false, message: nil)
        renderCurrentPage(savingProgress: savingProgress)
    }

    private func renderScrollContent(anchorByteOffset: Int, savingProgress shouldSave: Bool) {
        guard currentChapterText.isEmpty == false else {
            textView.text = NSLocalizedString("reader.emptyChapter", comment: "")
            currentProgress = nil
            return
        }

        showLoading(false, message: nil)
        textView.isScrollEnabled = true
        // Phase 7 performance: scroll mode still lets UITextView lay out the
        // current chapter on the main thread; revisit if Instruments shows
        // setting changes blocking frames on large chunks.
        textView.attributedText = ReaderTypography(settings: readerSettings)
            .attributedString(for: currentChapterText)
        view.layoutIfNeeded()

        let displayIndex = currentFilteredText
            .displayUTF16Index(containingOriginalByteOffset: anchorByteOffset)
        let displayLength = max(currentChapterText.utf16.count, 1)
        let ratio = min(max(Double(displayIndex) / Double(displayLength), 0), 1)
        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 0)
        isApplyingProgrammaticScroll = true
        textView.setContentOffset(
            CGPoint(x: 0, y: CGFloat(ratio) * maxOffset),
            animated: false
        )
        isApplyingProgrammaticScroll = false
        updateProgress(
            chapterOffset: currentFilteredText.originalByteOffset(
                atDisplayUTF16Index: displayIndex
            )
        )
        prefetchAdjacentChapterIfNeeded()

        if shouldSave {
            scheduleProgressSave()
        }
    }

    private func renderCurrentPage(savingProgress shouldSave: Bool) {
        guard currentChapterText.isEmpty == false else {
            textView.text = NSLocalizedString("reader.emptyChapter", comment: "")
            currentPaginator = nil
            return
        }

        guard let paginator = currentPaginator else {
            return
        }
        currentPageIndex = min(max(currentPageIndex, 0), max(paginator.pageCount - 1, 0))

        let page = paginator.page(at: currentPageIndex)
        textView.attributedText = page.attributedText
        updateProgress(
            chapterOffset: currentFilteredText.originalByteOffset(
                atDisplayUTF16Index: page.startDisplayUTF16Index
            )
        )
        prefetchAdjacentChapterIfNeeded()

        if shouldSave {
            scheduleProgressSave()
        }
    }

    private func moveToNextPage() {
        guard currentChapterText.isEmpty == false else {
            return
        }

        if readerSettings.pageMode == .scroll,
           scrollByPage(forward: true) {
            return
        }

        guard let paginator = currentPaginator else {
            return
        }

        if currentPageIndex + 1 < paginator.pageCount {
            currentPageIndex += 1
            renderCurrentPage(savingProgress: true)
            return
        }

        let nextChapterIndex = currentChapterIndex + 1
        guard chapters.indices.contains(nextChapterIndex) else {
            return
        }

        loadChapter(at: nextChapterIndex, startOffset: 0, saveAfterRender: true)
    }

    private func moveToPreviousPage() {
        if readerSettings.pageMode == .scroll,
           scrollByPage(forward: false) {
            return
        }

        guard currentPaginator != nil else {
            return
        }

        if currentPageIndex > 0 {
            currentPageIndex -= 1
            renderCurrentPage(savingProgress: true)
            return
        }

        let previousChapterIndex = currentChapterIndex - 1
        guard chapters.indices.contains(previousChapterIndex) else {
            return
        }

        let previousChapter = chapters[previousChapterIndex]
        loadChapter(
            at: previousChapterIndex,
            startOffset: max(0, previousChapter.byteLength - 1),
            saveAfterRender: true
        )
    }

    private func scrollByPage(forward: Bool) -> Bool {
        guard readerSettings.pageMode == .scroll else {
            return false
        }

        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 0)
        let step = max(textView.bounds.height * 0.86, 1)
        let currentY = textView.contentOffset.y
        let targetY = min(max(currentY + (forward ? step : -step), 0), maxOffset)

        if abs(targetY - currentY) > 1 {
            isApplyingProgrammaticScroll = true
            textView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
            isApplyingProgrammaticScroll = false
            updateScrollProgressFromContentOffset()
            scheduleProgressSave()
            return true
        }

        if forward {
            let nextChapterIndex = currentChapterIndex + 1
            guard chapters.indices.contains(nextChapterIndex) else {
                return true
            }
            loadChapter(at: nextChapterIndex, startOffset: 0, saveAfterRender: true)
        } else {
            let previousChapterIndex = currentChapterIndex - 1
            guard chapters.indices.contains(previousChapterIndex) else {
                return true
            }
            let previousChapter = chapters[previousChapterIndex]
            loadChapter(
                at: previousChapterIndex,
                startOffset: max(0, previousChapter.byteLength - 1),
                saveAfterRender: true
            )
        }

        return true
    }

    private func updateProgress(chapterOffset: Int) {
        guard chapters.indices.contains(currentChapterIndex) else {
            return
        }

        pendingAnchorByteOffset = nil
        setProvisionalProgress(chapterOffset: chapterOffset)
        let chapter = chapters[currentChapterIndex]
        let pageStartByteOffset = min(max(chapterOffset, 0), max(chapter.byteLength - 1, 0))
        let chapterProgress = chapter.byteLength > 0
            ? min(max(Double(pageStartByteOffset) / Double(chapter.byteLength), 0), 1)
            : 0
        let globalProgress = currentProgress?.globalProgress ?? 0

        progressLabel.text = progressText(
            chapter: chapter,
            chapterProgress: chapterProgress,
            globalProgress: globalProgress
        )
        if !isTrackingProgressSlider {
            progressSlider.value = Float(globalProgress)
        }
    }

    private func setProvisionalProgress(chapterOffset: Int) {
        guard chapters.indices.contains(currentChapterIndex) else {
            currentProgress = nil
            return
        }

        let chapter = chapters[currentChapterIndex]
        let pageStartByteOffset = min(max(chapterOffset, 0), max(chapter.byteLength - 1, 0))
        let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let absoluteOffset = chapter.startOffset + pageStartByteOffset
        let globalProgress = min(max(Double(absoluteOffset) / Double(totalByteLength), 0), 1)

        currentProgress = ReadingProgress(
            bookID: book.id,
            chapterID: chapter.id,
            chapterOffset: Int64(pageStartByteOffset),
            globalProgress: globalProgress
        )

        if !isTrackingProgressSlider {
            progressSlider.value = Float(globalProgress)
        }

        refreshBookmarkState()
    }

    private func progressText(
        chapter: Chapter,
        chapterProgress: Double,
        globalProgress: Double
    ) -> String {
        String(
            format: NSLocalizedString("reader.progress.format", comment: ""),
            chapter.title,
            NumberFormatter.readerPercent.string(
                from: NSNumber(value: chapterProgress)
            ) ?? "0%",
            NumberFormatter.readerPercent.string(
                from: NSNumber(value: globalProgress)
            ) ?? "0%"
        )
    }

    private func updateScrollProgressFromContentOffset() {
        guard readerSettings.pageMode == .scroll,
              chapters.indices.contains(currentChapterIndex)
        else {
            return
        }

        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 1)
        let yOffset = min(max(textView.contentOffset.y, 0), maxOffset)
        let ratio = min(max(Double(yOffset / maxOffset), 0), 1)
        let displayIndex = Int(Double(max(currentChapterText.utf16.count, 1)) * ratio)
        let chapterOffset = currentFilteredText.originalByteOffset(
            atDisplayUTF16Index: displayIndex
        )
        updateProgress(chapterOffset: chapterOffset)
        // Phase 7 performance: prefetch checks are cheap but run during active
        // scrolling; throttle or move them to scroll-end callbacks if needed.
        prefetchAdjacentChapterIfNeeded()
    }

    private func scheduleProgressSave() {
        guard let progress = currentProgress else {
            return
        }

        saveGeneration += 1
        let generation = saveGeneration
        saveTask?.cancel()

        let repository = repository
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                try Task.checkCancellation()
                guard generation == saveGeneration else {
                    return
                }
                try await repository.saveReadingProgress(progress)
            } catch {
            }
        }
    }

    private func saveProgressImmediately() {
        guard let progress = currentProgress else {
            return
        }

        saveTask?.cancel()
        let repository = repository
        Task {
            try? await repository.saveReadingProgress(progress)
        }
    }

    private func applyReaderSettings(_ settings: ReaderSettings) {
        let oldSettings = readerSettings
        let normalizedSettings = settings.normalized
        guard normalizedSettings != oldSettings else {
            return
        }

        let anchorByteOffset = currentDisplayByteOffset()
        let requiresImmediateRerender = oldSettings.pageMode != normalizedSettings.pageMode
            || oldSettings.theme != normalizedSettings.theme
        let requiresDeferredRerender = oldSettings.fontSize != normalizedSettings.fontSize
        readerSettings = normalizedSettings
        invalidatePrefetch()
        applyTheme()
        if requiresImmediateRerender {
            cancelSettingsRender()
            renderContent(anchorByteOffset: anchorByteOffset, savingProgress: false)
        } else if requiresDeferredRerender {
            scheduleSettingsRender(anchorByteOffset: anchorByteOffset)
        }
        scheduleSettingsSave()
    }

    private func invalidatePrefetch() {
        prefetchTask?.cancel()
        prefetchGeneration += 1
        prefetchedChapter = nil
        prefetchingChapterID = nil
    }

    private func scheduleSettingsRender(anchorByteOffset: Int) {
        let shouldRenderImmediately = settingsRenderTask == nil
        settingsRenderGeneration += 1
        let generation = settingsRenderGeneration
        settingsRenderTask?.cancel()

        if shouldRenderImmediately {
            settingsRenderNeedsTrailingRender = false
            renderContent(anchorByteOffset: anchorByteOffset, savingProgress: false)
        } else {
            settingsRenderNeedsTrailingRender = true
        }

        settingsRenderTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                try Task.checkCancellation()
                await self?.finishSettingsRender(generation: generation)
            } catch {
            }
        }
    }

    private func finishSettingsRender(generation: Int) {
        guard generation == settingsRenderGeneration else {
            return
        }

        settingsRenderTask = nil
        guard settingsRenderNeedsTrailingRender else {
            return
        }

        settingsRenderNeedsTrailingRender = false
        renderContent(
            anchorByteOffset: currentDisplayByteOffset(),
            savingProgress: false
        )
    }

    private func cancelSettingsRender() {
        settingsRenderGeneration += 1
        settingsRenderTask?.cancel()
        settingsRenderTask = nil
        settingsRenderNeedsTrailingRender = false
    }

    private func scheduleSettingsSave() {
        settingsSaveGeneration += 1
        let generation = settingsSaveGeneration
        let settings = readerSettings
        let repository = repository
        settingsSaveTask?.cancel()
        settingsSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
                try Task.checkCancellation()
                guard generation == settingsSaveGeneration else {
                    return
                }
                try await repository.saveReaderSettings(settings)
            } catch {
            }
        }
    }

    private func saveSettingsImmediately() {
        settingsSaveTask?.cancel()
        let settings = readerSettings
        let repository = repository
        Task {
            try? await repository.saveReaderSettings(settings)
        }
    }

    private func refreshBookmarkState() {
        guard let progress = currentProgress else {
            currentBookmark = nil
            updateBookmarkButton()
            return
        }

        currentBookmark = matchingBookmark(
            chapterID: progress.chapterID,
            offset: Int(progress.chapterOffset)
        )
        updateBookmarkButton()
    }

    private func matchingBookmark(
        chapterID: UUID?,
        offset: Int
    ) -> Bookmark? {
        bookmarks
            .filter { bookmark in
                bookmark.chapterID == chapterID
                    && abs(bookmark.offset - offset) <= Self.bookmarkMatchTolerance
            }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.offset - offset)
                let rhsDistance = abs(rhs.offset - offset)
                if lhsDistance == rhsDistance {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhsDistance < rhsDistance
            }
    }

    private func updateBookmarkButton() {
        let isBookmarked = currentBookmark != nil
        bookmarkButton.setImage(
            UIImage(systemName: isBookmarked ? "bookmark.fill" : "bookmark"),
            for: .normal
        )
        bookmarkButton.accessibilityLabel = NSLocalizedString(
            isBookmarked ? "reader.bookmark.remove" : "reader.bookmark.add",
            comment: ""
        )
    }

    private func applyTheme() {
        overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        view.backgroundColor = readerSettings.theme.backgroundColor
        textView.backgroundColor = .clear
        textView.indicatorStyle = readerSettings.theme == .dark ? .white : .black
        statusLabel.textColor = readerSettings.theme.secondaryTextColor
        progressLabel.textColor = readerSettings.theme.secondaryTextColor
        loadingIndicator.color = readerSettings.theme.secondaryTextColor
    }

    private func setMenuVisible(_ visible: Bool, animated: Bool) {
        isMenuVisible = visible
        topBar.isUserInteractionEnabled = visible
        bottomBar.isUserInteractionEnabled = visible
        let changes = {
            self.topBar.alpha = visible ? 1 : 0
            self.bottomBar.alpha = visible ? 1 : 0
        }

        if animated {
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes
            )
        } else {
            changes()
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        if isMenuVisible {
            guard topBar.frame.contains(location) == false,
                  bottomBar.frame.contains(location) == false
            else {
                return
            }
        }

        switch touchAreaAction(at: location) {
        case .previousPage:
            moveToPreviousPage()
        case .nextPage:
            moveToNextPage()
        case .menu:
            setMenuVisible(!isMenuVisible, animated: true)
        case .none:
            break
        }
    }

    private func touchAreaAction(at location: CGPoint) -> ReaderSettings.TouchAreaAction {
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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let width = max(view.bounds.width, 1)

        switch gesture.state {
        case .changed:
            let limitedTranslation = min(max(translation.x, -width), width)
            textView.transform = CGAffineTransform(translationX: limitedTranslation * 0.32, y: 0)
        case .ended:
            let velocity = gesture.velocity(in: view).x
            let shouldMoveNext = translation.x < -width * 0.22 || velocity < -520
            let shouldMovePrevious = translation.x > width * 0.22 || velocity > 520

            // Phase 3 polish: replace this outgoing-page animation with a dual
            // text/layer transition so the incoming page moves in continuously.
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut]
            ) {
                if shouldMoveNext {
                    self.textView.transform = CGAffineTransform(translationX: -width * 0.28, y: 0)
                    self.textView.alpha = 0.25
                } else if shouldMovePrevious {
                    self.textView.transform = CGAffineTransform(translationX: width * 0.28, y: 0)
                    self.textView.alpha = 0.25
                } else {
                    self.textView.transform = .identity
                    self.textView.alpha = 1
                }
            } completion: { [weak self] _ in
                guard let self else {
                    return
                }
                self.textView.transform = .identity
                self.textView.alpha = 1
                if shouldMoveNext {
                    self.moveToNextPage()
                } else if shouldMovePrevious {
                    self.moveToPreviousPage()
                }
            }
        case .cancelled, .failed:
            UIView.animate(withDuration: 0.16) {
                self.textView.transform = .identity
                self.textView.alpha = 1
            }
        default:
            break
        }
    }

    @objc private func handleEdgeBack(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else {
            return
        }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        guard translation.x > view.bounds.width * 0.18 || velocity.x > 520 else {
            return
        }

        closeButtonTapped()
    }

    @objc private func previousChapterButtonTapped() {
        let previousChapterIndex = currentChapterIndex - 1
        guard chapters.indices.contains(previousChapterIndex) else {
            return
        }
        loadChapter(at: previousChapterIndex, startOffset: 0, saveAfterRender: true)
    }

    @objc private func nextChapterButtonTapped() {
        let nextChapterIndex = currentChapterIndex + 1
        guard chapters.indices.contains(nextChapterIndex) else {
            return
        }
        loadChapter(at: nextChapterIndex, startOffset: 0, saveAfterRender: true)
    }

    @objc private func progressSliderTouchDown() {
        isTrackingProgressSlider = true
    }

    @objc private func progressSliderChanged() {
        guard let target = targetChapter(forGlobalProgress: Double(progressSlider.value)) else {
            return
        }
        progressLabel.text = progressText(
            chapter: target.chapter,
            chapterProgress: target.chapterProgress,
            globalProgress: Double(progressSlider.value)
        )
    }

    @objc private func progressSliderTouchFinished() {
        isTrackingProgressSlider = false
        guard let target = targetChapter(forGlobalProgress: Double(progressSlider.value)) else {
            return
        }

        if target.index == currentChapterIndex {
            renderContent(anchorByteOffset: target.chapterOffset, savingProgress: true)
        } else {
            loadChapter(
                at: target.index,
                startOffset: target.chapterOffset,
                saveAfterRender: true
            )
        }
    }

    @objc private func catalogButtonTapped() {
        saveProgressImmediately()
        presentContents()
    }

    private func presentContents() {
        let listViewController = ReaderContentsViewController(
            bookID: book.id,
            repository: repository,
            chapters: chapters,
            selectedChapterIndex: currentChapterIndex,
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.refreshBookmarkState()
            }
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpTo(target)
            self.dismiss(animated: true)
        }
        let navigationController = UINavigationController(rootViewController: listViewController)
        navigationController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    @objc private func showBookDetail() {
        saveProgressImmediately()
        let detailViewController = ReaderBookDetailViewController(
            book: book,
            repository: repository,
            fileStore: fileStore,
            chapters: chapters,
            selectedChapterIndex: currentChapterIndex,
            onBookUpdated: { [weak self] updatedBook in
                guard let self else {
                    return
                }
                self.book = updatedBook
                self.titleLabel.text = updatedBook.title
            },
            onBookmarksChanged: { [weak self] bookmarks in
                self?.bookmarks = bookmarks
                self?.refreshBookmarkState()
            },
            onSelectCatalogTarget: { [weak self] target in
                guard let self else {
                    return
                }
                self.jumpTo(target)
                self.presentedViewController?.dismiss(animated: true)
            }
        )
        presentFullScreenNavigation(detailViewController)
    }

    @objc private func showContentSearch() {
        let searchViewController = ReaderContentSearchViewController(
            book: book,
            fileStore: fileStore,
            chapters: chapters,
            filterRules: filterRules
        ) { [weak self] target in
            guard let self else {
                return
            }
            self.jumpTo(target)
            self.presentedViewController?.dismiss(animated: true)
        }
        presentFullScreenNavigation(searchViewController)
    }

    @objc private func showFilterRules() {
        let filterViewController = ReaderFilterRulesViewController(
            bookID: book.id,
            repository: repository,
            rules: filterRules
        ) { [weak self] rules in
            guard let self else {
                return
            }
            self.filterRules = rules
            self.refreshCurrentChapterAfterFilterChange()
        }
        presentFullScreenNavigation(filterViewController)
    }

    @objc private func showPageTouchAreas() {
        let viewController = ReaderPageTouchAreasViewController(settings: readerSettings) { [weak self] settings in
            self?.applyReaderSettings(settings)
        }
        viewController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        viewController.modalPresentationStyle = .fullScreen
        present(viewController, animated: true)
    }

    private func presentFullScreenNavigation(_ rootViewController: UIViewController) {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    @objc private func bookmarkButtonTapped() {
        guard let progress = currentProgress,
              chapters.indices.contains(currentChapterIndex)
        else {
            return
        }

        if let currentBookmark {
            bookmarkTask?.cancel()
            self.currentBookmark = nil
            bookmarks.removeAll { $0.id == currentBookmark.id }
            updateBookmarkButton()
            let repository = repository
            bookmarkTask = Task {
                try? await repository.deleteBookmark(id: currentBookmark.id)
            }
            return
        }

        let chapter = chapters[currentChapterIndex]
        let offset = Int(progress.chapterOffset)
        let preview = bookmarkPreview(near: offset)
        let repository = repository
        let bookID = book.id
        bookmarkButton.isEnabled = false
        bookmarkTask?.cancel()
        bookmarkTask = Task { [weak self] in
            let bookmark = try? await repository.createBookmark(
                bookID: bookID,
                chapterID: chapter.id,
                offset: offset,
                preview: preview
            )
            await MainActor.run {
                guard let self else {
                    return
                }
                self.bookmarkButton.isEnabled = true
                self.currentBookmark = bookmark
                if let bookmark {
                    self.bookmarks.removeAll { $0.id == bookmark.id }
                    self.bookmarks.insert(bookmark, at: 0)
                }
                self.updateBookmarkButton()
            }
        }
    }

    private func jumpTo(_ target: ReaderContentTarget) {
        guard let index = chapters.firstIndex(where: { $0.id == target.chapterID }) else {
            return
        }

        let chapter = chapters[index]
        let offset = min(max(target.offset, 0), max(chapter.byteLength - 1, 0))
        guard index != currentChapterIndex || currentChapterText.isEmpty else {
            jumpWithinCurrentChapter(to: offset, saveAfterRender: true)
            return
        }

        loadChapter(
            at: index,
            startOffset: offset,
            saveAfterRender: true
        )
    }

    private func jumpWithinCurrentChapter(
        to offset: Int,
        saveAfterRender: Bool
    ) {
        loadTask?.cancel()
        paginateTask?.cancel()
        cancelSettingsRender()
        pendingAnchorByteOffset = offset
        setProvisionalProgress(chapterOffset: offset)

        switch readerSettings.pageMode {
        case .paged:
            textView.isScrollEnabled = false
            guard let paginator = currentPaginator else {
                rebuildPaginator(anchorByteOffset: offset, savingProgress: saveAfterRender)
                return
            }

            currentPageIndex = paginator.pageIndex(
                containingDisplayUTF16Index: currentFilteredText
                    .displayUTF16Index(containingOriginalByteOffset: offset)
            )
            showLoading(false, message: nil)
            renderCurrentPage(savingProgress: saveAfterRender)
        case .scroll:
            scrollLoadedCurrentChapter(to: offset, saveAfterRender: saveAfterRender)
        }
    }

    private func scrollLoadedCurrentChapter(
        to offset: Int,
        saveAfterRender: Bool
    ) {
        guard currentChapterText.isEmpty == false,
              chapters.indices.contains(currentChapterIndex)
        else {
            renderScrollContent(anchorByteOffset: offset, savingProgress: saveAfterRender)
            return
        }

        showLoading(false, message: nil)
        textView.isScrollEnabled = true
        view.layoutIfNeeded()

        let displayIndex = currentFilteredText
            .displayUTF16Index(containingOriginalByteOffset: offset)
        let ratio = min(
            max(Double(displayIndex) / Double(max(currentChapterText.utf16.count, 1)), 0),
            1
        )
        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 0)
        isApplyingProgrammaticScroll = true
        textView.setContentOffset(
            CGPoint(x: 0, y: CGFloat(ratio) * maxOffset),
            animated: false
        )
        isApplyingProgrammaticScroll = false
        updateProgress(chapterOffset: offset)
        prefetchAdjacentChapterIfNeeded()

        if saveAfterRender {
            scheduleProgressSave()
        }
    }

    private func bookmarkPreview(near offset: Int) -> String {
        guard !currentChapterText.isEmpty else {
            return NSLocalizedString("reader.bookmark.preview.empty", comment: "")
        }

        let displayOffset = currentFilteredText
            .displayUTF16Index(containingOriginalByteOffset: offset)
        let startIndex = stringIndex(
            in: currentChapterText,
            atUTF16Offset: displayOffset
        )
        var preview = ""
        var index = startIndex
        while index < currentChapterText.endIndex,
              preview.count < Self.bookmarkPreviewCharacterLimit {
            preview.append(currentChapterText[index])
            index = currentChapterText.index(after: index)
        }

        let normalizedPreview = preview
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedPreview.isEmpty
            ? NSLocalizedString("reader.bookmark.preview.empty", comment: "")
            : normalizedPreview
    }

    private func stringIndex(
        in text: String,
        atUTF16Offset offset: Int
    ) -> String.Index {
        var candidateOffset = min(max(offset, 0), text.utf16.count)
        while candidateOffset >= 0 {
            let utf16Index = text.utf16.index(
                text.utf16.startIndex,
                offsetBy: candidateOffset
            )
            if let index = String.Index(utf16Index, within: text) {
                return index
            }
            candidateOffset -= 1
        }
        return text.startIndex
    }

    @objc private func settingsButtonTapped() {
        let settingsViewController = ReaderSettingsViewController(
            settings: readerSettings
        ) { [weak self] settings in
            self?.applyReaderSettings(settings)
        }
        let navigationController = UINavigationController(rootViewController: settingsViewController)
        navigationController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
    }

    private func currentDisplayByteOffset() -> Int {
        if let pendingAnchorByteOffset = pendingAnchorByteOffset {
            return pendingAnchorByteOffset
        }
        if let progress = currentProgress {
            return Int(progress.chapterOffset)
        }
        return currentPaginator.map {
            currentFilteredText.originalByteOffset(
                atDisplayUTF16Index: $0.pageStartDisplayUTF16Index(at: currentPageIndex)
            )
        } ?? 0
    }

    private func targetChapter(
        forGlobalProgress globalProgress: Double
    ) -> (index: Int, chapter: Chapter, chapterOffset: Int, chapterProgress: Double)? {
        guard chapters.isEmpty == false else {
            return nil
        }

        let totalByteLength = max(chapters.last?.endOffset ?? 1, 1)
        let absoluteOffset = min(
            max(Int(Double(totalByteLength) * min(max(globalProgress, 0), 1)), 0),
            max(totalByteLength - 1, 0)
        )
        let index = chapters.firstIndex { chapter in
            absoluteOffset >= chapter.startOffset && absoluteOffset < chapter.endOffset
        } ?? max(chapters.count - 1, 0)
        let chapter = chapters[index]
        let chapterOffset = min(
            max(absoluteOffset - chapter.startOffset, 0),
            max(chapter.byteLength - 1, 0)
        )
        let chapterProgress = chapter.byteLength > 0
            ? min(max(Double(chapterOffset) / Double(chapter.byteLength), 0), 1)
            : 0

        return (index, chapter, chapterOffset, chapterProgress)
    }

    @objc private func closeButtonTapped() {
        saveProgressImmediately()
        saveSettingsImmediately()
        onClose()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === textView,
              !isApplyingProgrammaticScroll
        else {
            return
        }
        updateScrollProgressFromContentOffset()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === textView,
              readerSettings.pageMode == .scroll,
              !decelerate
        else {
            return
        }
        scheduleProgressSave()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === textView,
              readerSettings.pageMode == .scroll
        else {
            return
        }
        scheduleProgressSave()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }

        guard readerSettings.pageMode != .scroll else {
            return false
        }

        let location = panGesture.location(in: view)
        guard topBar.frame.contains(location) == false,
              bottomBar.frame.contains(location) == false
        else {
            return false
        }

        let velocity = panGesture.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    private nonisolated static func selectedChapter(
        from chapters: [Chapter],
        progress: ReadingProgress?
    ) -> (index: Int, chapter: Chapter, offset: Int)? {
        guard chapters.isEmpty == false else {
            return nil
        }

        let index: Int
        let restoredChapterID = progress?.chapterID
        if let chapterID = progress?.chapterID,
           let progressIndex = chapters.firstIndex(where: { $0.id == chapterID }) {
            index = progressIndex
        } else {
            index = 0
        }

        let chapter = chapters[index]
        var offset = restoredChapterID == nil ? 0 : Int(progress?.chapterOffset ?? 0)
        if offset >= chapter.byteLength,
           chapters.indices.contains(index + 1) {
            let nextChapter = chapters[index + 1]
            return (index + 1, nextChapter, 0)
        }

        offset = min(max(offset, 0), max(chapter.byteLength - 1, 0))
        return (index, chapter, offset)
    }

    private nonisolated static func readChapterText(
        book: Book,
        chapter: Chapter,
        fileStore: AppFileStore
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let relativePath = book.normalizedPath ?? book.sourcePath
            let url = try fileStore.url(forRelativePath: relativePath)
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            try handle.seek(toOffset: UInt64(chapter.startOffset))
            let data = handle.readData(ofLength: chapter.byteLength)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ReaderLoadError.invalidUTF8Cache
            }
            return text
        }.value
    }
}

private enum ReaderLoadError: LocalizedError {
    case invalidUTF8Cache

    var errorDescription: String? {
        switch self {
        case .invalidUTF8Cache:
            return NSLocalizedString("reader.error.invalidUTF8Cache", comment: "")
        }
    }
}

private extension ReaderViewController {
    static let bookmarkMatchTolerance = 8
    static let bookmarkPreviewCharacterLimit = 120
}

private struct PrefetchedChapter: @unchecked Sendable {
    let index: Int
    let chapter: Chapter
    let text: String
    let paginator: ChapterPaginator?
    let settings: ReaderSettings
    let filterRules: [TextFilterRule]
    let fittingSize: CGSize
}

struct ReaderContentTarget {
    let chapterID: UUID
    let offset: Int
}

private extension NumberFormatter {
    static let readerPercent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct ReaderTypography: @unchecked Sendable {
    var fontSize: Double
    var lineSpacing: Double
    var paragraphSpacing: Double
    var textColor: UIColor

    init(settings: ReaderSettings) {
        fontSize = settings.normalized.fontSize
        lineSpacing = 4
        paragraphSpacing = 8
        textColor = settings.theme.textColor
    }

    func attributedString(for text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(paragraphSpacing)
        let baseFont = UIFont.systemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)

        return NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
        )
    }
}

private extension ReaderSettings.Theme {
    var backgroundColor: UIColor {
        switch self {
        case .white:
            return .systemBackground
        case .eyeCare:
            return UIColor(red: 0.92, green: 0.97, blue: 0.90, alpha: 1)
        case .paper:
            return UIColor(red: 0.97, green: 0.94, blue: 0.86, alpha: 1)
        case .dark:
            return UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        }
    }

    var textColor: UIColor {
        switch self {
        case .white:
            return .label
        case .eyeCare:
            return UIColor(red: 0.11, green: 0.18, blue: 0.12, alpha: 1)
        case .paper:
            return UIColor(red: 0.18, green: 0.13, blue: 0.08, alpha: 1)
        case .dark:
            return UIColor(red: 0.88, green: 0.88, blue: 0.86, alpha: 1)
        }
    }

    var secondaryTextColor: UIColor {
        switch self {
        case .dark:
            return UIColor(red: 0.70, green: 0.70, blue: 0.68, alpha: 1)
        default:
            return .secondaryLabel
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}

final class ReaderContentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private enum Mode: Int, CaseIterable {
        case chapters
        case bookmarks
    }

    private enum Layout {
        static let searchHeaderHeight: CGFloat = 56
        static let catalogEstimatedRowHeight: CGFloat = 52
        static let bookmarkEstimatedRowHeight: CGFloat = 118
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
    private var isCatalogJumpingToBottom = false
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
        segmentedControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 188).isActive = true
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
        dismiss(animated: true)
    }

    @objc private func segmentChanged() {
        guard let mode = Mode(rawValue: segmentedControl.selectedSegmentIndex) else {
            return
        }

        currentMode = mode
        isCatalogJumpingToBottom = false
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

        isCatalogJumpingToBottom.toggle()
        scrollToChapterRow(
            isCatalogJumpingToBottom ? displayedChapterItems.count - 1 : 0,
            at: isCatalogJumpingToBottom ? .bottom : .top,
            animated: true
        )
        updateCatalogJumpButton()
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
        bookmarks.removeAll { $0.id == bookmark.id }
        tableView.reloadData()
        updateBackgroundView()
        onBookmarksChanged(bookmarks)
        let repository = repository
        Task {
            try? await repository.deleteBookmark(id: bookmark.id)
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
                isCatalogJumpingToBottom
                    ? "reader.catalog.jumpTop"
                    : "reader.catalog.jumpBottom",
                comment: ""
            ),
            style: .plain,
            target: self,
            action: #selector(catalogJumpButtonTapped)
        )
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

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        revealSearchHeader(animated: true)
    }

    func searchBar(
        _ searchBar: UISearchBar,
        textDidChange searchText: String
    ) {
        self.searchText = searchText
        isCatalogJumpingToBottom = false
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
        isCatalogJumpingToBottom = false
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

private final class ReaderSettingsViewController: UIViewController {
    private var settings: ReaderSettings
    private let onChange: (ReaderSettings) -> Void
    private let fontValueLabel = UILabel()
    private let fontStepper = UIStepper()
    private lazy var pageModeControl = UISegmentedControl(
        items: ReaderSettings.PageMode.allCases.map(\.localizedTitle)
    )
    private lazy var themeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.localizedTitle)
    )

    init(
        settings: ReaderSettings,
        onChange: @escaping (ReaderSettings) -> Void
    ) {
        self.settings = settings.normalized
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.settings.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.close", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )

        configureControls()
    }

    private func configureControls() {
        pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases
            .firstIndex(of: settings.pageMode) ?? 0
        pageModeControl.addTarget(self, action: #selector(pageModeChanged), for: .valueChanged)

        themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases
            .firstIndex(of: settings.theme) ?? 0
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)

        fontStepper.minimumValue = ReaderSettings.minimumFontSize
        fontStepper.maximumValue = ReaderSettings.maximumFontSize
        fontStepper.stepValue = 1
        fontStepper.value = settings.fontSize
        fontStepper.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        updateFontValueLabel()

        let fontRow = UIStackView(arrangedSubviews: [fontValueLabel, fontStepper])
        fontRow.axis = .horizontal
        fontRow.alignment = .center
        fontRow.spacing = 12
        fontRow.distribution = .equalSpacing

        let stackView = UIStackView(arrangedSubviews: [
            settingsSection(
                title: NSLocalizedString("reader.settings.pageMode", comment: ""),
                control: pageModeControl
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.fontSize", comment: ""),
                control: fontRow
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.theme", comment: ""),
                control: themeControl
            )
        ])
        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    private func settingsSection(title: String, control: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        let stackView = UIStackView(arrangedSubviews: [titleLabel, control])
        stackView.axis = .vertical
        stackView.spacing = 8
        return stackView
    }

    private func updateFontValueLabel() {
        fontValueLabel.text = String(
            format: NSLocalizedString("reader.settings.fontSize.value", comment: ""),
            Int(settings.fontSize)
        )
        fontValueLabel.font = .preferredFont(forTextStyle: .body)
        fontValueLabel.adjustsFontForContentSizeCategory = true
    }

    @objc private func pageModeChanged() {
        let index = pageModeControl.selectedSegmentIndex
        guard ReaderSettings.PageMode.allCases.indices.contains(index) else {
            return
        }
        settings.pageMode = ReaderSettings.PageMode.allCases[index]
        onChange(settings)
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard ReaderSettings.Theme.allCases.indices.contains(index) else {
            return
        }
        settings.theme = ReaderSettings.Theme.allCases[index]
        onChange(settings)
    }

    @objc private func fontSizeChanged() {
        settings.fontSize = fontStepper.value
        updateFontValueLabel()
        onChange(settings)
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
}

private extension ReaderSettings.PageMode {
    var localizedTitle: String {
        switch self {
        case .paged:
            return NSLocalizedString("reader.settings.pageMode.paged", comment: "")
        case .scroll:
            return NSLocalizedString("reader.settings.pageMode.scroll", comment: "")
        }
    }
}

private extension ReaderSettings.Theme {
    var localizedTitle: String {
        switch self {
        case .white:
            return NSLocalizedString("reader.settings.theme.white", comment: "")
        case .eyeCare:
            return NSLocalizedString("reader.settings.theme.eyeCare", comment: "")
        case .paper:
            return NSLocalizedString("reader.settings.theme.paper", comment: "")
        case .dark:
            return NSLocalizedString("reader.settings.theme.dark", comment: "")
        }
    }
}

private final class ChapterPaginator: @unchecked Sendable {
    struct Page {
        let attributedText: NSAttributedString
        let startDisplayUTF16Index: Int
        let displayUTF16Length: Int
    }

    private let attributedText: NSAttributedString
    private(set) var pageCharacterRanges: [NSRange] = []
    private(set) var pageStartDisplayUTF16Indexes: [Int] = []

    var pageCount: Int {
        pageCharacterRanges.count
    }

    init(
        text: String,
        typography: ReaderTypography,
        fittingSize: CGSize
    ) {
        attributedText = typography.attributedString(for: text)
        buildPages(fittingSize: fittingSize)
    }

    func page(at index: Int) -> Page {
        guard pageCharacterRanges.isEmpty == false else {
            return Page(
                attributedText: NSAttributedString(string: ""),
                startDisplayUTF16Index: 0,
                displayUTF16Length: 0
            )
        }

        let safeIndex = min(max(index, 0), pageCharacterRanges.count - 1)
        let range = pageCharacterRanges[safeIndex]
        let pageText = attributedText.attributedSubstring(from: range)

        return Page(
            attributedText: pageText,
            startDisplayUTF16Index: range.location,
            displayUTF16Length: range.length
        )
    }

    func pageStartDisplayUTF16Index(at index: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let safeIndex = min(max(index, 0), pageStartDisplayUTF16Indexes.count - 1)
        return pageStartDisplayUTF16Indexes[safeIndex]
    }

    func pageIndex(containingDisplayUTF16Index displayIndex: Int) -> Int {
        guard pageStartDisplayUTF16Indexes.isEmpty == false else {
            return 0
        }

        let clampedIndex = min(max(displayIndex, 0), attributedText.length)
        var lowerBound = 0
        var upperBound = pageStartDisplayUTF16Indexes.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if pageStartDisplayUTF16Indexes[middle] <= clampedIndex {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        return max(0, lowerBound - 1)
    }

    private func buildPages(fittingSize: CGSize) {
        let textLength = attributedText.length
        guard textLength > 0 else {
            return
        }

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage(attributedString: attributedText)
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            size: CGSize(
                width: max(fittingSize.width, 1),
                height: .greatestFiniteMagnitude
            )
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)

        let glyphCount = layoutManager.numberOfGlyphs
        var pageStartGlyphIndex = 0
        let pageHeight = max(fittingSize.height, 1)

        while pageStartGlyphIndex < glyphCount {
            let firstLineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: pageStartGlyphIndex,
                effectiveRange: nil
            )
            let pageBottom = firstLineRect.minY + pageHeight
            var scanGlyphIndex = pageStartGlyphIndex
            var pageEndGlyphIndex = pageStartGlyphIndex

            while scanGlyphIndex < glyphCount {
                var lineRange = NSRange()
                let lineRect = layoutManager.lineFragmentUsedRect(
                    forGlyphAt: scanGlyphIndex,
                    effectiveRange: &lineRange
                )
                let isFirstLine = pageEndGlyphIndex == pageStartGlyphIndex
                if !isFirstLine,
                   lineRect.maxY > pageBottom {
                    break
                }

                pageEndGlyphIndex = max(
                    pageEndGlyphIndex,
                    lineRange.location + lineRange.length
                )

                guard pageEndGlyphIndex > scanGlyphIndex else {
                    pageEndGlyphIndex = scanGlyphIndex + 1
                    break
                }

                scanGlyphIndex = pageEndGlyphIndex
            }

            let pageGlyphRange = NSRange(
                location: pageStartGlyphIndex,
                length: max(pageEndGlyphIndex - pageStartGlyphIndex, 1)
            )
            var characterRange = layoutManager.characterRange(
                forGlyphRange: pageGlyphRange,
                actualGlyphRange: nil
            )
            characterRange.location = min(characterRange.location, textLength)
            characterRange.length = min(characterRange.length, textLength - characterRange.location)

            guard characterRange.length > 0 else {
                break
            }

            pageCharacterRanges.append(characterRange)
            pageStartDisplayUTF16Indexes.append(characterRange.location)

            if pageEndGlyphIndex >= glyphCount {
                break
            }
            pageStartGlyphIndex = pageEndGlyphIndex
        }

        if pageCharacterRanges.isEmpty {
            pageCharacterRanges = [NSRange(location: 0, length: textLength)]
            pageStartDisplayUTF16Indexes = [0]
        }
    }
}
