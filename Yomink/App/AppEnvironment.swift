import Combine
import Foundation

final class AppEnvironment: ObservableObject {
    let fileStore: AppFileStore?
    let database: AppDatabase?

    @Published var bootstrapError: String?

    private init(
        fileStore: AppFileStore?,
        database: AppDatabase?,
        bootstrapError: String?
    ) {
        self.fileStore = fileStore
        self.database = database
        self.bootstrapError = bootstrapError
    }

    static func live() -> AppEnvironment {
        do {
            let fileStore = try AppFileStore()
            let database = try AppDatabase(fileStore: fileStore)
            return AppEnvironment(
                fileStore: fileStore,
                database: database,
                bootstrapError: nil
            )
        } catch {
            return AppEnvironment(
                fileStore: nil,
                database: nil,
                bootstrapError: error.localizedDescription
            )
        }
    }
}
