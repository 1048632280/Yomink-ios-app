import UIKit

@MainActor
final class ReaderPageCurlContainer: ReaderPageContainer {
    override var turnPageType: ReaderTurnPageType {
        .pageCurl
    }

    init() {
        super.init(
            transitionStyle: .pageCurl,
            isDoubleSided: true
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        spineLocationFor orientation: UIInterfaceOrientation
    ) -> UIPageViewController.SpineLocation {
        pageViewController.isDoubleSided = true
        return .min
    }
}
