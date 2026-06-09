import UIKit

@MainActor
class ReaderV2Slider: UISlider {
    private static let minimumTrackColor = UIColor(
        red: 0.7844,
        green: 0.145114,
        blue: 0.082362,
        alpha: 1
    )
    private static let maximumTrackColor = UIColor(white: 0.172568, alpha: 1)
    private static let minimumHitSize = CGSize(width: 44, height: 44)

    private let preferredTrackHeight: CGFloat

    init(trackHeight: CGFloat) {
        preferredTrackHeight = trackHeight
        super.init(frame: .zero)
        configureStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(
            x: 0,
            y: bounds.midY - preferredTrackHeight / 2,
            width: bounds.width,
            height: preferredTrackHeight
        )
    }

    override func thumbRect(
        forBounds bounds: CGRect,
        trackRect rect: CGRect,
        value: Float
    ) -> CGRect {
        let thumbSize = currentThumbImage?.size ?? CGSize(width: 24, height: 24)
        let range = maximumValue - minimumValue
        let fraction: CGFloat
        if range > 0 {
            fraction = CGFloat((min(max(value, minimumValue), maximumValue) - minimumValue) / range)
        } else {
            fraction = 0
        }

        return CGRect(
            x: rect.minX + rect.width * fraction - thumbSize.width / 2,
            y: rect.midY - thumbSize.height / 2,
            width: thumbSize.width,
            height: thumbSize.height
        )
    }

    override func point(
        inside point: CGPoint,
        with event: UIEvent?
    ) -> Bool {
        let horizontalInset = min((bounds.width - Self.minimumHitSize.width) / 2, 0)
        let verticalInset = min((bounds.height - Self.minimumHitSize.height) / 2, 0)
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset).contains(point)
    }

    override func beginTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        _ = super.beginTracking(touch, with: event)
        updateValue(for: touch, sendsValueChanged: false)
        return true
    }

    override func continueTracking(
        _ touch: UITouch,
        with event: UIEvent?
    ) -> Bool {
        updateValue(for: touch, sendsValueChanged: true)
        return true
    }

    private func configureStyle() {
        clipsToBounds = false
        minimumTrackTintColor = Self.minimumTrackColor
        maximumTrackTintColor = Self.maximumTrackColor
        if let thumbImage = UIImage(named: "slider_btn")?.withRenderingMode(.alwaysOriginal) {
            setThumbImage(thumbImage, for: .normal)
            setThumbImage(thumbImage, for: .highlighted)
        }
    }

    private func updateValue(
        for touch: UITouch,
        sendsValueChanged: Bool
    ) {
        let trackRect = trackRect(forBounds: bounds)
        guard trackRect.width > 0 else {
            return
        }
        let locationX = touch.location(in: self).x
        let fraction = min(max((locationX - trackRect.minX) / trackRect.width, 0), 1)
        let nextValue = minimumValue + Float(fraction) * (maximumValue - minimumValue)
        guard nextValue != value else {
            return
        }
        value = nextValue
        if sendsValueChanged {
            sendActions(for: .valueChanged)
        }
    }
}

@MainActor
final class ReaderV2MenuSlider: ReaderV2Slider {
    init() {
        super.init(trackHeight: 4)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class ReaderV2VoiceSlider: ReaderV2Slider {
    init() {
        super.init(trackHeight: 5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
