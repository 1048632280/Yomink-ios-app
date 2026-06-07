import SwiftUI
import UIKit
import ObjectiveC

/// 让 SwiftUI 包裹的 UIKit 视图控制器能够正确控制 home indicator 行为。
///
/// SwiftUI 的 `UIHostingController` 默认不会把
/// `prefersHomeIndicatorAutoHidden` / `preferredScreenEdgesDeferringSystemGestures`
/// 的查询转发给内嵌的 UIKit 子控制器,导致重写的属性被系统忽略。本桥接器
/// 在运行时为所有 `UIHostingController` 子类注入两组方法:
///
/// 1. `childForHomeIndicatorAutoHidden` /
///    `childForScreenEdgesDeferringSystemGestures`
///    返回 `presentedViewController`、导航控制器当前页或 `children.last`,
///    打通从 root 到内层 UIKit VC 的 child 查询链。
///
/// 2. `preferredScreenEdgesDeferringSystemGestures` getter 本身
///    iOS 15 查询此属性时不会沿 child 链向下,只读 hosting controller
///    自己的值。覆盖后会沿 child / presented 链找到链尾 VC,
///    把链尾的诉求"提"到 hosting controller 上,系统在任何层级求值
///    都能拿到正确的延迟边缘。
///
/// 注意:每个泛型实参的 `UIHostingController<T>` 在 Objective-C runtime
/// 中是独立的类(方法表互不共享),因此必须遍历所有已注册类逐一注入。
enum HostingControllerHomeIndicatorBridge {
    /// 在 App 启动期调用一次,触发对当前已注册类的全量扫描。
    static let install: Void = {
        installForAllHostingSubclasses()
    }()

    /// 兜底入口:SwiftUI 可能在 App 启动后才动态生成新的泛型 hosting
    /// 子类(例如打开 reader 时),此方法用于在恰当时机重新扫描。
    /// 重复调用幂等。
    static func ensureInstalledForCurrentlyRegisteredClasses() {
        installForAllHostingSubclasses()
    }

    private static func installForAllHostingSubclasses() {
        let classCount = objc_getClassList(nil, 0)
        guard classCount > 0 else { return }

        let buffer = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(classCount))
        defer { buffer.deallocate() }
        let actualCount = objc_getClassList(
            AutoreleasingUnsafeMutablePointer<AnyClass>(buffer),
            classCount
        )

        for i in 0..<min(Int(actualCount), Int(classCount)) {
            let cls: AnyClass = buffer[i]
            guard isHostingControllerClass(cls) else { continue }
            inject(into: cls)
        }
    }

    /// 通过类名字符串匹配判断是否是 `UIHostingController` 子类。
    /// 不能使用 `isSubclass(of: UIHostingController<...>.superclass())`——
    /// 那个 superclass 是 `UIViewController` 自身,会误伤所有 UIKit VC。
    private static func isHostingControllerClass(_ cls: AnyClass) -> Bool {
        var current: AnyClass? = cls
        while let c = current {
            if NSStringFromClass(c).contains("UIHostingController") {
                return true
            }
            current = class_getSuperclass(c)
        }
        return false
    }

    private static func inject(into cls: AnyClass) {
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.childForHomeIndicatorAutoHidden),
            donorSelector: #selector(HostingHomeIndicatorBridgeDonor.bridge_childForHomeIndicatorAutoHidden)
        )
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.childForScreenEdgesDeferringSystemGestures),
            donorSelector: #selector(HostingHomeIndicatorBridgeDonor.bridge_childForScreenEdgesDeferringSystemGestures)
        )
        injectMethod(
            into: cls,
            selector: #selector(getter: UIViewController.preferredScreenEdgesDeferringSystemGestures),
            donorSelector: #selector(HostingHomeIndicatorBridgeDonor.bridge_preferredScreenEdgesDeferringSystemGestures)
        )
    }

    private static func injectMethod(
        into cls: AnyClass,
        selector: Selector,
        donorSelector: Selector
    ) {
        guard let donorMethod = class_getInstanceMethod(
            HostingHomeIndicatorBridgeDonor.self,
            donorSelector
        ) else { return }

        // 用 replace 强制覆盖:SwiftUI 的 UIHostingController 自带这些
        // getter 的默认实现(均返回 nil / []),class_addMethod 会因方法已存在
        // 而静默失败,必须用 replace 才能真正生效。
        class_replaceMethod(
            cls,
            selector,
            method_getImplementation(donorMethod),
            method_getTypeEncoding(donorMethod)
        )
    }
}

/// 仅用于承载注入方法的实现宿主。运行时这些方法体会被复制到每个
/// `UIHostingController` 子类的方法表里;调用时 `self` 指向真实的
/// hosting controller 实例。
private final class HostingHomeIndicatorBridgeDonor: UIViewController {
    @objc func bridge_childForHomeIndicatorAutoHidden() -> UIViewController? {
        Self.nextHomeIndicatorController(from: self)
    }

    @objc func bridge_childForScreenEdgesDeferringSystemGestures() -> UIViewController? {
        Self.nextHomeIndicatorController(from: self)
    }

    @objc func bridge_preferredScreenEdgesDeferringSystemGestures() -> UIRectEdge {
        let tail = Self.findChainTail(from: self)
        guard tail !== self else { return [] }
        return tail.preferredScreenEdgesDeferringSystemGestures
    }

    /// 沿 `presentedViewController`(优先)、导航控制器当前页或 `children.last`
    /// 一路向下,直到没有更深层的 VC 为止。`visited` 防止循环引用。
    private static func findChainTail(from start: UIViewController) -> UIViewController {
        var current: UIViewController = start
        var visited: Set<ObjectIdentifier> = [ObjectIdentifier(current)]
        while true {
            let next = nextHomeIndicatorController(from: current)
            guard let n = next else { return current }
            let id = ObjectIdentifier(n)
            if visited.insert(id).inserted == false { return current }
            current = n
        }
    }

    private static func nextHomeIndicatorController(from controller: UIViewController) -> UIViewController? {
        if let presented = controller.presentedViewController,
           !presented.isBeingDismissed {
            return presented
        }

        if let navigationController = controller as? UINavigationController {
            return navigationController.visibleViewController
                ?? navigationController.topViewController
                ?? navigationController.children.last
        }

        return controller.children.last
    }
}
