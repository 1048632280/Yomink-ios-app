import Combine
import Foundation
import OSLog

final class AppEnvironment: ObservableObject {
    enum BootstrapState {
        case ready(AppServices)
        case failed(String)
    }

    private static let logger = Logger(
        subsystem: "com.yomink.reader",
        category: "bootstrap"
    )

    @Published private(set) var bootstrapState: BootstrapState

    init(bootstrapState: BootstrapState) {
        self.bootstrapState = bootstrapState
    }

    static func live() -> AppEnvironment {
        do {
            let fileStore = try AppFileStore()
            let database = try AppDatabase(fileStore: fileStore)
            let services = AppServices(
                fileStore: fileStore,
                database: database,
                libraryRepository: GRDBLibraryRepository(database: database)
            )
            logger.info("Bootstrap completed")
            return AppEnvironment(
                bootstrapState: .ready(services)
            )
        } catch {
            logger.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
            return AppEnvironment(
                bootstrapState: .failed(error.localizedDescription)
            )
        }
    }

    static func preview() -> AppEnvironment {
        do {
            let fileStore = try AppFileStore.preview()
            let database = try AppDatabase.inMemory()
            let services = AppServices(
                fileStore: fileStore,
                database: database,
                libraryRepository: PreviewLibraryRepository()
            )
            return AppEnvironment(bootstrapState: .ready(services))
        } catch {
            return AppEnvironment(
                bootstrapState: .failed(error.localizedDescription)
            )
        }
    }
}
