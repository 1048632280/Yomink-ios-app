import UIKit

@MainActor
final class ReaderScrollPageCell: UITableViewCell {
    static let reuseIdentifier = "ReaderScrollPageCell"

    private let backgroundPageView = ReaderPageBackgroundView(frame: .zero)
    private let textView = TextReadView(frame: .zero)
    private(set) var pageModel: ReaderPageModel?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        backgroundPageView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundPageView)
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            backgroundPageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundPageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundPageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundPageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pageModel = nil
        textView.setAttributedText(NSAttributedString(string: ""))
        textView.setHighlightedRanges([])
        textView.setSelectedRange(nil)
    }

    func configure(
        attributedText: NSAttributedString,
        pageModel: ReaderPageModel,
        layout: ReaderLayout,
        theme: ReaderTheme
    ) {
        self.pageModel = pageModel
        backgroundPageView.apply(theme: theme)
        textView.layout = layout
        textView.contentColor = theme.contentColor
        textView.setAttributedText(attributedText)
    }
}
