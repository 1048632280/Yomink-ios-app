import Combine
import Dispatch
import Foundation
import OSLog

final class AppEnvironment: ObservableObject {
    enum BootstrapState {
        case bootstrapping
        case ready(AppServices)
        case failed(String)
    }

    private static let logger = Logger(
        subsystem: "com.yomink.reader",
        category: "bootstrap"
    )

    @Published private(set) var bootstrapState: BootstrapState
    private let makeServices: () throws -> AppServices
    private var bootstrapGeneration = 0

    init(
        bootstrapState: BootstrapState,
        makeServices: @escaping () throws -> AppServices = AppEnvironment.makeLiveServices
    ) {
        self.bootstrapState = bootstrapState
        self.makeServices = makeServices
    }

    static func live() -> AppEnvironment {
        let environment = AppEnvironment(bootstrapState: .bootstrapping)
        environment.bootstrap()
        return environment
    }

    func retryBootstrap() {
        bootstrap()
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
            return AppEnvironment(
                bootstrapState: .ready(services),
                makeServices: {
                    services
                }
            )
        } catch {
            return AppEnvironment(
                bootstrapState: .failed(error.localizedDescription)
            )
        }
    }

    private func bootstrap() {
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        let makeServices = makeServices
        bootstrapState = .bootstrapping

        DispatchQueue.global(qos: .userInitiated).async {
            let startedAt = Date()
            let result = Result {
                try makeServices()
            }
            let elapsed = Date().timeIntervalSince(startedAt)

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.bootstrapGeneration == generation
                else {
                    return
                }

                switch result {
                case let .success(services):
                    Self.logger.info("Bootstrap completed in \(elapsed, privacy: .public) seconds")
                    self.bootstrapState = .ready(services)
                case let .failure(error):
                    Self.logger.error(
                        "Bootstrap failed in \(elapsed, privacy: .public) seconds: \(error.localizedDescription, privacy: .public)"
                    )
                    self.bootstrapState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func makeLiveServices() throws -> AppServices {
        let fileStore = try AppFileStore()
        let database = try AppDatabase(fileStore: fileStore)
        let repository = GRDBLibraryRepository(database: database)
        return AppServices(
            fileStore: fileStore,
            database: database,
            libraryRepository: repository,
            importService: ImportService(
                fileStore: fileStore,
                libraryRepository: repository
            )
        )
    }
}
