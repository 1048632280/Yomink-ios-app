import UIKit

@MainActor
final class ReaderV2AutoReadPanelView: UIView {
    let speedSlider = UISlider()
    let exitButton = UIButton(type: .system)

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
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

    func setSpeed(_ speed: Double) {
        let normalized = min(
            max(speed, ReaderSettings.minimumAutoReadSpeed),
            ReaderSettings.maximumAutoReadSpeed
        )
        speedSlider.value = Float(normalized)
        valueLabel.text = "\(Int(normalized))"
    }

    func apply(chromeTheme: ReaderChromeTheme) {
        backgroundColor = chromeTheme.panelBackgroundColor
        layer.borderColor = chromeTheme.separatorColor.cgColor
        titleLabel.textColor = chromeTheme.primaryTextColor
        valueLabel.textColor = chromeTheme.secondaryTextColor
        speedSlider.minimumTrackTintColor = chromeTheme.controlTintColor
        speedSlider.maximumTrackTintColor = chromeTheme.separatorColor
        speedSlider.thumbTintColor = chromeTheme.controlTintColor
        exitButton.tintColor = chromeTheme.primaryTextColor
        exitButton.backgroundColor = chromeTheme.separatorColor.withAlphaComponent(0.48)
    }

    func setPanelVisible(
        _ visible: Bool,
        animated: Bool
    ) {
        isPanelVisible = visible
        let changes = {
            self.alpha = visible ? 1 : 0
            self.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: 18)
        }
        isHidden = false
        isUserInteractionEnabled = visible
        if animated {
            UIView.animate(
                withDuration: 0.2,
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

    private func configureViews() {
        layer.cornerRadius = 8
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        layer.borderWidth = 1 / UIScreen.main.scale

        titleLabel.text = NSLocalizedString("reader.autoRead.speed", comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true

        valueLabel.font = .preferredFont(forTextStyle: .body)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textAlignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        speedSlider.minimumValue = Float(ReaderSettings.minimumAutoReadSpeed)
        speedSlider.maximumValue = Float(ReaderSettings.maximumAutoReadSpeed)
        speedSlider.accessibilityLabel = NSLocalizedString("reader.autoRead.speed", comment: "")
        speedSlider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)

        exitButton.setTitle(NSLocalizedString("reader.autoRead.exit", comment: ""), for: .normal)
        exitButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        exitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        exitButton.layer.cornerRadius = 8
        exitButton.layer.masksToBounds = true
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 12

        let speedStack = UIStackView(arrangedSubviews: [
            iconView(systemName: "tortoise.fill", fallbackName: "tortoise"),
            speedSlider,
            iconView(systemName: "hare.fill", fallbackName: "hare")
        ])
        speedStack.axis = .horizontal
        speedStack.alignment = .center
        speedStack.spacing = 12

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(headerStack)
        stackView.addArrangedSubview(speedStack)
        stackView.addArrangedSubview(exitButton)
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            exitButton.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func iconView(
        systemName: String,
        fallbackName: String
    ) -> UIImageView {
        let imageView = UIImageView(image: UIImage(systemName: systemName) ?? UIImage(systemName: fallbackName))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        return imageView
    }

    @objc private func speedChanged() {
        let speed = Double(speedSlider.value)
        valueLabel.text = "\(Int(speed.rounded()))"
        onSpeedChange?(speed)
    }

    @objc private func exitTapped() {
        onExit?()
    }
}
