import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

final class ReaderProgressSlider: UISlider {
    private let minimumHitSize = CGSize(width: 44, height: 44)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalInset = min((bounds.width - minimumHitSize.width) / 2, 0)
        let verticalInset = min((bounds.height - minimumHitSize.height) / 2, 0)
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset).contains(point)
    }
}

struct ReaderWidgetLayoutConfiguration {
    var horizontalMargin: CGFloat
    var bottomMargin: CGFloat
    var titleTopMargin: CGFloat
    var titleLeftMargin: CGFloat
}

struct ReaderPageWidgetSnapshot {
    var chapterTitle: String
    var batteryLevel: Float
    var batteryState: UIDevice.BatteryState
    var timeText: String
    var pageProgressText: String
    var globalProgressText: String
}

final class ReaderPageWidgetOverlayView: UIView {
    private let titleLabel = UILabel()
    private let bottomLeftStack = UIStackView()
    private let batteryPercentageLabel = UILabel()
    private let batteryIconView = ReaderBatteryIconView()
    private let timeLabel = UILabel()
    private let bottomRightStack = UIStackView()
    private let pageProgressLabel = UILabel()
    private let globalProgressLabel = UILabel()

    private var titleTopConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var bottomLeftLeadingConstraint: NSLayoutConstraint?
    private var bottomLeftBottomConstraint: NSLayoutConstraint?
    private var bottomRightTrailingConstraint: NSLayoutConstraint?
    private var bottomRightBottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        snapshot: ReaderPageWidgetSnapshot,
        settings: ReaderSettings,
        layout: ReaderWidgetLayoutConfiguration
    ) {
        let visibility = settings.widgetVisibility
        let textColor = settings.theme.secondaryTextColor
        let secondaryColor = textColor.withAlphaComponent(0.78)
        titleLabel.text = snapshot.chapterTitle
        titleLabel.textColor = secondaryColor
        batteryPercentageLabel.text = batteryText(for: snapshot.batteryLevel)
        batteryPercentageLabel.textColor = textColor
        timeLabel.text = snapshot.timeText
        timeLabel.textColor = textColor
        pageProgressLabel.text = snapshot.pageProgressText
        pageProgressLabel.textColor = textColor
        globalProgressLabel.text = snapshot.globalProgressText
        globalProgressLabel.textColor = textColor
        batteryIconView.configure(
            level: snapshot.batteryLevel,
            state: snapshot.batteryState,
            strokeColor: textColor
        )

        titleLabel.isHidden = !visibility.chapterTitle
        batteryPercentageLabel.isHidden = !visibility.batteryPercentage
        batteryIconView.isHidden = !visibility.batteryIcon
        timeLabel.isHidden = !visibility.time
        pageProgressLabel.isHidden = !visibility.chapterPageProgress
        globalProgressLabel.isHidden = !visibility.globalProgress
        bottomLeftStack.isHidden = !visibility.batteryPercentage
            && !visibility.batteryIcon
            && !visibility.time
        bottomRightStack.isHidden = !visibility.chapterPageProgress
            && !visibility.globalProgress

        titleTopConstraint?.constant = layout.titleTopMargin
        titleLeadingConstraint?.constant = layout.titleLeftMargin
        bottomLeftLeadingConstraint?.constant = layout.horizontalMargin
        bottomLeftBottomConstraint?.constant = -layout.bottomMargin
        bottomRightTrailingConstraint?.constant = -layout.horizontalMargin
        bottomRightBottomConstraint?.constant = -layout.bottomMargin
    }

    private func configureViews() {
        backgroundColor = .clear

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        [batteryPercentageLabel, timeLabel, pageProgressLabel, globalProgressLabel].forEach { label in
            label.font = .preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 1
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        bottomLeftStack.axis = .horizontal
        bottomLeftStack.alignment = .center
        bottomLeftStack.spacing = 6
        bottomLeftStack.translatesAutoresizingMaskIntoConstraints = false
        bottomLeftStack.addArrangedSubview(batteryPercentageLabel)
        bottomLeftStack.addArrangedSubview(batteryIconView)
        bottomLeftStack.addArrangedSubview(timeLabel)
        addSubview(bottomLeftStack)

        bottomRightStack.axis = .horizontal
        bottomRightStack.alignment = .center
        bottomRightStack.spacing = 8
        bottomRightStack.translatesAutoresizingMaskIntoConstraints = false
        bottomRightStack.addArrangedSubview(pageProgressLabel)
        bottomRightStack.addArrangedSubview(globalProgressLabel)
        addSubview(bottomRightStack)

        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        bottomLeftLeadingConstraint = bottomLeftStack.leadingAnchor.constraint(equalTo: leadingAnchor)
        bottomLeftBottomConstraint = bottomLeftStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomRightTrailingConstraint = bottomRightStack.trailingAnchor.constraint(equalTo: trailingAnchor)
        bottomRightBottomConstraint = bottomRightStack.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            titleTopConstraint,
            titleLeadingConstraint,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),

            bottomLeftLeadingConstraint,
            bottomLeftBottomConstraint,
            bottomLeftStack.trailingAnchor.constraint(lessThanOrEqualTo: bottomRightStack.leadingAnchor, constant: -12),

            bottomRightTrailingConstraint,
            bottomRightBottomConstraint,
            batteryIconView.widthAnchor.constraint(equalToConstant: 24),
            batteryIconView.heightAnchor.constraint(equalToConstant: 12)
        ].compactMap { $0 })
    }

    private func batteryText(for level: Float) -> String {
        guard level >= 0 else {
            return "--%"
        }
        return "\(Int((level * 100).rounded()))%"
    }
}

private final class ReaderBatteryIconView: UIView {
    private var level: Float = -1
    private var batteryState: UIDevice.BatteryState = .unknown
    private var strokeColor: UIColor = .secondaryLabel

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        level: Float,
        state: UIDevice.BatteryState,
        strokeColor: UIColor
    ) {
        self.level = level
        self.batteryState = state
        self.strokeColor = strokeColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let capWidth: CGFloat = 2.2
        let bodyRect = CGRect(
            x: 0.75,
            y: 1.5,
            width: bounds.width - capWidth - 2.25,
            height: bounds.height - 3
        )
        let capRect = CGRect(
            x: bodyRect.maxX + 1,
            y: bounds.midY - 2,
            width: capWidth,
            height: 4
        )

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(1)
        UIBezierPath(roundedRect: bodyRect, cornerRadius: 2).stroke()
        context.setFillColor(strokeColor.cgColor)
        UIBezierPath(roundedRect: capRect, cornerRadius: 1).fill()

        let clampedLevel = level < 0 ? 1 : CGFloat(max(min(level, 1), 0))
        let fillInset: CGFloat = 2
        let fillWidth = max(0, (bodyRect.width - fillInset * 2) * clampedLevel)
        let fillRect = CGRect(
            x: bodyRect.minX + fillInset,
            y: bodyRect.minY + fillInset,
            width: fillWidth,
            height: max(0, bodyRect.height - fillInset * 2)
        )
        guard fillRect.width > 0 else {
            return
        }
        let fillColor: UIColor = batteryState == .charging || batteryState == .full
            ? .systemGreen
            : .black
        context.setFillColor(fillColor.cgColor)
        UIBezierPath(roundedRect: fillRect, cornerRadius: 1).fill()
    }
}
