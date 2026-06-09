import UIKit

final class ReaderPageViewController: UIViewController {
    private(set) var backgroundView = ReaderPageBackgroundView()
    private(set) var textView = TextReadView()
    private var page: ReaderDivisionPage?
    private(set) var pageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundView)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

    func setHighlightedRanges(_ ranges: [NSRange]) {
        textView.setHighlightedRanges(ranges)
    }

    func setSelectedRange(_ range: NSRange?) {
        textView.setSelectedRange(range)
    }

    private func applyConfiguration() {
        backgroundView.apply(theme: theme)
        textView.layout = layout
        textView.contentColor = theme.contentColor
        if let page {
            textView.setAttributedText(page.attributedText)
        }
    }
}
