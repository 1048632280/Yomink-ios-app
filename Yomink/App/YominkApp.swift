import SwiftUI
import UIKit

@main
struct YominkApp: App {
    @UIApplicationDelegateAdaptor(YominkAppDelegate.self) private var appDelegate
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
                .onOpenURL { url in
                    ExternalOpenURLRelay.shared.receive(url)
                }
        }
    }
}

final class YominkAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let url = launchOptions?[.url] as? URL {
            ExternalOpenURLRelay.shared.receive(url)
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        ExternalOpenURLRelay.shared.receive(url)
        return true
    }
}

final class ExternalOpenURLRelay: ObservableObject {
    static let shared = ExternalOpenURLRelay()

    @Published private(set) var event: ExternalOpenURLEvent?
    private var lastReceivedURL: URL?
    private var lastReceivedAt = Date.distantPast

    func receive(_ url: URL) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.receive(url)
            }
            return
        }

        let now = Date()
        if lastReceivedURL == url,
           now.timeIntervalSince(lastReceivedAt) < 0.5 {
            return
        }

        lastReceivedURL = url
        lastReceivedAt = now
        event = ExternalOpenURLEvent(url: url)
    }

    func clear(_ event: ExternalOpenURLEvent) {
        guard self.event == event else {
            return
        }

        self.event = nil
    }
}

struct ExternalOpenURLEvent: Equatable, Identifiable {
    let id = UUID()
    let url: URL
}
