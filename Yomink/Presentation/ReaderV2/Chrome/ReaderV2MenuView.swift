import UIKit

@MainActor
final class ReaderV2MenuView: UIView {
    let closeButton = UIButton(type: .system)
    let settingsButton = UIButton(type: .system)
    let previousPageButton = UIButton(type: .system)
    let nextPageButton = UIButton(type: .system)

    private let topBar = UIView()
    private let bottomBar = UIView()
    private let topSeparator = UIView()
    private let bottomSeparator = UIView()
    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let modeLabel = UILabel()

    private(set) var isMenuVisible = false

    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onPreviousPage: (() -> Void)?
    var onNextPage: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        setMenuVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(bookTitle: String) {
        titleLabel.text = bookTitle
    }

    func update(
        pageModel: ReaderPageModel?,
        chapterTitle: String,
        turnPageType: ReaderTurnPageType
    ) {
        modeLabel.text = turnPageType.readerV2Title
        guard let pageModel else {
            progressLabel.text = chapterTitle
            return
        }
        let pageText = "\(pageModel.pageIndex + 1)/\(max(pageModel.pageCount, 1))"
        progressLabel.text = chapterTitle.isEmpty ? pageText : "\(chapterTitle)  \(pageText)"
    }

    func apply(chromeTheme: ReaderChromeTheme) {
        topBar.backgroundColor = chromeTheme.barBackgroundColor
        bottomBar.backgroundColor = chromeTheme.barBackgroundColor
        topSeparator.backgroundColor = chromeTheme.separatorColor
        bottomSeparator.backgroundColor = chromeTheme.separatorColor
        titleLabel.textColor = chromeTheme.primaryTextColor
        progressLabel.textColor = chromeTheme.secondaryTextColor
        modeLabel.textColor = chromeTheme.secondaryTextColor
        [
            closeButton,
            settingsButton,
            previousPageButton,
            nextPageButton
        ].forEach { button in
            button.tintColor = chromeTheme.primaryTextColor
        }
    }

    func setMenuVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        isMenuVisible = visible
        let changes = {
            self.alpha = visible ? 1 : 0
        }
        isHidden = false
        isUserInteractionEnabled = visible
        if animated {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: changes
            ) { _ in
                self.isHidden = !visible
            }
        } else {
            changes()
            isHidden = !visible
        }
    }

    func containsInteractiveContent(at point: CGPoint) -> Bool {
        topBar.frame.contains(point) || bottomBar.frame.contains(point)
    }

    private func configureViews() {
        backgroundColor = .clear

        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBar)
        addSubview(bottomBar)
        topBar.addSubview(topSeparator)
        bottomBar.addSubview(bottomSeparator)

        configureLabels()
        configureButtons()

        let topStack = UIStackView(arrangedSubviews: [
            closeButton,
            titleLabel,
            settingsButton
        ])
        topStack.axis = .horizontal
        topStack.alignment = .center
        topStack.spacing = 12
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(topStack)

        let bottomStack = UIStackView(arrangedSubviews: [
            previousPageButton,
            progressLabel,
            modeLabel,
            nextPageButton
        ])
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(bottomStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            topStack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            topStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            topStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            topStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),

            topSeparator.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            topSeparator.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),

            bottomStack.topAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 10),
            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
            bottomStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),

            bottomSeparator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            bottomSeparator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),
            bottomSeparator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            bottomSeparator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            closeButton.widthAnchor.constraint(equalToConstant: 38),
            closeButton.heightAnchor.constraint(equalToConstant: 38),
            settingsButton.widthAnchor.constraint(equalToConstant: 38),
            settingsButton.heightAnchor.constraint(equalToConstant: 38),
            previousPageButton.widthAnchor.constraint(equalToConstant: 42),
            previousPageButton.heightAnchor.constraint(equalToConstant: 38),
            nextPageButton.widthAnchor.constraint(equalToConstant: 42),
            nextPageButton.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    private func configureLabels() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.numberOfLines = 1
        progressLabel.lineBreakMode = .byTruncatingMiddle

        modeLabel.font = .preferredFont(forTextStyle: .caption1)
        modeLabel.adjustsFontForContentSizeCategory = true
        modeLabel.numberOfLines = 1
        modeLabel.textAlignment = .right
        modeLabel.setContentHuggingPriority(.required, for: .horizontal)
        modeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureButtons() {
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("common.close", comment: "")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        settingsButton.setImage(UIImage(systemName: "textformat.size"), for: .normal)
        settingsButton.accessibilityLabel = NSLocalizedString("reader.settings", comment: "")
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)

        previousPageButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        previousPageButton.accessibilityLabel = NSLocalizedString("reader.previousPage", comment: "")
        previousPageButton.addTarget(self, action: #selector(previousPageTapped), for: .touchUpInside)

        nextPageButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        nextPageButton.accessibilityLabel = NSLocalizedString("reader.nextPage", comment: "")
        nextPageButton.addTarget(self, action: #selector(nextPageTapped), for: .touchUpInside)
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func settingsTapped() {
        onSettings?()
    }

    @objc private func previousPageTapped() {
        onPreviousPage?()
    }

    @objc private func nextPageTapped() {
        onNextPage?()
    }
}

private extension ReaderTurnPageType {
    var readerV2Title: String {
        switch self {
        case .horizontalScroll:
            return NSLocalizedString("reader.settings.pageTurn.slide", comment: "")
        case .pageCurl:
            return NSLocalizedString("reader.settings.pageTurn.curl", comment: "")
        case .verticalContinuous:
            return NSLocalizedString("reader.settings.pageTurn.scroll", comment: "")
        }
    }
}
