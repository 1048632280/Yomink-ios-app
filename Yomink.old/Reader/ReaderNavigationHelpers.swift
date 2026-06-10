import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

extension UIViewController {
    func readerPopOrDismiss(animated: Bool) {
        if let navigationController,
           navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: animated)
        } else {
            dismiss(animated: animated)
        }
    }
}

