import UIKit

final class ReaderPageBackgroundView: UIView {
    private let textureView = UIView()
    private let imageView = UIImageView()

    private(set) var currentTheme = ReaderTheme.standard
    private(set) var usesPatternImage = false
    private(set) var displayedImageName: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = true

        textureView.translatesAutoresizingMaskIntoConstraints = false
        textureView.isUserInteractionEnabled = false
        textureView.isOpaque = false

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = false
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill

        addSubview(textureView)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            textureView.topAnchor.constraint(equalTo: topAnchor),
            textureView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textureView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textureView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        apply(theme: currentTheme)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(theme: ReaderTheme) {
        currentTheme = theme
        backgroundColor = theme.backgroundColor
        isOpaque = true
        displayedImageName = theme.backgroundImageName

        guard let imageName = theme.backgroundImageName,
              let image = UIImage(named: imageName) else {
            clearImage()
            return
        }

        if theme.backgroundImageStyle == "2" {
            usesPatternImage = true
            textureView.backgroundColor = UIColor(patternImage: image)
            textureView.isHidden = false
            imageView.image = nil
            imageView.isHidden = true
        } else {
            usesPatternImage = false
            textureView.backgroundColor = .clear
            textureView.isHidden = true
            imageView.image = image
            imageView.isHidden = false
        }
    }

    private func clearImage() {
        usesPatternImage = false
        textureView.backgroundColor = .clear
        textureView.isHidden = true
        imageView.image = nil
        imageView.isHidden = true
    }
}
