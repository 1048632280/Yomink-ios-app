import SwiftUI

@main
struct YominkApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        // 触发一次性 swizzle,让 UIHostingController 把
        // childForHomeIndicatorAutoHidden / childForScreenEdgesDeferringSystemGestures
        // 转发给内嵌的 UIKit 子控制器(详见 HostingControllerHomeIndicatorBridge)
        _ = HostingControllerHomeIndicatorBridge.install
        _environment = StateObject(wrappedValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(environment)
        }
    }
}

