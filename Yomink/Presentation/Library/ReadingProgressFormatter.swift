import Foundation

enum ReadingProgressFormatter {
    static func percentString(from progress: Double) -> String {
        percentFormatter.string(from: NSNumber(value: clamped(progress))) ?? "0%"
    }

    static func tooltipPercentString(from progress: Double) -> String {
        tooltipPercentFormatter.string(from: NSNumber(value: clamped(progress))) ?? "0.00%"
    }

    private static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let tooltipPercentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
