import UIKit

@MainActor
final class ReaderPageCurlContainer: ReaderPageContainer {
    private var backPagePool: [ReaderPageCurlBackViewController] = []
    private var reservedBackPageIDs: Set<ObjectIdentifier> = []
    private var preparedBackPages: [ObjectIdentifier: ReaderPageCurlBackViewController] = [:]
    private var scheduledBackPagePreparationID: ObjectIdentifier?
    private var scheduledBackPagePreparationToken = 0
    private var isPageCurlTransitionActive = false
    private var currentTheme = ReaderTheme.standard
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isPageCurlTransitionActive else {
            return
        }
        scheduleCurrentBackPagePreparation(after: 0.08)
    }

    override func apply(theme: ReaderTheme) {
        currentTheme = theme
        super.apply(theme: theme)
        placeholderPageController.apply(backgroundColor: theme.backgroundColor)
        backPagePool.forEach { $0.apply(backgroundColor: theme.backgroundColor) }
    }

    override func display(
        pageModel: ReaderPageModel,
        pageController: ReaderPageViewController,
        direction: ReaderPageTurnDirection,
        animated: Bool
    ) {
        setCurrentPageModel(pageModel)
        prunePreparedBackPages(keeping: [ObjectIdentifier(pageController)])
        if animated {
            let backPage = mirroredBackPage(
                from: pageController,
                reservesPage: true,
                afterScreenUpdates: true
            )
            pageViewController.setViewControllers(
                [pageController, backPage],
                direction: direction.pageViewControllerDirection,
                animated: animated
            ) { [weak self] _ in
                self?.reservedBackPageIDs.removeAll()
                self?.refreshPrioritizedReturnGesture()
                self?.scheduleBackPagePreparation(for: pageController, after: 0.18)
            }
        } else {
            pageViewController.setViewControllers(
                [pageController],
                direction: direction.pageViewControllerDirection,
                animated: animated
            )
            refreshPrioritizedReturnGesture()
            scheduleBackPagePreparation(for: pageController, after: 0.05)
        }
    }

    override func readerViewControllerBefore(_ viewController: UIViewController) -> UIViewController? {
        page(for: viewController, delta: -1)
    }

    override func readerViewControllerAfter(_ viewController: UIViewController) -> UIViewController? {
        page(for: viewController, delta: 1)
    }

    override func readerWillTransition(to pendingViewControllers: [UIViewController]) {
        isPageCurlTransitionActive = true
        scheduledBackPagePreparationToken += 1
    }

    override func readerDidFinishPageTurn(
        in pageViewController: UIPageViewController,
        transitionCompleted completed: Bool
    ) {
        super.readerDidFinishPageTurn(in: pageViewController, transitionCompleted: completed)
        reservedBackPageIDs.removeAll()
        isPageCurlTransitionActive = false
        scheduleCurrentBackPagePreparation(after: completed ? 0.22 : 0.08)
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
            return backPage(for: contentPage)
        }

        guard let backPage = viewController as? ReaderPageCurlBackViewController,
              let contentPage = backPage.sourcePageController ?? currentPageController() else {
            return nil
        }
        return pageController(adjacentTo: contentPage, delta: delta)
    }

    private func backPage(for contentPage: ReaderPageViewController) -> ReaderPageCurlBackViewController {
        let contentID = ObjectIdentifier(contentPage)
        if let preparedPage = preparedBackPages[contentID],
           preparedPage.mirroredImage != nil,
           preparedPage.parent == nil,
           preparedPage.view.superview == nil {
            preparedPage.sourcePageController = contentPage
            reservedBackPageIDs.insert(ObjectIdentifier(preparedPage))
            return preparedPage
        }

        return mirroredBackPage(
            from: contentPage,
            reservesPage: true,
            afterScreenUpdates: false
        )
    }

    @discardableResult
    private func mirroredBackPage(
        from contentPage: ReaderPageViewController,
        reservesPage: Bool,
        afterScreenUpdates: Bool
    ) -> ReaderPageCurlBackViewController {
        let contentID = ObjectIdentifier(contentPage)
        let backPage = idleBackPage(
            reservesPage: reservesPage,
            protectedContentID: contentID
        )
        backPage.sourcePageController = contentPage
        backPage.apply(backgroundColor: currentTheme.backgroundColor)
        contentPage.view.layoutIfNeeded()
        backPage.mirror(
            from: contentPage.view,
            afterScreenUpdates: afterScreenUpdates
        )
        if backPage.mirroredImage != nil {
            removePreparedBackPageReferences(to: backPage)
            preparedBackPages[contentID] = backPage
        }
        return backPage
    }

    private func idleBackPage(
        reservesPage: Bool,
        protectedContentID: ObjectIdentifier? = nil
    ) -> ReaderPageCurlBackViewController {
        let protectedBackPageIDs = protectedPreparedBackPageIDs(excluding: protectedContentID)
        if let page = backPagePool.first(where: {
            let pageID = ObjectIdentifier($0)
            return !reservedBackPageIDs.contains(pageID)
                && !protectedBackPageIDs.contains(pageID)
                && $0.parent == nil
                && $0.view.superview == nil
        }) {
            if reservesPage {
                reservedBackPageIDs.insert(ObjectIdentifier(page))
            }
            return page
        }

        let page = ReaderPageCurlBackViewController()
        backPagePool.append(page)
        if reservesPage {
            reservedBackPageIDs.insert(ObjectIdentifier(page))
        }
        return page
    }

    private func scheduleCurrentBackPagePreparation(after delay: TimeInterval = 0.08) {
        guard let contentPage = currentPageController() else {
            return
        }
        scheduleBackPagePreparation(for: contentPage, after: delay)
    }

    private func scheduleBackPagePreparation(
        for contentPage: ReaderPageViewController,
        after delay: TimeInterval = 0.08
    ) {
        let contentID = ObjectIdentifier(contentPage)
        guard preparedBackPages[contentID]?.mirroredImage == nil else {
            return
        }

        scheduledBackPagePreparationID = contentID
        scheduledBackPagePreparationToken += 1
        let token = scheduledBackPagePreparationToken
        let prepare = { [weak self, weak contentPage] in
            guard let self,
                  let contentPage,
                  self.scheduledBackPagePreparationID == contentID,
                  self.scheduledBackPagePreparationToken == token,
                  !self.isPageCurlTransitionActive,
                  self.currentPageController() === contentPage else {
                return
            }
            self.prepareBackPageIfPossible(for: contentPage)
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                prepare()
            }
        } else {
            DispatchQueue.main.async {
                prepare()
            }
        }
    }

    private func prepareBackPageIfPossible(for contentPage: ReaderPageViewController) {
        let contentID = ObjectIdentifier(contentPage)
        guard contentPage.view.bounds.width > 0,
              contentPage.view.bounds.height > 0 else {
            return
        }

        prunePreparedBackPages(keeping: [contentID])
        mirroredBackPage(
            from: contentPage,
            reservesPage: false,
            afterScreenUpdates: false
        )
    }

    private func prunePreparedBackPages(keeping contentIDs: Set<ObjectIdentifier>) {
        preparedBackPages = preparedBackPages.filter { contentIDs.contains($0.key) }
    }

    private func removePreparedBackPageReferences(to page: ReaderPageCurlBackViewController) {
        let pageID = ObjectIdentifier(page)
        preparedBackPages = preparedBackPages.filter { ObjectIdentifier($0.value) != pageID }
    }

    private func protectedPreparedBackPageIDs(excluding contentID: ObjectIdentifier?) -> Set<ObjectIdentifier> {
        Set(
            preparedBackPages.compactMap { entry in
                if let contentID = contentID,
                   entry.key == contentID {
                    return nil
                }
                return ObjectIdentifier(entry.value)
            }
        )
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
    private var pageBackgroundColor = ReaderTheme.standard.backgroundColor

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageBackgroundColor
        view.isOpaque = true
    }

    func apply(backgroundColor: UIColor) {
        pageBackgroundColor = backgroundColor
        if isViewLoaded {
            view.backgroundColor = backgroundColor
            view.isOpaque = true
        }
    }
}

@MainActor
final class ReaderPageCurlBackViewController: UIViewController {
    private let imageView = UIImageView()
    private var pageBackgroundColor = ReaderTheme.standard.backgroundColor
    weak var sourcePageController: ReaderPageViewController?
    private(set) var mirroredImage: UIImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageBackgroundColor
        view.isOpaque = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = pageBackgroundColor
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func apply(backgroundColor: UIColor) {
        pageBackgroundColor = backgroundColor
        if isViewLoaded {
            view.backgroundColor = backgroundColor
            view.isOpaque = true
            imageView.backgroundColor = backgroundColor
            imageView.isOpaque = true
        }
    }

    func mirror(
        from source: UIView,
        afterScreenUpdates: Bool = false
    ) {
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
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        let image = renderer.image { context in
            pageBackgroundColor.setFill()
            context.fill(bounds)
            let didDraw = source.drawHierarchy(
                in: bounds,
                afterScreenUpdates: afterScreenUpdates
            )
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
