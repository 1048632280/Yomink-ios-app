import SwiftUI
import UIKit

final class ReaderBookCoverView: UIView {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 5
        backgroundColor = .systemGray5
        titleLabel.textColor = UIColor.darkGray.withAlphaComponent(0.62)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, fontSize: CGFloat) {
        titleLabel.text = title.firstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
        titleLabel.font = .systemFont(ofSize: fontSize, weight: .semibold)
    }
}


private extension String {
    var firstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
    }
}
