import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var viewModel = LibraryViewModel()
    @State private var activeSheet: LibrarySheet?
    @State private var isImportPickerPresented = false
    @State private var shouldOpenImportPickerAfterSheetDismisses = false

    var body: some View {
        NavigationView {
            ZStack {
                contentView
                    .padding(24)

                if viewModel.isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("library.title")
            .disabled(viewModel.isImporting)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        activeSheet = .librarySidebar
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel(Text("library.sidebar.open"))
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .search
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel(Text("library.search.open"))

                    Button {
                        activeSheet = .addBook
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("library.add.open"))
                }
            }
            .sheet(
                item: $activeSheet,
                onDismiss: presentPendingImportPicker
            ) { sheet in
                switch sheet {
                case .librarySidebar:
                    LibrarySidebarView()
                case .addBook:
                    AddBookSidebarView {
                        shouldOpenImportPickerAfterSheetDismisses = true
                        activeSheet = nil
                    }
                case .search:
                    GlobalSearchPlaceholderView()
                case let .reader(book):
                    ReaderHostView(book: book)
                        .ignoresSafeArea()
                }
            }
            .fileImporter(
                isPresented: $isImportPickerPresented,
                allowedContentTypes: [Self.txtContentType],
                allowsMultipleSelection: false
            ) { result in
                guard case let .ready(services) = environment.bootstrapState else {
                    return
                }
                viewModel.handleImportResult(
                    result,
                    importService: services.importService,
                    repository: services.libraryRepository
                )
            }
            .alert(
                "import.error.title",
                isPresented: Binding(
                    get: { viewModel.importErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.importErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("common.ok", role: .cancel) {
                    viewModel.importErrorMessage = nil
                }
            } message: {
                Text(viewModel.importErrorMessage ?? "")
            }
            .refreshable {
                if case let .ready(services) = environment.bootstrapState {
                    await viewModel.loadBooks(repository: services.libraryRepository)
                }
            }
            .task(id: bootstrapTaskID) {
                if case let .ready(services) = environment.bootstrapState {
                    await viewModel.loadBooks(repository: services.libraryRepository)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var contentView: some View {
        switch environment.bootstrapState {
        case let .failed(bootstrapError):
            VStack(spacing: 16) {
                bootstrapErrorView(bootstrapError)
                Spacer(minLength: 0)
            }
        case .ready:
            if viewModel.books.isEmpty {
                emptyShelfView
            } else {
                bookListView
            }
        }
    }

    private var bookListView: some View {
        List(viewModel.books) { book in
            Button {
                activeSheet = .reader(book)
            } label: {
                BookRowView(book: book)
            }
            .buttonStyle(.plain)
            .listRowInsets(
                EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            )
        }
        .listStyle(.plain)
        .padding(.horizontal, -24)
        .padding(.vertical, -24)
    }

    private var emptyShelfView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.secondary)

            Text("library.empty.title")
                .font(.headline)

            Text("library.empty.message")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button {
                isImportPickerPresented = true
            } label: {
                Label("add.import.file", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                Text("import.progress.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
    }

    private var bootstrapTaskID: String {
        switch environment.bootstrapState {
        case .ready:
            return "ready"
        case let .failed(message):
            return "failed-\(message)"
        }
    }

    private func bootstrapErrorView(_ message: String) -> some View {
        Text(String(format: NSLocalizedString("bootstrap.error.message", comment: ""), message))
            .font(.footnote)
            .foregroundColor(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
    }

    private func presentPendingImportPicker() {
        guard shouldOpenImportPickerAfterSheetDismisses else {
            return
        }
        shouldOpenImportPickerAfterSheetDismisses = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isImportPickerPresented = true
        }
    }

    private static let txtContentType = UTType(
        filenameExtension: "txt",
        conformingTo: .plainText
    ) ?? .plainText
}

@MainActor
private final class LibraryViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var isImporting = false
    @Published var importErrorMessage: String?
    private var currentImportTask: Task<Void, Never>?

    func loadBooks(repository: any LibraryRepository) async {
        guard !isImporting else {
            return
        }

        do {
            books = try await repository.fetchBooks()
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    func handleImportResult(
        _ result: Result<[URL], Error>,
        importService: ImportService,
        repository: any LibraryRepository
    ) {
        guard !isImporting else {
            return
        }

        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }
            importBook(
                from: url,
                importService: importService,
                repository: repository
            )
        case let .failure(error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importBook(
        from url: URL,
        importService: ImportService,
        repository: any LibraryRepository
    ) {
        isImporting = true
        currentImportTask = Task {
            do {
                _ = try await importService.importBook(from: url)
                try Task.checkCancellation()
                books = try await repository.fetchBooks()
                currentImportTask = nil
            } catch {
                if !Task.isCancelled {
                    importErrorMessage = error.localizedDescription
                    currentImportTask = nil
                }
            }
            isImporting = false
            if Task.isCancelled {
                currentImportTask = nil
            }
        }
    }
}

private struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                Text(book.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    ProgressView(value: clampedProgress)
                        .frame(maxWidth: 120)

                    Text(progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var clampedProgress: Double {
        min(max(book.progressPercentage, 0), 1)
    }

    private var progressText: String {
        NumberFormatter.readingProgress.string(from: NSNumber(value: clampedProgress)) ?? "0%"
    }
}

private extension NumberFormatter {
    static let readingProgress: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private struct GlobalSearchPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("search.title")
                    .font(.headline)
                Text("search.placeholder.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("search.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum LibrarySheet: Identifiable {
    case librarySidebar
    case addBook
    case search
    case reader(Book)

    var id: String {
        switch self {
        case .librarySidebar:
            return "librarySidebar"
        case .addBook:
            return "addBook"
        case .search:
            return "search"
        case let .reader(book):
            return "reader-\(book.id.uuidString)"
        }
    }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(AppEnvironment.preview())
    }
}
#endif
