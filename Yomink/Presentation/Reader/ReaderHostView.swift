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
final class ReaderViewController: UIViewController {
    private let fileStore: AppFileStore
    private let repository: any LibraryRepository
    private let onClose: () -> Void

    private let textView = UITextView()
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let progressLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)

    private var book: Book
    private var chapters: [Chapter] = []
    private var currentChapterIndex = 0
    private var currentChapterText = ""
    private var currentPaginator: ChapterPaginator?
    private var currentPageIndex = 0
    private var currentProgress: ReadingProgress?
    private var loadTask: Task<Void, Never>?
    private var paginateTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0
    private var paginateGeneration = 0
    private var isMenuVisible = false
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
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureTextView()
        configureMenus()
        configureLoadingIndicator()
        configureGestures()
        startInitialLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let size = textView.bounds.size
        guard currentChapterText.isEmpty == false,
              size.width > 0,
              size.height > 0,
              abs(size.width - lastPaginationSize.width) > 1
                || abs(size.height - lastPaginationSize.height) > 1
        else {
            return
        }

        lastPaginationSize = size
        rebuildPaginator(
            anchorByteOffset: currentPaginator?.pageStartByteOffset(at: currentPageIndex) ?? 0,
            savingProgress: false
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveProgressImmediately()
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

        let previousButton = UIButton(type: .system)
        previousButton.setImage(UIImage(systemName: "chevron.left.circle"), for: .normal)
        previousButton.accessibilityLabel = NSLocalizedString("reader.previousPage", comment: "")
        previousButton.addTarget(self, action: #selector(previousButtonTapped), for: .touchUpInside)
        previousButton.translatesAutoresizingMaskIntoConstraints = false

        let nextButton = UIButton(type: .system)
        nextButton.setImage(UIImage(systemName: "chevron.right.circle"), for: .normal)
        nextButton.accessibilityLabel = NSLocalizedString("reader.nextPage", comment: "")
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        progressLabel.font = .preferredFont(forTextStyle: .footnote)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textAlignment = .center
        progressLabel.textColor = .secondaryLabel
        progressLabel.numberOfLines = 2
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        bottomBar.contentView.addSubview(previousButton)
        bottomBar.contentView.addSubview(progressLabel)
        bottomBar.contentView.addSubview(nextButton)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -72),

            previousButton.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 18),
            previousButton.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 12),
            previousButton.widthAnchor.constraint(equalToConstant: 44),
            previousButton.heightAnchor.constraint(equalToConstant: 44),

            nextButton.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -18),
            nextButton.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44),

            progressLabel.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 12),
            progressLabel.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -12),
            progressLabel.centerYAnchor.constraint(equalTo: previousButton.centerYAnchor)
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
        view.addGestureRecognizer(tapGesture)
    }

    private func startInitialLoad() {
        loadTask?.cancel()
        paginateTask?.cancel()
        saveTask?.cancel()
        paginateGeneration += 1
        chapters = []
        currentChapterText = ""
        currentPaginator = nil
        currentChapterIndex = 0
        currentPageIndex = 0
        currentProgress = nil
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
                async let markOpened: Void = repository.markBookOpened(id: book.id, at: Date())

                let chapters = try await fetchedChapters
                let progress = try await fetchedProgress
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

        loadTask?.cancel()
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
        saveAfterRender: Bool
    ) {
        self.chapters = chapters
        currentChapterIndex = chapterIndex
        currentChapterText = text
        currentPaginator = nil
        currentPageIndex = 0
        lastPaginationSize = textView.bounds.size
        rebuildPaginator(anchorByteOffset: startOffset, savingProgress: saveAfterRender)
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
        let typography = ReaderTypography.default

        // Phase 3: consider adjacent chapter paginator prefetch near chapter
        // edges, coordinated with typography/settings changes and cancellation.
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
        updateProgress()

        if shouldSave {
            scheduleProgressSave()
        }
    }

    private func moveToNextPage() {
        guard currentChapterText.isEmpty == false else {
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

    private func updateProgress() {
        guard chapters.indices.contains(currentChapterIndex) else {
            return
        }

        let chapter = chapters[currentChapterIndex]
        let pageStartByteOffset = currentPaginator?.pageStartByteOffset(at: currentPageIndex) ?? 0
        let totalByteLength = max(chapters.last?.endOffset ?? chapter.endOffset, 1)
        let absoluteOffset = chapter.startOffset + pageStartByteOffset
        let globalProgress = min(max(Double(absoluteOffset) / Double(totalByteLength), 0), 1)
        let chapterProgress = chapter.byteLength > 0
            ? min(max(Double(pageStartByteOffset) / Double(chapter.byteLength), 0), 1)
            : 0

        currentProgress = ReadingProgress(
            bookID: book.id,
            chapterID: chapter.id,
            chapterOffset: Int64(pageStartByteOffset),
            globalProgress: globalProgress
        )

        progressLabel.text = String(
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

    @objc private func previousButtonTapped() {
        moveToPreviousPage()
    }

    @objc private func nextButtonTapped() {
        moveToNextPage()
    }

    @objc private func closeButtonTapped() {
        saveProgressImmediately()
        onClose()
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
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
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

private struct ReaderTypography: Sendable {
    var textStyle: String
    var lineSpacing: Double
    var paragraphSpacing: Double

    static var `default`: ReaderTypography {
        ReaderTypography(
            textStyle: UIFont.TextStyle.body.rawValue,
            lineSpacing: 4,
            paragraphSpacing: 8
        )
    }

    func attributedString(for text: String) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(paragraphSpacing)

        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: UIFont.TextStyle(textStyle)),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
        )
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
