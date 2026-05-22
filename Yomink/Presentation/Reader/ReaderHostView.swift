import SwiftUI
import UIKit

struct ReaderHostView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ReaderViewController {
        ReaderViewController()
    }

    func updateUIViewController(
        _ uiViewController: ReaderViewController,
        context: Context
    ) {
    }
}

final class ReaderViewController: UIViewController {
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureTitleLabel()
        configureBodyLabel()
        configureLayout()
    }

    private func configureTitleLabel() {
        titleLabel.text = NSLocalizedString("reader.placeholder.title", comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureBodyLabel() {
        bodyLabel.text = NSLocalizedString("reader.placeholder.message", comment: "")
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
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
}
