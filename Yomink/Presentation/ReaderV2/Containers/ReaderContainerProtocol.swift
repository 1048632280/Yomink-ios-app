import UIKit

enum ReaderPageTurnDirection {
    case forward
    case reverse

    var pageViewControllerDirection: UIPageViewController.NavigationDirection {
        switch self {
        case .forward:
            return .forward
        case .reverse:
            return .reverse
        }
    }
}

@MainActor
protocol ReaderContainerProtocol: AnyObject {
    var turnPageType: ReaderTurnPageType { get }
    var viewController: UIViewController { get }
    var currentPageModel: ReaderPageModel? { get }
    var makePageController: (@MainActor (ReaderPageModel) -> ReaderPageViewController?)? { get set }
    var adjacentPageModel: (@MainActor (ReaderPageModel, Int) -> ReaderPageModel?)? { get set }
    var onPageTurnCompleted: (@MainActor (ReaderPageModel) -> Void)? { get set }

    func display(
        pageModel: ReaderPageModel,
        pageController: ReaderPageViewController,
        direction: ReaderPageTurnDirection,
        animated: Bool
    )
    func apply(theme: ReaderTheme)
}
