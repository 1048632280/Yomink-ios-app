import SwiftUI
import UIKit

struct ReaderHostView: UIViewControllerRepresentable {
    var book: Book?

    init(book: Book? = nil) {
        self.book = book
    }

    func makeUIViewController(context: Context) -> ReaderViewController {
        ReaderViewController(book: book)
    }

    func updateUIViewController(
        _ uiViewController: ReaderViewController,
        context: Context
    ) {
        uiViewController.update(book: book)
    }
}

final class ReaderViewController: UIViewController {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private var book: Book?

    init(book: Book?) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureTitleLabel()
        configureBodyLabel()
        configureLayout()
    }

    func update(book: Book?) {
        self.book = book
        updateContent()
    }

    private func configureTitleLabel() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureBodyLabel() {
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        updateContent()
    }

    private func configureLayout() {
        view.addSubview(titleLabel)
        view.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -36),

            bodyLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16)
        ])
    }

    private func updateContent() {
        if let book {
            titleLabel.text = book.title
            bodyLabel.text = String(
                format: NSLocalizedString("reader.book.placeholder.message", comment: ""),
                book.normalizedPath ?? book.sourcePath
            )
        } else {
            titleLabel.text = NSLocalizedString("reader.placeholder.title", comment: "")
            bodyLabel.text = NSLocalizedString("reader.placeholder.message", comment: "")
        }
    }
}
