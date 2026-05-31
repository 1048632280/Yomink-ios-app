import Foundation

struct AppServices {
    let fileStore: AppFileStore
    let libraryRepository: any LibraryRepository
    let importService: ImportService
}
