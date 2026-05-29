import SwiftUI
import UIKit
import ObjectiveC

/// SwiftUI 的 `UIHostingController` 默认不会把 `prefersHomeIndicatorAutoHidden`
/// 与 `preferredScreenEdgesDeferringSystemGestures` 转发到内嵌的 UIKit 子控制器，
/// 导致 `CollectionReaderViewController` 中重写的这两个属性被系统忽略。
///
/// 这里通过运行时方法替换，让所有 `UIHostingController` 的
/// `childForHomeIndicatorAutoHidden` / `childForScreenEdgesDeferringSystemGestures`
/// 优先返回 `presentedViewController`，其次返回 `children.last`，
/// 从而把查询链一路向下传到最内层的 UIKit VC。
///
/// 仅替换默认返回 `nil` 的情况；若 hosting controller 子类自己有实现，保持不变。
enum HostingControllerHomeIndicatorBridge {
    static let install: Void = {
        installSwizzle(
            originalSelector: #selector(getter: UIViewController.childForHomeIndicatorAutoHidden),
            swizzledSelector: #selector(UIHostingControllerHomeIndicatorSwizzle.yomink_childForHomeIndicatorAutoHidden)
        )
        installSwizzle(
            originalSelector: #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures),
            swizzledSelector: #selector(UIHostingControllerHomeIndicatorSwizzle.yomink_childForScreenEdgesDeferringSystemGestures)
        )
    }()

    private static func installSwizzle(
        originalSelector: Selector,
        swizzledSelector: Selector
    ) {
        // 以 UIHostingController<AnyView> 作为基类锚点。其它泛型实参的 hosting
        // controller 共享同一份 Objective-C 类方法表，替换一次即可。
        let baseClass: AnyClass = UIHostingController<AnyView>.self
        guard
            let originalMethod = class_getInstanceMethod(baseClass, originalSelector),
            let swizzledMethod = class_getInstanceMethod(
                UIHostingControllerHomeIndicatorSwizzle.self,
                swizzledSelector
            )
        else {
            return
        }

        let didAdd = class_addMethod(
            baseClass,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAdd {
            // UIHostingController 自身没有重写该 getter,从父类继承。
            // class_addMethod 把我们的实现挂到 hosting controller 类上,
            // 直接覆盖父类查找结果,不需要再交换。
            return
        }

        // 兜底:若 hosting controller 自己有实现,走 exchange。
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

/// 仅用于承载替换方法实现的占位类。运行时这两个方法会被注入到
/// `UIHostingController` 的方法表里。
private final class UIHostingControllerHomeIndicatorSwizzle: UIViewController {
    @objc func yomink_childForHomeIndicatorAutoHidden() -> UIViewController? {
        if let presented = presentedViewController, !presented.isBeingDismissed {
            return presented
        }
        return children.last
    }

    @objc func yomink_childForScreenEdgesDeferringSystemGestures() -> UIViewController? {
        if let presented = presentedViewController, !presented.isBeingDismissed {
            return presented
        }
        return children.last
    }
}
