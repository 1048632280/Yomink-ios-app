import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    let environment: AppEnvironment

    override init() {
        _ = HostingControllerHomeIndicatorBridge.install
        environment = AppEnvironment.live()
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let rootView = LibraryView()
            .environmentObject(environment)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: rootView)
        self.window = window
        window.makeKeyAndVisible()

        if let url = launchOptions?[.url] as? URL {
            DispatchQueue.main.async { [weak self] in
                self?.applicationOpenURL(url)
            }
        }

        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.applicationOpenURL(url)
        }
        return true
    }

    func applicationOpenURL(_ url: URL) {
        ExternalOpenURLRelay.shared.receive(url)
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
