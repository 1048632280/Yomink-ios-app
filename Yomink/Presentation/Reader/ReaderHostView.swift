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
        titleLabel.text = "阅读器核心容器"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureBodyLabel() {
        bodyLabel.text = """
        UIKit 阅读器占位页已接入。

        Phase 2 会在这里实现高性能文本渲染、分页、手势热区和阅读进度恢复。
        """
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

