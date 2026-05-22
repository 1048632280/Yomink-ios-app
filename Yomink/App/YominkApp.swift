import SwiftUI

@main
struct YominkApp: App {
    @StateObject private var environment: AppEnvironment

    init() {
        _environment = StateObject(wrappedValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(environment)
        }
    }
}

