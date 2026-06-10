import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

struct ReaderContentTarget: Sendable {
    let chapterID: UUID
    let offset: Int
}
