import UIKit

@MainActor
final class ReaderV2AutoReadPanelView: UIView {
    static let preferredContentHeight: CGFloat = 190

    let speedSlider = ReaderV2VoiceSlider()
    let exitButton = UIButton(type: .system)

    private let stackView = UIStackView()
    private(set) var isPanelVisible = false

    var onSpeedChangeFinished: ((Double) -> Void)?
    var onExit: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
        setSpeed(ReaderSettings.default.autoReadSpeed)
        setPanelVisible(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPanelPosition()
    }

    func setSpeed(_ speed: Double) {
        let normalized = ReaderSettings.normalizedAutoReadSpeed(speed)
        speedSlider.value = Float(normalized)
        speedSlider.accessibilityValue = "\(Int(normalized.rounded()))"
    }

    func apply(chromeTheme _: ReaderChromeTheme) {
        backgroundColor = MenuStyle.barBackgroundColor
        exitButton.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
        exitButton.setTitleColor(MenuStyle.secondaryTextColor, for: .highlighted)
        exitButton.backgroundColor = MenuStyle.settingsControlBackgroundColor
    }

    func setPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        isPanelVisible = visible
        isHidden = false
        isUserInteractionEnabled = visible
        layoutIfNeeded()

        let changes = {
            self.applyPanelPosition()
        }
        let completion: (Bool) -> Void = { _ in
            self.isHidden = !visible
        }

        if animated {
            UIView.animate(
                withDuration: 0.24,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut],
                animations: changes,
                completion: completion
            )
        } else {
            changes()
            completion(true)
        }
    }

    private func configureViews() {
        backgroundColor = MenuStyle.barBackgroundColor
        clipsToBounds = true

        speedSlider.minimumValue = Float(ReaderSettings.minimumAutoReadSpeed)
        speedSlider.maximumValue = Float(ReaderSettings.maximumAutoReadSpeed)
        speedSlider.accessibilityLabel = NSLocalizedString("reader.autoRead.speed", comment: "")
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        speedSlider.addTarget(
            self,
            action: #selector(speedChangeFinished),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        speedSlider.translatesAutoresizingMaskIntoConstraints = false

        exitButton.setTitle(NSLocalizedString("reader.autoRead.exit", comment: ""), for: .normal)
        exitButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        exitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        exitButton.layer.cornerRadius = Layout.autoReadExitButtonHeight / 2
        exitButton.layer.masksToBounds = true
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false

        let speedRow = UIStackView(arrangedSubviews: [
            autoReadIcon(named: "tortoise.fill", fallbackName: "tortoise"),
            speedSlider,
            autoReadIcon(named: "hare.fill", fallbackName: "hare")
        ])
        speedRow.axis = .horizontal
        speedRow.alignment = .center
        speedRow.spacing = 14

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 22
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(speedRow)
        stackView.addArrangedSubview(exitButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.autoReadPanelHorizontalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.autoReadPanelHorizontalInset),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.autoReadPanelTopInset),
            stackView.bottomAnchor.constraint(
                lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor,
                constant: -Layout.autoReadPanelBottomInset
            ),
            exitButton.heightAnchor.constraint(equalToConstant: Layout.autoReadExitButtonHeight)
        ])

        apply(chromeTheme: .standard)
    }

    private func autoReadIcon(
        named imageName: String,
        fallbackName: String
    ) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: imageName) ?? UIImage(systemName: fallbackName))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: Layout.autoReadIconSize,
            weight: .regular
        )
        imageView.tintColor = MenuStyle.secondaryTextColor
        imageView.contentMode = .scaleAspectFit
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Layout.autoReadIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Layout.autoReadIconSize)
        ])
        return imageView
    }

    private func applyPanelPosition() {
        let hiddenOffset = bounds.height + 1
        transform = isPanelVisible
            ? .identity
            : CGAffineTransform(translationX: 0, y: hiddenOffset)
    }

    @objc private func speedChanged() {
        let speed = Double(speedSlider.value)
        speedSlider.accessibilityValue = "\(Int(speed.rounded()))"
    }

    @objc private func exitTapped() {
        onExit?()
    }

    @objc private func speedChangeFinished() {
        onSpeedChangeFinished?(Double(speedSlider.value))
    }
}

private extension ReaderV2AutoReadPanelView {
    enum Layout {
        static let autoReadPanelHorizontalInset: CGFloat = 22
        static let autoReadPanelTopInset: CGFloat = 28
        static let autoReadPanelBottomInset: CGFloat = 18
        static let autoReadIconSize: CGFloat = 24
        static let autoReadExitButtonHeight: CGFloat = 42
    }

    enum MenuStyle {
        static let barBackgroundColor = UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
        static let primaryTextColor = UIColor(white: 0.82, alpha: 1)
        static let secondaryTextColor = UIColor(white: 0.58, alpha: 1)
        static let settingsControlBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
    }
}
