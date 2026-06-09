import Foundation

enum ReaderTurnPageType: Int, Codable, CaseIterable, Sendable {
    case horizontalScroll = 0
    case pageCurl = 1
    case verticalContinuous = 3
}
