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

@MainActor
final class ReaderBookDetailEditViewController: UIViewController, UITextViewDelegate {
    private var book: Book
    private let repository: any LibraryRepository
    private let onSaved: (Book) -> Void
    private let stackView = UIStackView()
    private let titleTextField = UITextField()
    private let authorTextField = UITextField()
    private let tagsButton = UIButton(type: .system)
    private let introTextView = UITextView()
    private var availableTagNames: [UUID: String] = [:]
    private var selectedTagIDs: Set<UUID> = []

    init(
        book: Book,
        repository: any LibraryRepository,
        onSaved: @escaping (Book) -> Void
    ) {
        self.book = book
        self.repository = repository
        self.onSaved = onSaved
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.bookDetail.editTitle", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.save", comment: ""),
            style: .done,
            target: self,
            action: #selector(saveButtonTapped)
        )
        configureFields()
        configureLayout()
        loadTags()
    }

    private func configureFields() {
        configureTextField(
            titleTextField,
            placeholder: NSLocalizedString("reader.bookDetail.name", comment: "")
        )
        titleTextField.text = book.title
        titleTextField.returnKeyType = .next
        titleTextField.addTarget(
            self,
            action: #selector(titleReturnTapped),
            for: .editingDidEndOnExit
        )

        configureTextField(
            authorTextField,
            placeholder: NSLocalizedString("reader.bookDetail.author", comment: "")
        )
        authorTextField.text = book.author
        authorTextField.returnKeyType = .next
        authorTextField.addTarget(
            self,
            action: #selector(authorReturnTapped),
            for: .editingDidEndOnExit
        )

        configureTagsButton()

        introTextView.text = book.intro ?? ""
        introTextView.font = .preferredFont(forTextStyle: .body)
        introTextView.adjustsFontForContentSizeCategory = true
        introTextView.backgroundColor = .clear
        introTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        introTextView.delegate = self
        introTextView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureTextField(
        _ textField: UITextField,
        placeholder: String
    ) {
        textField.placeholder = placeholder
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.backgroundColor = .clear
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    private func configureTagsButton() {
        tagsButton.contentHorizontalAlignment = .right
        tagsButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        tagsButton.titleLabel?.adjustsFontForContentSizeCategory = true
        tagsButton.titleLabel?.lineBreakMode = .byTruncatingTail
        tagsButton.setTitleColor(.secondaryLabel, for: .normal)
        tagsButton.addTarget(
            self,
            action: #selector(tagsButtonTapped),
            for: .touchUpInside
        )
        tagsButton.translatesAutoresizingMaskIntoConstraints = false
        tagsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        updateTagsButtonTitle()
    }

    private func configureLayout() {
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        stackView.addArrangedSubview(
            fieldRow(
                title: NSLocalizedString("reader.bookDetail.name", comment: ""),
                content: titleTextField
            )
        )
        stackView.addArrangedSubview(
            fieldRow(
                title: NSLocalizedString("reader.bookDetail.author", comment: ""),
                content: authorTextField
            )
        )
        stackView.addArrangedSubview(
            fieldRow(
                title: NSLocalizedString("tags.field.title", comment: ""),
                content: tagsButton
            )
        )
        stackView.addArrangedSubview(introRow())

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),

            introTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    private func fieldRow(
        title: String,
        content: UIView
    ) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let row = UIStackView(arrangedSubviews: [titleLabel, content])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        return formContainer(containing: row, verticalInset: 0)
    }

    private func introRow() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("reader.bookDetail.intro", comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        let stack = UIStackView(arrangedSubviews: [titleLabel, introTextView])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        return formContainer(containing: stack, verticalInset: 12)
    }

    private func formContainer(
        containing content: UIView,
        verticalInset: CGFloat
    ) -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.layer.cornerRadius = 8
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalInset),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalInset)
        ])
        return container
    }

    @objc private func titleReturnTapped() {
        authorTextField.becomeFirstResponder()
    }

    @objc private func authorReturnTapped() {
        introTextView.becomeFirstResponder()
    }

    @objc private func tagsButtonTapped() {
        let picker = ReaderBookTagPickerHostView(
            repository: repository,
            initialSelectedTagIDs: selectedTagIDs,
            onSelectionChanged: { [weak self] nextValue in
                guard let self else {
                    return
                }
                self.selectedTagIDs = nextValue
                self.updateTagsButtonTitle()
            },
            onCatalogChanged: { [weak self] in
                self?.loadAvailableTags()
            }
        )
        let hostingController = UIHostingController(rootView: picker)
        navigationController?.pushViewController(hostingController, animated: true)
    }

    @objc private func saveButtonTapped() {
        view.endEditing(true)
        navigationItem.rightBarButtonItem?.isEnabled = false
        let title = titleTextField.text ?? book.title
        let author = authorTextField.text
        let intro = introTextView.text
        let tagIDs = selectedTagIDs

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
                try await repository.setBookTags(
                    bookID: book.id,
                    tagIDs: tagIDs
                )
                await MainActor.run {
                    self.book = updated
                    self.onSaved(updated)
                    self.navigationController?.popViewController(animated: true)
                }
            } catch {
                await MainActor.run {
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.showError(error)
                }
            }
        }
    }

    private func loadTags() {
        let bookID = book.id
        let repository = repository
        Task { [weak self] in
            do {
                async let fetchedUsages = repository.fetchTagsWithUsage()
                async let fetchedBookTags = repository.fetchTags(bookID: bookID)
                let usages = try await fetchedUsages
                let bookTags = try await fetchedBookTags

                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.availableTagNames = Dictionary(
                        uniqueKeysWithValues: usages.map { usage in
                            (usage.id, usage.tag.name)
                        }
                    )
                    for tag in bookTags {
                        self.availableTagNames[tag.id] = tag.name
                    }
                    self.selectedTagIDs = Set(bookTags.map(\.id))
                    self.updateTagsButtonTitle()
                }
            } catch {
                await MainActor.run {
                    self?.showError(error)
                }
            }
        }
    }

    private func loadAvailableTags() {
        let repository = repository
        Task { [weak self] in
            do {
                let usages = try await repository.fetchTagsWithUsage()
                await MainActor.run {
                    guard let self else {
                        return
                    }
                    self.availableTagNames = Dictionary(
                        uniqueKeysWithValues: usages.map { usage in
                            (usage.id, usage.tag.name)
                        }
                    )
                    self.updateTagsButtonTitle()
                }
            } catch {
                await MainActor.run {
                    self?.showError(error)
                }
            }
        }
    }

    private func updateTagsButtonTitle() {
        guard !selectedTagIDs.isEmpty else {
            tagsButton.setTitle(NSLocalizedString("tags.none", comment: ""), for: .normal)
            return
        }

        let names = selectedTagIDs
            .compactMap { availableTagNames[$0] }
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
        guard !names.isEmpty else {
            tagsButton.setTitle(
                String(
                    format: NSLocalizedString("tags.selected.count", comment: ""),
                    selectedTagIDs.count
                ),
                for: .normal
            )
            return
        }

        let visibleNames = names.prefix(3).joined(separator: ", ")
        if names.count <= 3 {
            tagsButton.setTitle(visibleNames, for: .normal)
        } else {
            tagsButton.setTitle(
                String(
                    format: NSLocalizedString("tags.summary.more", comment: ""),
                    visibleNames,
                    names.count - 3
                ),
                for: .normal
            )
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

private struct ReaderBookTagPickerHostView: View {
    let repository: any LibraryRepository
    let onSelectionChanged: (Set<UUID>) -> Void
    let onCatalogChanged: () -> Void

    @State private var selectedTagIDs: Set<UUID>

    init(
        repository: any LibraryRepository,
        initialSelectedTagIDs: Set<UUID>,
        onSelectionChanged: @escaping (Set<UUID>) -> Void,
        onCatalogChanged: @escaping () -> Void
    ) {
        self.repository = repository
        self.onSelectionChanged = onSelectionChanged
        self.onCatalogChanged = onCatalogChanged
        _selectedTagIDs = State(initialValue: initialSelectedTagIDs)
    }

    var body: some View {
        BookTagPickerPage(
            repository: repository,
            selectedTagIDs: $selectedTagIDs,
            onCatalogChanged: onCatalogChanged
        )
        .onChange(of: selectedTagIDs) { nextValue in
            onSelectionChanged(nextValue)
        }
        .onDisappear {
            onSelectionChanged(selectedTagIDs)
        }
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
        configureCloseButtonIfNeeded()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        updateEmptyState()
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
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rules.indices.contains(indexPath.row) else {
            return
        }

        showRuleEditor(rule: rules[indexPath.row])
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
            Task { [weak self] in
                guard let self else {
                    await MainActor.run {
                        completion(false)
                    }
                    return
                }
                do {
                    try await self.repository.deleteFilterRule(id: rule.id)
                    await MainActor.run {
                        guard let currentIndex = self.rules.firstIndex(where: { $0.id == rule.id }) else {
                            completion(false)
                            return
                        }
                        self.rules.remove(at: currentIndex)
                        self.tableView.deleteRows(
                            at: [IndexPath(row: currentIndex, section: indexPath.section)],
                            with: .automatic
                        )
                        self.updateEmptyState()
                        self.onRulesChanged(self.rules)
                        completion(true)
                    }
                } catch {
                    await MainActor.run {
                        completion(false)
                    }
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    @objc private func addButtonTapped() {
        showRuleEditor(rule: nil)
    }

    private func showRuleEditor(rule: TextFilterRule?) {
        let alert = UIAlertController(
            title: NSLocalizedString(
                rule == nil ? "reader.filter.addTitle" : "reader.filter.editTitle",
                comment: ""
            ),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.source", comment: "")
            textField.text = rule?.source
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.replacement", comment: "")
            textField.text = rule?.replacement
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let source = alert?.textFields?.first?.text
            else {
                return
            }
            let replacement = alert?.textFields?[safe: 1]?.text
            if let rule {
                self.updateRule(id: rule.id, source: source, replacement: replacement)
            } else {
                self.createRule(source: source, replacement: replacement)
            }
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

    private func updateRule(id: UUID, source: String, replacement: String?) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let rule = try await repository.updateFilterRule(
                    id: id,
                    source: source,
                    replacement: replacement
                )
                await MainActor.run {
                    guard let index = self.rules.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    self.rules[index] = rule
                    self.tableView.reloadRows(
                        at: [IndexPath(row: index, section: 0)],
                        with: .automatic
                    )
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
        configureCloseButtonIfNeeded()
        configureViews()
        updateFooter()
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

@MainActor
final class ReaderPageTouchAreasViewController: UIViewController {
    private var settings: ReaderSettings
    private let onSave: (ReaderSettings) -> Void
    private var buttons: [UIButton] = []
    private var didSaveSettings = false

    init(
        settings: ReaderSettings,
        onSave: @escaping (ReaderSettings) -> Void
    ) {
        self.settings = settings.normalized
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        edgesForExtendedLayout = [.top, .bottom]
        extendedLayoutIncludesOpaqueBars = true
        configureGrid()
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }

        if let transitionCoordinator,
           transitionCoordinator.isInteractive {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else {
                    return
                }
                self?.saveSettingsIfNeeded()
            }
            return
        }

        saveSettingsIfNeeded()
    }

    private func configureGrid() {
        buttons = []

        let rows = (0..<3).map { rowIndex in
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill
            rowStack.spacing = 0

            for columnIndex in 0..<3 {
                let index = rowIndex * 3 + columnIndex
                rowStack.addArrangedSubview(cellButton(at: index))
            }

            return rowStack
        }

        let gridStack = UIStackView(arrangedSubviews: rows)
        gridStack.axis = .vertical
        gridStack.distribution = .fillEqually
        gridStack.alignment = .fill
        gridStack.spacing = 0
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridStack)

        NSLayoutConstraint.activate([
            gridStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridStack.topAnchor.constraint(equalTo: view.topAnchor),
            gridStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func cellButton(at index: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = index
        button.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(touchAreaButtonTapped(_:)), for: .touchUpInside)
        buttons.append(button)
        update(button, at: index)

        if index == 3 {
            addEdgeHint(to: button)
        }

        return button
    }

    private func addEdgeHint(to container: UIView) {
        let hintLabel = UILabel()
        hintLabel.text = NSLocalizedString("reader.touchAreas.edgeBackHint", comment: "")
            .map(String.init)
            .joined(separator: "\n")
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        hintLabel.font = .preferredFont(forTextStyle: .caption2)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isUserInteractionEnabled = false
        container.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            hintLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hintLabel.widthAnchor.constraint(equalToConstant: 18),
            hintLabel.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.7)
        ])
    }

    private func update(
        _ button: UIButton,
        at index: Int
    ) {
        let action = settings.touchAreaMap[index]
        button.backgroundColor = action.touchAreaColor
        button.setTitle(action.localizedTitle, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.72), for: .highlighted)
    }

    @objc private func touchAreaButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard settings.touchAreaMap.indices.contains(index) else {
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("reader.touchAreas.bindTitle", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        let isOnlyMenuArea = settings.touchAreaMap[index] == .menu
            && settings.touchAreaMap.filter { $0 == .menu }.count == 1
        for action in ReaderSettings.TouchAreaAction.allCases {
            let item = UIAlertAction(title: action.localizedTitle, style: .default) { [weak self] _ in
                guard let self else {
                    return
                }
                self.settings.touchAreaMap[index] = action
                self.update(sender, at: index)
            }
            item.isEnabled = !(isOnlyMenuArea && action != .menu)
            alert.addAction(item)
        }
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("reader.touchAreas.saveAndExit", comment: ""),
                style: .destructive
            ) { [weak self] _ in
                self?.saveAndExit()
            }
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.popoverPresentationController?.sourceView = sender
        alert.popoverPresentationController?.sourceRect = sender.bounds
        present(alert, animated: true)
    }

    private func saveAndExit() {
        saveSettingsIfNeeded()
        readerPopOrDismiss(animated: true)
    }

    private func saveSettingsIfNeeded() {
        guard !didSaveSettings else {
            return
        }

        didSaveSettings = true
        onSave(settings.normalized)
    }
}

private extension ReaderSettings.TouchAreaAction {
    var localizedTitle: String {
        switch self {
        case .previousPage:
            return NSLocalizedString("reader.touchAreas.previousPage", comment: "")
        case .menu:
            return NSLocalizedString("reader.touchAreas.menu", comment: "")
        case .nextPage:
            return NSLocalizedString("reader.touchAreas.nextPage", comment: "")
        case .none:
            return NSLocalizedString("reader.touchAreas.none", comment: "")
        }
    }

    var touchAreaColor: UIColor {
        switch self {
        case .previousPage:
            return UIColor(red: 0.29, green: 0.33, blue: 0.58, alpha: 1)
        case .menu:
            return UIColor(red: 0.70, green: 0.48, blue: 0.30, alpha: 1)
        case .nextPage:
            return UIColor(red: 0.36, green: 0.54, blue: 0.24, alpha: 1)
        case .none:
            return UIColor(red: 0.31, green: 0.31, blue: 0.33, alpha: 1)
        }
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
