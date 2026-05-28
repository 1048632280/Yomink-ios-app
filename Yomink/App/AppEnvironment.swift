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
            let repository = GRDBLibraryRepository(database: database)
            let services = AppServices(
                fileStore: fileStore,
                database: database,
                libraryRepository: repository,
                importService: ImportService(
                    fileStore: fileStore,
                    libraryRepository: repository
                )
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
            try FileManager.default.createDirectory(
                at: fileStore.bookDirectoryURL(for: PreviewLibraryRepository.sampleBookID),
                withIntermediateDirectories: true
            )
            try PreviewLibraryRepository.sampleText.write(
                to: fileStore.contentURL(for: PreviewLibraryRepository.sampleBookID),
                atomically: true,
                encoding: .utf8
            )
            let database = try AppDatabase.inMemory()
            let repository = PreviewLibraryRepository()
            let services = AppServices(
                fileStore: fileStore,
                database: database,
                libraryRepository: repository,
                importService: ImportService(
                    fileStore: fileStore,
                    libraryRepository: repository
                )
            )
            return AppEnvironment(bootstrapState: .ready(services))
        } catch {
            return AppEnvironment(
                bootstrapState: .failed(error.localizedDescription)
            )
        }
    }
}
