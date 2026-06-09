import UIKit

@MainActor
class ReaderPageContainer: UIViewController, ReaderContainerProtocol {
    let pageViewController: UIPageViewController
    private(set) var currentPageModel: ReaderPageModel?
    var makePageController: (@MainActor (ReaderPageModel) -> ReaderPageViewController?)?
    var adjacentPageModel: (@MainActor (ReaderPageModel, Int) -> ReaderPageModel?)?
    var onPageTurnCompleted: (@MainActor (ReaderPageModel) -> Void)?

    var turnPageType: ReaderTurnPageType {
        .horizontalScroll
    }

    var viewController: UIViewController {
        self
    }

    init(
        transitionStyle: UIPageViewController.TransitionStyle = .scroll,
        isDoubleSided: Bool = false
    ) {
        pageViewController = UIPageViewController(
            transitionStyle: transitionStyle,
            navigationOrientation: .horizontal
        )
        super.init(nibName: nil, bundle: nil)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.isDoubleSided = isDoubleSided
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(pageViewController)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)
    }

    func display(
        pageModel: ReaderPageModel,
        pageController: ReaderPageViewController,
        direction: ReaderPageTurnDirection,
        animated: Bool
    ) {
        currentPageModel = pageModel
        pageViewController.setViewControllers(
            [pageController],
            direction: direction.pageViewControllerDirection,
            animated: animated
        )
    }

    func apply(theme: ReaderTheme) {
        view.backgroundColor = theme.backgroundColor
        pageViewController.view.backgroundColor = theme.backgroundColor
    }

    func pageController(adjacentTo pageController: ReaderPageViewController, delta: Int) -> ReaderPageViewController? {
        guard let pageModel = pageController.pageModel,
              let model = adjacentPageModel?(pageModel, delta) else {
            return nil
        }
        return makePageController?(model)
    }
}

extension ReaderPageContainer: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController else {
            return nil
        }
        return self.pageController(adjacentTo: pageController, delta: -1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController else {
            return nil
        }
        return self.pageController(adjacentTo: pageController, delta: 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let pageController = pageViewController.viewControllers?.first as? ReaderPageViewController,
              let pageModel = pageController.pageModel else {
            return
        }
        currentPageModel = pageModel
        onPageTurnCompleted?(pageModel)
    }
}
