import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var activeSheet: LibrarySheet?

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 16) {
                    if case let .failed(bootstrapError) = environment.bootstrapState {
                        bootstrapErrorView(bootstrapError)
                    }

                    emptyShelfView
                }
                .padding(24)
            }
            .navigationTitle("library.title")
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .librarySidebar:
                    LibrarySidebarView()
                case .addBook:
                    AddBookSidebarView()
                case .search:
                    GlobalSearchPlaceholderView()
                case .reader:
                    ReaderHostView()
                        .ignoresSafeArea()
                }
            }
        }
        .navigationViewStyle(.stack)
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

            Button("reader.placeholder.open") {
                activeSheet = .reader
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private enum LibrarySheet: String, Identifiable {
    case librarySidebar
    case addBook
    case search
    case reader

    var id: String { rawValue }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(AppEnvironment.preview())
    }
}
#endif
