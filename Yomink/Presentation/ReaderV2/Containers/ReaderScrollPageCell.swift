import UIKit

@MainActor
final class ReaderScrollPageCell: UITableViewCell {
    static let reuseIdentifier = "ReaderScrollPageCell"

    private let backgroundPageView = ReaderPageBackgroundView(frame: .zero)
    private let textView = TextReadView(frame: .zero)
    private let chapterTitleLabel = UILabel()
    private let bottomWidgetView = ReaderBottomWidgetView()
    private(set) var pageModel: ReaderPageModel?
    var onTextSelectionAction: ((ReaderTextSelectionAction, String) -> Void)? {
        didSet {
            textView.onSelectionAction = onTextSelectionAction
        }
    }
    private var layout = ReaderLayout.notchedPhone
    private var theme = ReaderTheme.standard
    private var chapterTitle = ""
    private var bookTitle = ""
    private var fullProgress: Double = 0
    private var widgetVisibility = ReaderSettings.WidgetVisibility.default

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        backgroundPageView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundPageView)
        contentView.addSubview(textView)
        configureWidgets()
        contentView.addSubview(chapterTitleLabel)
        contentView.addSubview(bottomWidgetView)
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
        chapterTitle = ""
        bookTitle = ""
        fullProgress = 0
        textView.setAttributedText(NSAttributedString(string: ""))
        textView.setHighlightedRanges([])
        textView.setSelectedRange(nil)
        textView.onSelectionAction = onTextSelectionAction
        chapterTitleLabel.text = nil
        bottomWidgetView.updateContent(
            chapterTitle: "",
            pageIndex: 0,
            pageCount: 1,
            fullProgress: 0
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chapterTitleLabel.frame = ReaderPageWidgetLayout.titleFrame(
            screenSize: contentView.bounds.size,
            layout: layout
        )
        bottomWidgetView.frame = ReaderPageWidgetLayout.bottomFrame(
            screenSize: contentView.bounds.size,
            layout: layout
        )
        bottomWidgetView.updateWidgetLayout(
            screenSize: bottomWidgetView.bounds.size,
            layoutConfig: layout
        )
    }

    func configure(
        attributedText: NSAttributedString,
        pageModel: ReaderPageModel,
        layout: ReaderLayout,
        theme: ReaderTheme,
        chapterTitle: String = "",
        bookTitle: String = "",
        fullProgress: Double = 0,
        widgetVisibility: ReaderSettings.WidgetVisibility = .default
    ) {
        self.pageModel = pageModel
        self.layout = layout
        self.theme = theme
        self.chapterTitle = chapterTitle
        self.bookTitle = bookTitle
        self.fullProgress = ReaderPageModel.clampedProgress(fullProgress)
        self.widgetVisibility = widgetVisibility
        backgroundPageView.apply(theme: theme)
        textView.layout = layout
        textView.contentColor = theme.contentColor
        textView.onSelectionAction = onTextSelectionAction
        textView.setAttributedText(attributedText)
        applyWidgets()
    }

    private func configureWidgets() {
        chapterTitleLabel.backgroundColor = .clear
        chapterTitleLabel.textAlignment = .left
        chapterTitleLabel.font = ReaderPageWidgetLayout.font
        chapterTitleLabel.numberOfLines = 1
        chapterTitleLabel.lineBreakMode = .byTruncatingTail
        chapterTitleLabel.isUserInteractionEnabled = false
        bottomWidgetView.isUserInteractionEnabled = false
    }

    private func applyWidgets() {
        chapterTitleLabel.textColor = theme.headerColor
        chapterTitleLabel.font = ReaderPageWidgetLayout.font
        chapterTitleLabel.text = ReaderPageWidgetLayout.headerTitle(
            bookTitle: bookTitle,
            chapterTitle: chapterTitle,
            pageIndex: pageModel?.pageIndex ?? 0
        )
        chapterTitleLabel.isHidden = !widgetVisibility.chapterTitle
        bottomWidgetView.updateTheme(headerColor: theme.headerColor)
        bottomWidgetView.updateFont(ReaderPageWidgetLayout.font)
        bottomWidgetView.updateSettings(
            showTime: widgetVisibility.time,
            showBatteryView: widgetVisibility.batteryIcon,
            showBatteryLabel: widgetVisibility.batteryPercentage,
            showChapterTitle: widgetVisibility.chapterTitle,
            showPageProgress: widgetVisibility.chapterPageProgress,
            showFullProgress: widgetVisibility.globalProgress
        )
        bottomWidgetView.updateContent(
            chapterTitle: chapterTitle,
            pageIndex: pageModel?.pageIndex ?? 0,
            pageCount: pageModel?.pageCount ?? 1,
            fullProgress: fullProgress
        )
        setNeedsLayout()
    }
}
