import UIKit

final class ReaderPageViewController: UIViewController {
    private let textView = TextReadView()
    private var page: ReaderDivisionPage?
    private(set) var pageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.backgroundColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        applyConfiguration()
    }

    func configure(
        page: ReaderDivisionPage,
        pageModel: ReaderPageModel,
        layout: ReaderLayout,
        theme: ReaderTheme
    ) {
        self.page = page
        self.pageModel = pageModel
        self.layout = layout
        self.theme = theme
        applyConfiguration()
    }

    private func applyConfiguration() {
        viewIfLoaded?.backgroundColor = theme.backgroundColor
        textView.layout = layout
        textView.contentColor = theme.contentColor
        if let page {
            textView.setAttributedText(page.attributedText)
        }
    }
}
