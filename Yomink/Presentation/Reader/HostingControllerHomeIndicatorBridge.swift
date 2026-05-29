import SwiftUI
import UIKit
import ObjectiveC

/// SwiftUI 的 `UIHostingController<Content>` 在 Objective-C runtime 中,每个不同
/// 的泛型实参都是一个**独立的类**(`UIHostingController<AnyView>` 与
/// `UIHostingController<ModifiedContent<...>>` 不共享方法表)。
///
/// 因此不能只 swizzle "UIHostingController" 一个类,必须遍历运行时已注册的全部
/// 类,把所有从 `UIHostingController` 继承的子类一一注入 child 转发方法。
///
/// 注入后的行为:
/// - `childForHomeIndicatorAutoHidden`
/// - `childForScreenEdgesDeferringSystemGestures`
/// 优先返回 `presentedViewController`(modal 链),其次返回 `children.last`
/// (child VC 链),从而把查询一路向下传到最内层的 UIKit VC
/// (`CollectionReaderViewController`)。
enum HostingControllerHomeIndicatorBridge {
    static let install: Void = {
        installForAllHostingSubclasses()
    }()

    /// 供 reader VC 在 viewDidAppear 时再次调用,覆盖 SwiftUI 后续才注册的
    /// 新泛型 hosting controller 子类。重复对同一个类安装会被 `class_addMethod`
    /// 的失败分支自然忽略。
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

        // 用 replace 而不是 add:SwiftUI 的 UIHostingController 自己实现了这两个
        // getter(返回 nil),class_addMethod 会因方法表已存在条目而静默失败。
        // class_replaceMethod 无条件覆盖目标类自身方法表中的 IMP,确保我们的
        // 转发实现真正生效。
        class_replaceMethod(cls, selector, imp, typeEncoding)
    }
}

/// 仅用于承载注入方法的实现。运行时这两个方法体会被复制到每个
/// UIHostingController 子类的方法表里。
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
}
