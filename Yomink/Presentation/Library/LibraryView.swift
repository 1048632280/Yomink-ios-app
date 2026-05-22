import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isLibrarySidebarPresented = false
    @State private var isAddSidebarPresented = false
    @State private var isSearchPresented = false
    @State private var isReaderPresented = false

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 16) {
                    if let bootstrapError = environment.bootstrapError {
                        bootstrapErrorView(bootstrapError)
                    }

                    emptyShelfView
                }
                .padding(24)
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isLibrarySidebarPresented = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("打开分组")
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isSearchPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜索")

                    Button {
                        isAddSidebarPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加")
                }
            }
            .sheet(isPresented: $isLibrarySidebarPresented) {
                LibrarySidebarView()
            }
            .sheet(isPresented: $isAddSidebarPresented) {
                AddBookSidebarView()
            }
            .sheet(isPresented: $isSearchPresented) {
                GlobalSearchPlaceholderView()
            }
            .sheet(isPresented: $isReaderPresented) {
                ReaderHostView()
                    .ignoresSafeArea()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyShelfView: some View {
        VStack(spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 48, weight: .regular))
                .foregroundColor(.secondary)

            Text("还没有导入书籍")
                .font(.headline)

            Text("Phase 0 已完成工程初始化。下一阶段会接入文件导入、编码识别和书架数据。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button("打开阅读器占位页") {
                isReaderPresented = true
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bootstrapErrorView(_ message: String) -> some View {
        Text("初始化失败：\(message)")
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
                Text("全局搜索")
                    .font(.headline)
                Text("Phase 4 将实现书名模糊搜索和历史搜索气泡。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct LibraryView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryView()
            .environmentObject(AppEnvironment.live())
    }
}
#endif

