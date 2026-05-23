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
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressSlider = UISlider()
    private let previousChapterButton = UIButton(type: .system)
    private let nextChapterButton = UIButton(type: .system)
    private let catalogButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var book: Book
    private var chapters: [Chapter] = []
    private var currentChapterIndex = 0
    private var currentChapterText = ""
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
    private var saveGeneration = 0
    private var settingsSaveGeneration = 0
    private var settingsRenderGeneration = 0
    private var settingsRenderNeedsTrailingRender = false
    private var paginateGeneration = 0
    private var prefetchGeneration = 0
    private var readerSettings = ReaderSettings.default
    private var prefetchedChapter: PrefetchedChapter?
    private var prefetchingChapterID: UUID?
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
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28)
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

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        topBar.contentView.addSubview(closeButton)
        topBar.contentView.addSubview(titleLabel)
        topBar.contentView.addSubview(spacer)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),

            closeButton.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 12),
            closeButton.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),

            spacer.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            spacer.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -12),
            spacer.widthAnchor.constraint(equalTo: closeButton.widthAnchor)
        ])
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
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -132),

            progressRow.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 18),
            progressRow.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -18),
            progressRow.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 12),
            progressRow.heightAnchor.constraint(equalToConstant: 32),

            previousChapterButton.widthAnchor.constraint(equalToConstant: 44),
            nextChapterButton.widthAnchor.constraint(equalToConstant: 44),

            progressLabel.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 18),
            progressLabel.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -18),
            progressLabel.topAnchor.constraint(equalTo: progressRow.bottomAnchor, constant: 8),

            actionRow.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 18),
            actionRow.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -18),
            actionRow.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            actionRow.heightAnchor.constraint(equalToConstant: 34)
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
        currentChapterText = ""
        currentPaginator = nil
        prefetchedChapter = nil
        prefetchingChapterID = nil
        currentChapterIndex = 0
        currentPageIndex = 0
        currentProgress = nil
        pendingAnchorByteOffset = nil
        titleLabel.text = book.title
        textView.text = nil
        showLoading(true, message: NSLocalizedString("reader.loading", comment: ""))

        let book = book
        let fileStore = fileStore
        let repository = repository

        loadTask = Task { [weak self] in
            do {
                async let fetchedChapters = repository.fetchChapters(bookID: book.id)
                async let fetchedProgress = repository.fetchReadingProgress(bookID: book.id)
                async let fetchedSettings = repository.fetchReaderSettings()
                async let markOpened: Void = repository.markBookOpened(id: book.id, at: Date())

                let chapters = try await fetchedChapters
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
        chapterIndex: Int,
        text: String,
        startOffset: Int,
        settings: ReaderSettings? = nil,
        saveAfterRender: Bool
    ) {
        self.chapters = chapters
        if let settings = settings {
            readerSettings = settings.normalized
        }
        currentChapterIndex = chapterIndex
        currentChapterText = text
        currentPaginator = nil
        currentPageIndex = 0
        pendingAnchorByteOffset = startOffset
        setProvisionalProgress(chapterOffset: startOffset)
        if prefetchedChapter?.chapter.id != chapters[chapterIndex].id {
            prefetchedChapter = nil
            prefetchingChapterID = nil
        }
        lastPaginationSize = textView.bounds.size
        renderContent(anchorByteOffset: startOffset, savingProgress: saveAfterRender)
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
        currentChapterText = prefetchedChapter.text
        currentPaginator = nil
        currentPageIndex = 0
        pendingAnchorByteOffset = startOffset
        setProvisionalProgress(chapterOffset: startOffset)
        lastPaginationSize = textView.bounds.size
        applyTheme()
        textView.transform = .identity
        textView.alpha = 1

        if readerSettings.pageMode == .paged,
           let paginator = prefetchedChapter.paginator {
            textView.isScrollEnabled = false
            currentPaginator = paginator
            currentPageIndex = paginator.pageIndex(containingByteOffset: startOffset)
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
                        let paginator = ChapterPaginator(
                            text: text,
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
        currentPageIndex = paginator.pageIndex(containingByteOffset: anchorByteOffset)
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

        let chapter = chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex]
            : nil
        let chapterLength = max(chapter?.byteLength ?? 0, 1)
        let ratio = min(max(Double(anchorByteOffset) / Double(chapterLength), 0), 1)
        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 0)
        isApplyingProgrammaticScroll = true
        textView.setContentOffset(
            CGPoint(x: 0, y: CGFloat(ratio) * maxOffset),
            animated: false
        )
        isApplyingProgrammaticScroll = false
        updateProgress(chapterOffset: anchorByteOffset)
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
        updateProgress(chapterOffset: page.startByteOffset)
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

        let chapter = chapters[currentChapterIndex]
        let maxOffset = max(textView.contentSize.height - textView.bounds.height, 1)
        let yOffset = min(max(textView.contentOffset.y, 0), maxOffset)
        let ratio = min(max(Double(yOffset / maxOffset), 0), 1)
        let chapterOffset = Int(Double(chapter.byteLength) * ratio)
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
        readerSettings = normalizedSettings
        invalidatePrefetch()
        applyTheme()
        if requiresImmediateRerender {
            cancelSettingsRender()
            renderContent(anchorByteOffset: anchorByteOffset, savingProgress: false)
        } else {
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

        let width = view.bounds.width
        if location.x < width / 3 {
            moveToPreviousPage()
        } else if location.x > width * 2 / 3 {
            moveToNextPage()
        } else {
            setMenuVisible(!isMenuVisible, animated: true)
        }
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
        let listViewController = ReaderChapterListViewController(
            chapters: chapters,
            selectedIndex: currentChapterIndex
        ) { [weak self] index in
            guard let self else {
                return
            }
            self.dismiss(animated: true) {
                self.loadChapter(at: index, startOffset: 0, saveAfterRender: true)
            }
        }
        let navigationController = UINavigationController(rootViewController: listViewController)
        navigationController.overrideUserInterfaceStyle = readerSettings.theme.userInterfaceStyle
        navigationController.modalPresentationStyle = .pageSheet
        present(navigationController, animated: true)
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
        return currentPaginator?.pageStartByteOffset(at: currentPageIndex) ?? 0
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

private struct PrefetchedChapter: @unchecked Sendable {
    let index: Int
    let chapter: Chapter
    let text: String
    let paginator: ChapterPaginator?
    let settings: ReaderSettings
    let fittingSize: CGSize
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

private final class ReaderChapterListViewController: UITableViewController {
    private let chapters: [Chapter]
    private let selectedIndex: Int
    private let onSelect: (Int) -> Void

    init(
        chapters: [Chapter],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void
    ) {
        self.chapters = chapters
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        super.init(style: .plain)
        title = NSLocalizedString("reader.catalog.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.close", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )

        if chapters.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = NSLocalizedString("reader.catalog.empty", comment: "")
            emptyLabel.textAlignment = .center
            emptyLabel.textColor = .secondaryLabel
            emptyLabel.numberOfLines = 0
            tableView.backgroundView = emptyLabel
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapters.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let reuseIdentifier = "chapter"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: reuseIdentifier)
        let chapter = chapters[indexPath.row]
        cell.textLabel?.text = chapter.title
        cell.detailTextLabel?.text = String(
            format: NSLocalizedString("reader.catalog.chapterProgress", comment: ""),
            NumberFormatter.readerPercent.string(
                from: NSNumber(value: chapterStartProgress(for: chapter))
            ) ?? "0%"
        )
        cell.accessoryType = indexPath.row == selectedIndex ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect(indexPath.row)
    }

    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }

    private func chapterStartProgress(for chapter: Chapter) -> Double {
        let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        return min(max(Double(chapter.startOffset) / Double(totalByteLength), 0), 1)
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
        let startByteOffset: Int
        let byteLength: Int
    }

    private let attributedText: NSAttributedString
    private let utf8OffsetsByCharacterIndex: [Int]
    private(set) var pageCharacterRanges: [NSRange] = []
    private(set) var pageStartByteOffsets: [Int] = []

    var pageCount: Int {
        pageCharacterRanges.count
    }

    init(
        text: String,
        typography: ReaderTypography,
        fittingSize: CGSize
    ) {
        attributedText = typography.attributedString(for: text)
        utf8OffsetsByCharacterIndex = Self.makeUTF8Offsets(for: text)
        buildPages(fittingSize: fittingSize)
    }

    func page(at index: Int) -> Page {
        guard pageCharacterRanges.isEmpty == false else {
            return Page(attributedText: NSAttributedString(string: ""), startByteOffset: 0, byteLength: 0)
        }

        let safeIndex = min(max(index, 0), pageCharacterRanges.count - 1)
        let range = pageCharacterRanges[safeIndex]
        let startOffset = pageStartByteOffset(at: safeIndex)
        let endOffset = byteOffset(atCharacterIndex: range.location + range.length)
        let pageText = attributedText.attributedSubstring(from: range)

        return Page(
            attributedText: pageText,
            startByteOffset: startOffset,
            byteLength: max(endOffset - startOffset, 0)
        )
    }

    func pageStartByteOffset(at index: Int) -> Int {
        guard pageStartByteOffsets.isEmpty == false else {
            return 0
        }

        let safeIndex = min(max(index, 0), pageStartByteOffsets.count - 1)
        return pageStartByteOffsets[safeIndex]
    }

    func pageIndex(containingByteOffset byteOffset: Int) -> Int {
        guard pageStartByteOffsets.isEmpty == false else {
            return 0
        }

        let clampedOffset = min(max(byteOffset, 0), utf8OffsetsByCharacterIndex.last ?? 0)
        var lowerBound = 0
        var upperBound = pageStartByteOffsets.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if pageStartByteOffsets[middle] <= clampedOffset {
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
            pageStartByteOffsets.append(byteOffset(atCharacterIndex: characterRange.location))

            if pageEndGlyphIndex >= glyphCount {
                break
            }
            pageStartGlyphIndex = pageEndGlyphIndex
        }

        if pageCharacterRanges.isEmpty {
            pageCharacterRanges = [NSRange(location: 0, length: textLength)]
            pageStartByteOffsets = [0]
        }
    }

    private func byteOffset(atCharacterIndex characterIndex: Int) -> Int {
        let safeIndex = min(max(characterIndex, 0), utf8OffsetsByCharacterIndex.count - 1)
        return utf8OffsetsByCharacterIndex[safeIndex]
    }

    private static func makeUTF8Offsets(for text: String) -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(text.utf16.count + 1)

        var offset = 0
        offsets.append(offset)
        for character in text {
            let characterText = String(character)
            let previousOffset = offset
            offset += characterText.utf8.count
            let utf16Length = characterText.utf16.count
            if utf16Length > 1 {
                offsets.append(
                    contentsOf: Array(repeating: previousOffset, count: utf16Length - 1)
                )
            }
            offsets.append(offset)
        }

        return offsets
    }
}
