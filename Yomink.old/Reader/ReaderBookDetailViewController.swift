import SwiftUI
import UIKit

@MainActor
final class ReaderBookDetailViewController: UIViewController {
    private var book: Book
    private let repository: any LibraryRepository
    private let fileStore: AppFileStore
    private let chapters: [Chapter]
    private let selectedChapterIndex: Int
    private let onBookUpdated: (Book) -> Void
    private let onBookmarksChanged: ([Bookmark]) -> Void
    private let onSelectCatalogTarget: (ReaderContentTarget) -> Void
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let introLabel = UILabel()
    private let tagBubbleWrapView = ReaderTagBubbleWrapView()
    private var tags: [BookTag] = []

    init(
        book: Book,
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        chapters: [Chapter],
        selectedChapterIndex: Int,
        onBookUpdated: @escaping (Book) -> Void,
        onBookmarksChanged: @escaping ([Bookmark]) -> Void,
        onSelectCatalogTarget: @escaping (ReaderContentTarget) -> Void
    ) {
        self.book = book
        self.repository = repository
        self.fileStore = fileStore
        self.chapters = chapters
        self.selectedChapterIndex = selectedChapterIndex
        self.onBookUpdated = onBookUpdated
        self.onBookmarksChanged = onBookmarksChanged
        self.onSelectCatalogTarget = onSelectCatalogTarget
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
        configureCloseButtonIfNeeded()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.edit", comment: ""),
            style: .plain,
            target: self,
            action: #selector(editButtonTapped)
        )
        configureLayout()
        render()
        loadTags()
        loadIntroFallbackIfNeeded()
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
        stackView.addArrangedSubview(tagsCard())
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

    private func tagsCard() -> UIView {
        let titleLabel = sectionTitle(NSLocalizedString("tags.field.title", comment: ""))
        tagBubbleWrapView.configure(tags: tags)

        let stack = UIStackView(arrangedSubviews: [titleLabel, tagBubbleWrapView])
        stack.axis = .vertical
        stack.spacing = 8
        return card(containing: stack)
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
            let text: String
            do {
                text = try await ReaderChapterTextReader.readTextAsync(
                    book: book,
                    chapter: chapter,
                    fileStore: fileStore
                )
            } catch {
                await MainActor.run {
                    self?.showError(error)
                }
                return
            }
            let intro = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            await MainActor.run {
                guard let self else {
                    return
                }
                guard (self.book.intro ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return
                }
                if intro.isEmpty {
                    self.introLabel.text = NSLocalizedString("reader.bookDetail.emptyIntro", comment: "")
                } else {
                    self.book.intro = intro
                    self.introLabel.text = intro
                }
            }
        }
    }

    private func loadTags() {
        let bookID = book.id
        let repository = repository
        Task { [weak self] in
            do {
                let fetchedTags = try await repository.fetchTags(bookID: bookID)
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.tags = fetchedTags
                    self.tagBubbleWrapView.configure(tags: fetchedTags)
                }
            } catch {
                await MainActor.run {
                    self?.showError(error)
                }
            }
        }
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    @objc private func editButtonTapped() {
        let editViewController = ReaderBookDetailEditViewController(
            book: book,
            repository: repository
        ) { [weak self] updatedBook in
            guard let self else {
                return
            }
            self.book = updatedBook
            self.onBookUpdated(updatedBook)
            self.render()
            self.loadTags()
            self.loadIntroFallbackIfNeeded()
        }
        navigationController?.pushViewController(editViewController, animated: true)
    }

    @objc private func showCatalogButtonTapped() {
        let contentsViewController = ReaderContentsViewController(
            bookID: book.id,
            repository: repository,
            chapters: chapters,
            selectedChapterIndex: selectedChapterIndex,
            onBookmarksChanged: onBookmarksChanged,
            onSelect: onSelectCatalogTarget
        )
        navigationController?.pushViewController(contentsViewController, animated: true)
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

private final class ReaderTagBubbleWrapView: UIView {
    private var arrangedViews: [UIView] = []
    private let itemSpacing: CGFloat = 8
    private let lineSpacing: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tags: [BookTag]) {
        arrangedViews.forEach { $0.removeFromSuperview() }

        if tags.isEmpty {
            let label = UILabel()
            label.text = NSLocalizedString("tags.none", comment: "")
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .secondaryLabel
            arrangedViews = [label]
        } else {
            arrangedViews = tags.map { tag in
                let label = ReaderTagBubbleLabel()
                label.text = tag.name
                return label
            }
        }

        arrangedViews.forEach(addSubview)
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        _ = layoutArrangedViews(maxWidth: bounds.width, shouldApplyFrames: true)
    }

    override var intrinsicContentSize: CGSize {
        let fallbackWidth = UIScreen.main.bounds.width - 64
        return CGSize(
            width: UIView.noIntrinsicMetric,
            height: layoutArrangedViews(
                maxWidth: bounds.width > 0 ? bounds.width : fallbackWidth,
                shouldApplyFrames: false
            )
        )
    }

    private func layoutArrangedViews(
        maxWidth: CGFloat,
        shouldApplyFrames: Bool
    ) -> CGFloat {
        let availableWidth = max(maxWidth, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in arrangedViews {
            let size = view.intrinsicContentSize
            if x > 0,
               x + size.width > availableWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            if shouldApplyFrames {
                view.frame = CGRect(
                    origin: CGPoint(x: x, y: y),
                    size: size
                )
            }

            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return y + rowHeight
    }
}

private final class ReaderTagBubbleLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let baseFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
            weight: .medium
        )
        font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: baseFont)
        adjustsFontForContentSizeCategory = true
        textColor = tintColor
        backgroundColor = tintColor.withAlphaComponent(0.12)
        layer.cornerRadius = 8
        layer.masksToBounds = true
        numberOfLines = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}

