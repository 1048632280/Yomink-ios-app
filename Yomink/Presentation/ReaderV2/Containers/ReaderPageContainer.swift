import UIKit

@MainActor
class ReaderPageContainer: UIViewController, ReaderContainerProtocol {
    let pageViewController: UIPageViewController
    private(set) var currentPageModel: ReaderPageModel?
    private weak var prioritizedReturnGesture: UIGestureRecognizer?
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
        setCurrentPageModel(pageModel)
        pageViewController.setViewControllers(
            [pageController],
            direction: direction.pageViewControllerDirection,
            animated: animated
        )
        refreshPrioritizedReturnGesture()
    }

    func apply(theme: ReaderTheme) {
        view.backgroundColor = theme.backgroundColor
        view.isOpaque = true
        pageViewController.view.backgroundColor = theme.backgroundColor
        pageViewController.view.isOpaque = true
    }

    func selectableTextView(
        at location: CGPoint,
        from coordinateView: UIView
    ) -> TextReadView? {
        guard let pageController = currentPageController() else {
            return nil
        }
        let textLocation = pageController.textView.convert(location, from: coordinateView)
        guard pageController.textView.bounds.contains(textLocation) else {
            return nil
        }
        return pageController.textView
    }

    func pageController(adjacentTo pageController: ReaderPageViewController, delta: Int) -> ReaderPageViewController? {
        guard let pageModel = pageController.pageModel,
              let model = adjacentPageModel?(pageModel, delta) else {
            return nil
        }
        return makePageController?(model)
    }

    func currentPageController() -> ReaderPageViewController? {
        contentPageController(in: pageViewController.viewControllers)
    }

    func contentPageController(in viewControllers: [UIViewController]?) -> ReaderPageViewController? {
        viewControllers?.first { $0 is ReaderPageViewController } as? ReaderPageViewController
    }

    func setCurrentPageModel(_ pageModel: ReaderPageModel?) {
        currentPageModel = pageModel
    }

    func readerSpineLocation(for orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
        .min
    }

    func readerViewControllerBefore(_ viewController: UIViewController) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController else {
            return nil
        }
        return self.pageController(adjacentTo: pageController, delta: -1)
    }

    func readerViewControllerAfter(_ viewController: UIViewController) -> UIViewController? {
        guard let pageController = viewController as? ReaderPageViewController else {
            return nil
        }
        return self.pageController(adjacentTo: pageController, delta: 1)
    }

    func readerDidFinishPageTurn(
        in pageViewController: UIPageViewController,
        transitionCompleted completed: Bool
    ) {
        guard completed,
              let pageController = contentPageController(in: pageViewController.viewControllers),
              let pageModel = pageController.pageModel else {
            return
        }
        setCurrentPageModel(pageModel)
        onPageTurnCompleted?(pageModel)
    }

    func prioritizeReturnGesture(_ returnGesture: UIGestureRecognizer) {
        guard prioritizedReturnGesture !== returnGesture else {
            return
        }

        prioritizedReturnGesture = returnGesture
        requirePageTurnGestures(toFailBefore: returnGesture)
    }

    func refreshPrioritizedReturnGesture() {
        if let prioritizedReturnGesture {
            requirePageTurnGestures(toFailBefore: prioritizedReturnGesture)
        }
    }

    private func requirePageTurnGestures(toFailBefore returnGesture: UIGestureRecognizer) {
        pageViewController.gestureRecognizers
            .filter { $0 !== returnGesture }
            .forEach { $0.require(toFail: returnGesture) }

        scrollViews(in: pageViewController.view).forEach { scrollView in
            scrollView.panGestureRecognizer.require(toFail: returnGesture)
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        var scrollViews = (view as? UIScrollView).map { [$0] } ?? []
        for subview in view.subviews {
            scrollViews.append(contentsOf: self.scrollViews(in: subview))
        }
        return scrollViews
    }
}

extension ReaderPageContainer: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        readerViewControllerBefore(viewController)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        readerViewControllerAfter(viewController)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        readerDidFinishPageTurn(in: pageViewController, transitionCompleted: completed)
    }

    @objc(pageViewController:spineLocationForInterfaceOrientation:)
    func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
    ) -> UIPageViewController.SpineLocation {
        readerSpineLocation(for: orientation)
    }
}
