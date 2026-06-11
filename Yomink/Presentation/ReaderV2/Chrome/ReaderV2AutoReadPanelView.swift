import UIKit

@MainActor
final class ReaderV2AutoReadPanelView: UIView {
    static let preferredContentHeight: CGFloat = 92

    let speedSlider = ReaderV2VoiceSlider()
    let exitButton = UIButton(type: .system)

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
        speedSlider.minimumValueImage = autoReadIcon(named: "tortoise.fill", fallbackName: "tortoise")
        speedSlider.maximumValueImage = autoReadIcon(named: "hare.fill", fallbackName: "hare")
        exitButton.setTitleColor(MenuStyle.primaryTextColor, for: .normal)
        exitButton.setTitleColor(MenuStyle.secondaryTextColor, for: .highlighted)
        exitButton.backgroundColor = .clear
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
        exitButton.titleLabel?.font = .systemFont(ofSize: Layout.exitButtonFontSize)
        exitButton.titleLabel?.adjustsFontForContentSizeCategory = false
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(speedSlider)
        addSubview(exitButton)

        NSLayoutConstraint.activate([
            speedSlider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.sliderHorizontalInset),
            speedSlider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.sliderHorizontalInset),
            speedSlider.topAnchor.constraint(equalTo: topAnchor, constant: Layout.sliderTop),
            speedSlider.heightAnchor.constraint(equalToConstant: Layout.sliderHeight),

            exitButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            exitButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            exitButton.topAnchor.constraint(equalTo: topAnchor, constant: Layout.exitButtonTop),
            exitButton.heightAnchor.constraint(equalToConstant: Layout.exitButtonHeight)
        ])

        apply(chromeTheme: .standard)
    }

    private func autoReadIcon(
        named imageName: String,
        fallbackName: String
    ) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: Layout.iconSize,
            weight: .regular
        )
        let image = UIImage(systemName: imageName, withConfiguration: configuration)
            ?? UIImage(systemName: fallbackName, withConfiguration: configuration)
        return image?.withTintColor(MenuStyle.secondaryTextColor, renderingMode: .alwaysOriginal)
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
        static let sliderHorizontalInset: CGFloat = 54
        static let sliderTop: CGFloat = 18
        static let sliderHeight: CGFloat = 32
        static let iconSize: CGFloat = 28
        static let exitButtonTop: CGFloat = 52
        static let exitButtonHeight: CGFloat = 40
        static let exitButtonFontSize: CGFloat = 16
    }

    enum MenuStyle {
        static let barBackgroundColor = UIColor.black.withAlphaComponent(0.86)
        static let primaryTextColor = UIColor(white: 0.82, alpha: 1)
        static let secondaryTextColor = UIColor(white: 0.58, alpha: 1)
    }
}
