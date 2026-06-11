import UIKit

struct ReaderTheme: @unchecked Sendable {
    var contentColor: UIColor
    var headerColor: UIColor
    var backgroundColor: UIColor
    var backgroundImageName: String?
    var backgroundImageStyle: String?

    static let standard = ReaderTheme(
        contentColor: ReaderTheme.color(rgbString: "62"),
        headerColor: ReaderTheme.color(rgbString: "176"),
        backgroundColor: ReaderTheme.color(rgbString: "249"),
        backgroundImageName: "theme_bg5",
        backgroundImageStyle: "2"
    )

    static let dark = ReaderTheme(
        contentColor: ReaderTheme.color(rgbString: "147,151,158"),
        headerColor: ReaderTheme.color(rgbString: "109,113,121"),
        backgroundColor: ReaderTheme.color(rgbString: "22"),
        backgroundImageName: nil,
        backgroundImageStyle: nil
    )

    static func color(rgbString: String) -> UIColor {
        let parts = rgbString
            .split(separator: ",")
            .compactMap { Double(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        if parts.count == 3 {
            return UIColor(
                red: CGFloat(parts[0] / 255),
                green: CGFloat(parts[1] / 255),
                blue: CGFloat(parts[2] / 255),
                alpha: 1
            )
        }

        let white = min(max((Double(rgbString) ?? 255) / 255, 0), 1)
        return UIColor(white: CGFloat(white), alpha: 1)
    }
}
