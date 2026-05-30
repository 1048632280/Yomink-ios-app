import Foundation

enum DatabaseDateFormatter {
    static func string(from date: Date) -> String {
        makeFormatter().string(from: date)
    }

    static func date(from string: String) -> Date? {
        makeFormatter().date(from: string)
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
