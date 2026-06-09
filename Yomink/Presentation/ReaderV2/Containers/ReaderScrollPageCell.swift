import UIKit

@MainActor
final class ReaderScrollPageCell: UITableViewCell {
    static let reuseIdentifier = "ReaderScrollPageCell"

    private let backgroundPageView = ReaderPageBackgroundView(frame: .zero)
    private let textView = TextReadView(frame: .zero)
    private(set) var pageModel: ReaderPageModel?
    var onTextSelectionAction: ((ReaderTextSelectionAction, String) -> Void)? {
        didSet {
            textView.onSelectionAction = onTextSelectionAction
        }
    }
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var textLeadingConstraint: NSLayoutConstraint?
    private var textTrailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        backgroundPageView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundPageView)
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
            backgroundPageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundPageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundPageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            backgroundPageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

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
        textView.setSelectedRange(nil)
        textView.onSelectionAction = onTextSelectionAction
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
        textLeadingConstraint?.constant = layout.leftMargin
        textTrailingConstraint?.constant = -layout.rightMargin
        backgroundPageView.apply(theme: theme)
        textView.layout = layout
        textView.contentColor = theme.contentColor
        textView.contentRectOverride = textView.bounds
        textView.onSelectionAction = onTextSelectionAction
        textView.setAttributedText(attributedText)
        setNeedsLayout()
    }
}
