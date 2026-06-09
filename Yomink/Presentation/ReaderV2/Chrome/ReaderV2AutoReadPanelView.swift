import UIKit

@MainActor
final class ReaderV2AutoReadPanelView: UIView {
    let speedSlider = UISlider()
    let exitButton = UIButton(type: .system)

    private let stackView = UIStackView()
    private(set) var isPanelVisible = false

    var onSpeedChange: ((Double) -> Void)?
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
        let normalized = min(
            max(speed, ReaderSettings.minimumAutoReadSpeed),
            ReaderSettings.maximumAutoReadSpeed
        )
        speedSlider.value = Float(normalized)
        speedSlider.accessibilityValue = "\(Int(normalized.rounded()))"
    }

    func apply(chromeTheme _: ReaderChromeTheme) {
        backgroundColor = MenuStyle.barBackgroundColor
        speedSlider.minimumTrackTintColor = MenuStyle.progressTintColor
        speedSlider.maximumTrackTintColor = MenuStyle.progressTrackColor
        speedSlider.thumbTintColor = MenuStyle.progressThumbColor
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
        speedSlider.minimumTrackTintColor = MenuStyle.progressTintColor
        speedSlider.maximumTrackTintColor = MenuStyle.progressTrackColor
        speedSlider.thumbTintColor = MenuStyle.progressThumbColor
        speedSlider.setThumbImage(makeSliderThumbImage(diameter: 24), for: .normal)
        speedSlider.setThumbImage(makeSliderThumbImage(diameter: 28), for: .highlighted)
        speedSlider.accessibilityLabel = NSLocalizedString("reader.autoRead.speed", comment: "")
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
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

    private func makeSliderThumbImage(diameter: CGFloat) -> UIImage {
        let shadowPadding: CGFloat = 4
        let size = CGSize(
            width: diameter + shadowPadding * 2,
            height: diameter + shadowPadding * 2
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(
                x: shadowPadding,
                y: shadowPadding,
                width: diameter,
                height: diameter
            )
            let cgContext = context.cgContext
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.36).cgColor
            )

            UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1).setFill()
            cgContext.fillEllipse(in: bounds)
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            MenuStyle.progressThumbColor.setFill()
            cgContext.fillEllipse(in: bounds.insetBy(dx: 3, dy: 3))

            UIColor(white: 0.64, alpha: 0.36).setFill()
            cgContext.fillEllipse(
                in: CGRect(
                    x: bounds.minX + diameter * 0.31,
                    y: bounds.minY + diameter * 0.24,
                    width: diameter * 0.38,
                    height: diameter * 0.18
                )
            )

            UIColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1).setStroke()
            cgContext.setLineWidth(1)
            cgContext.strokeEllipse(in: bounds.insetBy(dx: 0.5, dy: 0.5))
        }
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
        onSpeedChange?(speed)
    }

    @objc private func exitTapped() {
        onExit?()
    }
}

private extension ReaderV2AutoReadPanelView {
    enum Layout {
        static let autoReadPanelHeight: CGFloat = 190
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
        static let progressTintColor = UIColor(red: 0.68, green: 0.17, blue: 0.14, alpha: 1)
        static let progressTrackColor = UIColor(red: 0.26, green: 0.26, blue: 0.26, alpha: 1)
        static let progressThumbColor = UIColor(red: 0.353, green: 0.353, blue: 0.365, alpha: 1)
        static let settingsControlBackgroundColor = UIColor(red: 0.216, green: 0.216, blue: 0.216, alpha: 1)
    }
}
