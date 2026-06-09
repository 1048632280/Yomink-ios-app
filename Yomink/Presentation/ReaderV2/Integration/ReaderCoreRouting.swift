import Foundation

enum ReaderCoreEngine: Equatable, Sendable {
    case legacyCollection
    case readerV2
}

enum ReaderCoreRouting {
    static let defaultEngine: ReaderCoreEngine = .readerV2
    static let legacyFallbackEngine: ReaderCoreEngine = .legacyCollection
    static let keepsLegacyReaderForRollback = true

    static func usesReaderV2(for engine: ReaderCoreEngine = defaultEngine) -> Bool {
        engine == .readerV2
    }
}
