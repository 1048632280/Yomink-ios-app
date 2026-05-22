import Foundation

struct AppServices {
    let fileStore: AppFileStore
    let database: AppDatabase
    let libraryRepository: any LibraryRepository
}
