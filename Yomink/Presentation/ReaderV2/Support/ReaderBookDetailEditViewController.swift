import SwiftUI
import UIKit

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
        navigationItem.backButtonTitle = NSLocalizedString("common.back", comment: "")
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
        let navigationActions = BookTagPickerNavigationActions()
        let picker = ReaderBookTagPickerHostView(
            repository: repository,
            initialSelectedTagIDs: selectedTagIDs,
            navigationActions: navigationActions,
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
        let hostingController = ReaderBookTagPickerHostingController(
            rootView: picker,
            navigationActions: navigationActions
        )
        hostingController.title = NSLocalizedString("tags.select.title", comment: "")
        hostingController.navigationItem.backButtonTitle = NSLocalizedString("common.back", comment: "")
        hostingController.navigationItem.largeTitleDisplayMode = .never
        hostingController.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.new", comment: ""),
            style: .plain,
            target: navigationActions,
            action: #selector(BookTagPickerNavigationActions.createTagButtonTapped)
        )
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
    let navigationActions: BookTagPickerNavigationActions
    let onSelectionChanged: (Set<UUID>) -> Void
    let onCatalogChanged: () -> Void

    @State private var selectedTagIDs: Set<UUID>

    init(
        repository: any LibraryRepository,
        initialSelectedTagIDs: Set<UUID>,
        navigationActions: BookTagPickerNavigationActions,
        onSelectionChanged: @escaping (Set<UUID>) -> Void,
        onCatalogChanged: @escaping () -> Void
    ) {
        self.repository = repository
        self.navigationActions = navigationActions
        self.onSelectionChanged = onSelectionChanged
        self.onCatalogChanged = onCatalogChanged
        _selectedTagIDs = State(initialValue: initialSelectedTagIDs)
    }

    var body: some View {
        BookTagPickerPage(
            repository: repository,
            selectedTagIDs: $selectedTagIDs,
            onCatalogChanged: onCatalogChanged,
            navigationChrome: .system,
            navigationActions: navigationActions
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
private final class ReaderBookTagPickerHostingController<Content: View>: UIHostingController<Content> {
    private let navigationActions: BookTagPickerNavigationActions

    init(rootView: Content, navigationActions: BookTagPickerNavigationActions) {
        self.navigationActions = navigationActions
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
