import UIKit

@MainActor
final class ReaderScrollPageCell: UITableViewCell {
    static let reuseIdentifier = "ReaderScrollPageCell"

    private let pageBackgroundView = ReaderPageBackgroundView(frame: .zero)
    private(set) var textView = TextReadView(frame: .zero)
    private(set) var pageModel: ReaderPageModel?
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var textLeadingConstraint: NSLayoutConstraint?
    private var textTrailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        isOpaque = false
        contentView.backgroundColor = .clear
        contentView.isOpaque = false

        pageBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageBackgroundView)
        contentView.addSubview(textView)
        let textLeadingConstraint = textView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: layout.leftMargin
        )
        let textTrailingConstraint = textView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -layout.rightMargin
        )
        self.textLeadingConstraint = textLeadingConstraint
        self.textTrailingConstraint = textTrailingConstraint

        NSLayoutConstraint.activate([
            pageBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textLeadingConstraint,
            textTrailingConstraint,
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
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.contentRectOverride = textView.bounds
    }

    func configure(
        attributedText: NSAttributedString,
        pageModel: ReaderPageModel,
        layout: ReaderLayout,
        theme: ReaderTheme,
        chapterTitle _: String = "",
        bookTitle _: String = "",
        fullProgress _: Double = 0,
        widgetVisibility _: ReaderSettings.WidgetVisibility = .default
    ) {
        self.pageModel = pageModel
        self.layout = layout
        self.theme = theme
        pageBackgroundView.apply(theme: theme)
        textLeadingConstraint?.constant = layout.leftMargin
        textTrailingConstraint?.constant = -layout.rightMargin
        textView.layout = layout
        textView.contentColor = theme.contentColor
        textView.contentRectOverride = textView.bounds
        textView.setAttributedText(attributedText)
        setNeedsLayout()
    }

    func apply(theme: ReaderTheme) {
        self.theme = theme
        pageBackgroundView.apply(theme: theme)
        textView.contentColor = theme.contentColor
    }
}
