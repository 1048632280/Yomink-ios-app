import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

struct ReaderLayoutConfiguration {
    var bodyKern: CGFloat
    var bodyLineSpacing: CGFloat
    var bodyParagraphSpacing: CGFloat
    var topMargin: CGFloat
    var bottomMargin: CGFloat
    var leftMargin: CGFloat
    var rightMargin: CGFloat
    var bodyFontWeight: UIFont.Weight
    var firstLineIndentEms: CGFloat
    var titleKern: CGFloat
    var titleLineSpacing: CGFloat
    var titleParagraphSpacing: CGFloat
    var titleFontSizeDelta: CGFloat
    var titleFontWeight: UIFont.Weight
    var widgetHorizontalMargin: CGFloat
    var widgetBottomMargin: CGFloat
    var widgetTitleTopMargin: CGFloat
    var widgetTitleLeftMargin: CGFloat
}

struct ReaderTypography: @unchecked Sendable {
    var fontSize: Double
    var textColor: UIColor
    var chapterTitle: String?
    var layout: ReaderLayoutConfiguration

    init(settings: ReaderSettings, chapterTitle: String? = nil) {
        let normalizedSettings = settings.normalized
        fontSize = normalizedSettings.fontSize
        textColor = normalizedSettings.theme.textColor
        self.chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        layout = normalizedSettings.effectiveLayoutConfiguration
    }

    func attributedString(for text: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text)
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard fullRange.length > 0 else {
            return attributedString
        }

        let bodyFont = scaledFont(
            size: CGFloat(fontSize),
            weight: layout.bodyFontWeight
        )
        let titleFont = scaledFont(
            size: CGFloat(fontSize) + layout.titleFontSizeDelta,
            weight: layout.titleFontWeight
        )
        let titleRange = titleParagraphRange(in: nsText, fullRange: fullRange)

        nsText.enumerateSubstrings(
            in: fullRange,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, enclosingRange, _ in
            let range = NSIntersectionRange(enclosingRange, fullRange)
            guard range.length > 0 else {
                return
            }

            let isTitle = titleRange?.location == paragraphRange.location
                && titleRange?.length == paragraphRange.length
            if isTitle {
                attributedString.addAttributes(
                    titleAttributes(font: titleFont),
                    range: range
                )
            } else {
                attributedString.addAttributes(
                    bodyAttributes(
                        font: bodyFont,
                        nsText: nsText,
                        paragraphRange: paragraphRange
                    ),
                    range: range
                )
            }
        }

