import SwiftUI
import UIKit
import ObjectiveC

/// SwiftUI 的 `UIHostingController<Content>` 在 Objective-C runtime 中,每个不同
/// 的泛型实参都是一个**独立的类**(`UIHostingController<AnyView>` 与
/// `UIHostingController<ModifiedContent<...>>` 不共享方法表)。
///
/// 因此不能只 swizzle "UIHostingController" 一个类,必须遍历运行时已注册的全部
/// 类,把所有从 `UIHostingController` 继承的子类一一注入桥接方法。
///
/// 注入两组方法:
///
/// 1. `childForHomeIndicatorAutoHidden` / `childForScreenEdgesDeferringSystemGestures`
///    优先返回 `presentedViewController` 否则 `children.last`,
///    保证沿 child 链能找到内层 UIKit VC。
///
/// 2. `preferredScreenEdgesDeferringSystemGestures` getter 直接覆盖:
///    iOS 15 不会沿 child 链查询这个值,只读 hosting controller 自己的。
///    我们让 hosting controller 沿 child 链向下递归找到链尾 VC,
///    如果链尾是开启了"小横条休眠"的 reader VC,就返回 `.bottom`。
///    这样系统对 hosting controller 自身求值时也能拿到正确的延迟边缘。
enum HostingControllerHomeIndicatorBridge {
    static let install: Void = {
        installForAllHostingSubclasses()
    }()

    /// 供 reader VC 在 viewDidAppear 时再次调用,覆盖 SwiftUI 后续才注册的
    /// 新泛型 hosting controller 子类。
    static func ensureInstalledForCurrentlyRegisteredClasses() {
        installForAllHostingSubclasses()
    }

    private static func installForAllHostingSubclasses() {
        let hostingBaseClass: AnyClass = NSClassFromString("SwiftUI.UIHostingController")
            ?? UIHostingController<AnyView>.superclass()
            ?? UIViewController.self

        let classCount = objc_getClassList(nil, 0)
        guard classCount > 0 else { return }

        let allClasses = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(classCount))
        defer { allClasses.deallocate() }
        let autoreleasingPtr = AutoreleasingUnsafeMutablePointer<AnyClass>(allClasses)
        let actualCount = objc_getClassList(autoreleasingPtr, classCount)

        for i in 0..<Int(actualCount) {
            let cls: AnyClass = allClasses[i]
            guard isSubclass(cls, of: hostingBaseClass) else { continue }
            inject(into: cls)
        }
    }

    private static func isSubclass(_ cls: AnyClass, of base: AnyClass) -> Bool {
        var current: AnyClass? = cls
        while let c = current {
            if c === base { return true }
            current = class_getSuperclass(c)
        }
        return false
    }

    private static func inject(into cls: AnyClass) {
        // child 链转发 (沿用)
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.childForHomeIndicatorAutoHidden),
            donorSelector: #selector(YominkHostingChildForwarder.yomink_childForHomeIndicatorAutoHidden)
        )
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures),
            donorSelector: #selector(YominkHostingChildForwarder.yomink_childForScreenEdgesDeferringSystemGestures)
        )
        // 关键新增:直接覆盖 deferring edges getter
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures),
            donorSelector: #selector(YominkHostingChildForwarder.yomink_preferredScreenEdgesDeferringSystemGestures)
        )
    }

    private static func injectMethod(
        into cls: AnyClass,
        selector: Selector,
        donorSelector: Selector
    ) {
        guard let donorMethod = class_getInstanceMethod(
            YominkHostingChildForwarder.self,
            donorSelector
        ) else { return }

        let imp = method_getImplementation(donorMethod)
        let typeEncoding = method_getTypeEncoding(donorMethod)

        // 用 replace 强制覆盖:SwiftUI 的 UIHostingController 自带这些 getter 的实现,
        // class_addMethod 会在已有同名方法时静默失败,所以必须 replace。
        class_replaceMethod(cls, selector, imp, typeEncoding)
    }
}

/// 仅用于承载注入方法的实现。运行时这些方法体会被复制到每个
/// UIHostingController 子类的方法表里。`self` 在方法被调用时指向那个
/// hosting controller 实例。
private final class YominkHostingChildForwarder: UIViewController {
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

    /// 直接返回 deferring edges:沿 child / presented 链找到链尾的非 hosting VC,
    /// 如果它声明了希望延迟底部边缘手势,就返回 `.bottom`,否则 `[]`。
    /// iOS 15 不会沿 child 链查询这个属性,所以每个 hosting controller 自己求值
    /// 时都要把链尾的诉求"提"上来。
    @objc func yomink_preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        let tail = Self.findChainTail(from: self)
        guard tail !== self else { return [] }
        return tail.preferredScreenEdgesDeferringSystemGestures
    }

    /// 沿 presentedViewController(优先)或 children.last 一路向下,直到链尾。
    /// 链尾 = 没有 presented 且没有 children 的那个 VC,
    /// 或者沿途遇到非 hosting controller 时就停下来用它的值。
    private static func findChainTail(from start: UIViewController) -> UIViewController {
        var current: UIViewController = start
        var visited: Set<ObjectIdentifier> = [ObjectIdentifier(current)]
        while true {
            let next: UIViewController?
            if let presented = current.presentedViewController, !presented.isBeingDismissed {
                next = presented
            } else if let lastChild = current.children.last {
                next = lastChild
            } else {
                next = nil
            }
            guard let n = next else { return current }
            let id = ObjectIdentifier(n)
            if visited.contains(id) { return current }
            visited.insert(id)
            current = n
        }
    }
}
