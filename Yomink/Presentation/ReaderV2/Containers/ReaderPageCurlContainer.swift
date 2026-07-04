import UIKit

@MainActor
final class ReaderPageCurlContainer: ReaderPageContainer {
    private var backPagePool: [ReaderPageCurlBackViewController] = []
    private var reservedBackPageIDs: Set<ObjectIdentifier> = []
    private let placeholderPageController = ReaderPageCurlPlaceholderViewController()

    override var turnPageType: ReaderTurnPageType {
        .pageCurl
    }

    init() {
        super.init(
            transitionStyle: .pageCurl,
            isDoubleSided: true
        )
        seedPlaceholderPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func display(
        pageModel: ReaderPageModel,
        pageController: ReaderPageViewController,
        direction: ReaderPageTurnDirection,
        animated: Bool
    ) {
        setCurrentPageModel(pageModel)
        if animated {
            let backPage = mirroredBackPage(from: pageController)
            pageViewController.setViewControllers(
                [pageController, backPage],
                direction: direction.pageViewControllerDirection,
                animated: animated
            ) { [weak self] _ in
                self?.reservedBackPageIDs.removeAll()
                self?.refreshPrioritizedReturnGesture()
            }
        } else {
            pageViewController.setViewControllers(
                [pageController],
                direction: direction.pageViewControllerDirection,
                animated: animated
            )
            refreshPrioritizedReturnGesture()
        }
    }

    override func readerViewControllerBefore(_ viewController: UIViewController) -> UIViewController? {
        page(for: viewController, delta: -1)
    }

    override func readerViewControllerAfter(_ viewController: UIViewController) -> UIViewController? {
        page(for: viewController, delta: 1)
    }

    override func readerDidFinishPageTurn(
        in pageViewController: UIPageViewController,
        transitionCompleted completed: Bool
    ) {
        super.readerDidFinishPageTurn(in: pageViewController, transitionCompleted: completed)
        reservedBackPageIDs.removeAll()
    }

    override func readerSpineLocation(for orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation {
        pageViewController.isDoubleSided = true
        return .min
    }

    private func page(for viewController: UIViewController, delta: Int) -> UIViewController? {
        if viewController === placeholderPageController {
            return nil
        }

        if let contentPage = viewController as? ReaderPageViewController {
            return mirroredBackPage(from: contentPage)
        }

        guard let backPage = viewController as? ReaderPageCurlBackViewController,
              let contentPage = backPage.sourcePageController ?? currentPageController() else {
            return nil
        }
        return pageController(adjacentTo: contentPage, delta: delta)
    }

    private func mirroredBackPage(from contentPage: ReaderPageViewController) -> ReaderPageCurlBackViewController {
        let backPage = idleBackPage()
        backPage.sourcePageController = contentPage
        contentPage.view.layoutIfNeeded()
        backPage.mirror(from: contentPage.view)
        return backPage
    }

    private func idleBackPage() -> ReaderPageCurlBackViewController {
        if let page = backPagePool.first(where: {
            !reservedBackPageIDs.contains(ObjectIdentifier($0))
                && $0.parent == nil
                && $0.view.superview == nil
        }) {
            reservedBackPageIDs.insert(ObjectIdentifier(page))
            return page
        }

        let page = ReaderPageCurlBackViewController()
        backPagePool.append(page)
        reservedBackPageIDs.insert(ObjectIdentifier(page))
        return page
    }

    private func seedPlaceholderPage() {
        pageViewController.setViewControllers(
            [placeholderPageController],
            direction: .forward,
            animated: false
        )
    }
}

@MainActor
private final class ReaderPageCurlPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

@MainActor
final class ReaderPageCurlBackViewController: UIViewController {
    private let imageView = UIImageView()
    weak var sourcePageController: ReaderPageViewController?
    private(set) var mirroredImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func mirror(from source: UIView) {
        loadViewIfNeeded()
        source.layoutIfNeeded()
        let bounds = source.bounds
        guard bounds.width > 0,
              bounds.height > 0 else {
            mirroredImage = nil
            imageView.image = nil
            return
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = source.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { context in
            let didDraw = source.drawHierarchy(in: bounds, afterScreenUpdates: true)
            if !didDraw {
                source.layer.render(in: context.cgContext)
            }
        }

        guard let cgImage = image.cgImage else {
            mirroredImage = image
            imageView.image = image
            return
        }

        let mirrored = UIImage(
            cgImage: cgImage,
            scale: image.scale,
            orientation: .upMirrored
        )
        mirroredImage = mirrored
        imageView.image = mirrored
    }
}