        return attributedString
    }

    private func scaledFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
    }

    private func bodyAttributes(
        font: UIFont,
        nsText: NSString,
        paragraphRange: NSRange
    ) -> [NSAttributedString.Key: Any] {
        let firstLineIndent = hasExistingFirstLineIndent(in: nsText, paragraphRange: paragraphRange)
            ? 0
            : font.pointSize * layout.firstLineIndentEms

        return [
            .font: font,
            .foregroundColor: textColor,
            .kern: layout.bodyKern,
            .paragraphStyle: coreTextParagraphStyle(
                lineSpacing: layout.bodyLineSpacing,
                paragraphSpacing: layout.bodyParagraphSpacing,
                firstLineIndent: firstLineIndent
            ),
            .ligature: 0
        ]
    }

    private func titleAttributes(font: UIFont) -> [NSAttributedString.Key: Any] {
        return [
            .font: font,
            .foregroundColor: textColor,
            .kern: layout.titleKern,
            .paragraphStyle: coreTextParagraphStyle(
                lineSpacing: layout.titleLineSpacing,
                paragraphSpacing: layout.titleParagraphSpacing,
                firstLineIndent: 0
            ),
            .ligature: 0
        ]
    }

    private func coreTextParagraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        firstLineIndent: CGFloat
    ) -> CTParagraphStyle {
        var alignment = CTTextAlignment.justified
        var lineBreakMode = CTLineBreakMode.byWordWrapping
        var lineSpacingAdjustment = lineSpacing
        var minimumLineSpacing = lineSpacing
        var maximumLineSpacing = lineSpacing
        var paragraphSpacingValue = paragraphSpacing
        var firstLineIndentValue = firstLineIndent
        return withUnsafePointer(to: &alignment) { alignmentPointer in
            withUnsafePointer(to: &lineBreakMode) { lineBreakPointer in
                withUnsafePointer(to: &lineSpacingAdjustment) { lineSpacingAdjustmentPointer in
                    withUnsafePointer(to: &minimumLineSpacing) { minimumLineSpacingPointer in
                        withUnsafePointer(to: &maximumLineSpacing) { maximumLineSpacingPointer in
                            withUnsafePointer(to: &paragraphSpacingValue) { paragraphSpacingPointer in
                                withUnsafePointer(to: &firstLineIndentValue) { firstLineIndentPointer in
                                    let settings = [
                                        CTParagraphStyleSetting(
                                            spec: .alignment,
                                            valueSize: MemoryLayout<CTTextAlignment>.size,
                                            value: UnsafeRawPointer(alignmentPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .lineBreakMode,
                                            valueSize: MemoryLayout<CTLineBreakMode>.size,
                                            value: UnsafeRawPointer(lineBreakPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .lineSpacingAdjustment,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(lineSpacingAdjustmentPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .minimumLineSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(minimumLineSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .maximumLineSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(maximumLineSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .paragraphSpacing,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(paragraphSpacingPointer)
                                        ),
                                        CTParagraphStyleSetting(
                                            spec: .firstLineHeadIndent,
                                            valueSize: MemoryLayout<CGFloat>.size,
                                            value: UnsafeRawPointer(firstLineIndentPointer)
                                        )
                                    ]
                                    return CTParagraphStyleCreate(settings, settings.count)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func titleParagraphRange(in nsText: NSString, fullRange: NSRange) -> NSRange? {
        guard let expectedTitle = chapterTitle,
              !expectedTitle.isEmpty
        else {
            return nil
        }

        var result: NSRange?
        nsText.enumerateSubstrings(
            in: fullRange,
            options: [.byParagraphs, .substringNotRequired]
        ) { _, paragraphRange, _, stop in
            let candidate = nsText.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else {
                return
            }

            if candidate == expectedTitle {
                result = paragraphRange
            }
            stop.pointee = true
        }
        return result
    }

    private func hasExistingFirstLineIndent(
        in nsText: NSString,
        paragraphRange: NSRange
    ) -> Bool {
        guard paragraphRange.length > 0 else {
            return false
        }

        let paragraph = nsText.substring(with: paragraphRange)
        guard let firstCharacter = paragraph.first else {
            return false
        }

        return firstCharacter.isWhitespace
    }
}

func readerFontWeight(for value: Double) -> UIFont.Weight {
    switch Int(value.rounded()) {
    case 0:
        return .regular
    case 1:
        return .medium
    case 2:
        return .semibold
    case 3:
        return .bold
    case 4:
        return .heavy
    default:
        return .black
    }
}

final class CollectionReaderPageCell: UICollectionViewCell {
    static let reuseIdentifier = "CollectionReaderPageCell"

    private let pageView = CollectionCoreTextPageView()
    private let widgetOverlay = ReaderPageWidgetOverlayView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        pageView.translatesAutoresizingMaskIntoConstraints = false
        widgetOverlay.translatesAutoresizingMaskIntoConstraints = false
        widgetOverlay.isUserInteractionEnabled = false
        contentView.addSubview(pageView)
        contentView.addSubview(widgetOverlay)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            widgetOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            widgetOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            widgetOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            widgetOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        pageView.configure(
            attributedText: NSAttributedString(string: ""),
            layout: CollectionReaderPaginator.withDisabledWidgets(ReaderSettings.default)
                .effectiveLayoutConfiguration,
            backgroundColor: ReaderSettings.default.theme.backgroundColor
        )
        widgetOverlay.isHidden = true
    }

    func configure(
        page: CollectionReaderPage,
        settings: ReaderSettings,
        layout: ReaderLayoutConfiguration,
        widgetSnapshot: ReaderPageWidgetSnapshot,
        widgetLayout: ReaderWidgetLayoutConfiguration,
        showsWidgets: Bool
    ) {
        let backgroundColor = settings.theme.backgroundColor
        contentView.backgroundColor = backgroundColor
        pageView.configure(
            attributedText: page.attributedText,
            layout: showsWidgets ? page.contentLayout : layout,
            backgroundColor: backgroundColor
        )
        widgetOverlay.isHidden = !showsWidgets
        if showsWidgets {
            widgetOverlay.configure(
                snapshot: widgetSnapshot,
                settings: settings,
                layout: widgetLayout
            )
        }
    }
}

private final class CollectionCoreTextPageView: UIView {
    private var attributedText = NSAttributedString(string: "")
    private var layout = ReaderSettings.default.layoutPreset.layoutConfiguration

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        attributedText: NSAttributedString,
        layout: ReaderLayoutConfiguration,
        backgroundColor: UIColor
    ) {
        self.attributedText = attributedText
        self.layout = layout
        self.backgroundColor = backgroundColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard attributedText.length > 0,
              let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let contentRect = layout.contentRect(in: bounds)
        guard contentRect.width > 0,
              contentRect.height > 0 else {
            return
        }

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)

        let path = CGMutablePath()
        path.addRect(contentRect)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

extension ReaderLayoutConfiguration {
    func contentRect(in bounds: CGRect) -> CGRect {
        let minX = ceil(leftMargin)
        let minY = ceil(bottomMargin)
        let maxX = floor(bounds.width - rightMargin)
        let maxY = floor(bounds.height - topMargin)
        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }
}
