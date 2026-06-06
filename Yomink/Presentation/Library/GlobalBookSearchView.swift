import Foundation
import SwiftUI
import UIKit

struct GlobalBookSearchView: View {
    @Environment(\.dismiss) private var dismiss

    private let repository: (any LibraryRepository)?
    private let sortOrder: LibrarySettings.SortOrder
    private let onOpenBook: (Book) -> Void

    @State private var keyword = ""
    @State private var results: [Book] = []
    @State private var historyItems: [SearchHistoryItem] = []
    @State private var errorMessage: String?
    @State private var searchFocusToken = 0
    @State private var searchTask: Task<Void, Never>?
    @State private var shouldSkipNextLiveSearch = false

    init(
        repository: (any LibraryRepository)?,
        sortOrder: LibrarySettings.SortOrder,
        onOpenBook: @escaping (Book) -> Void
    ) {
        self.repository = repository
        self.sortOrder = sortOrder
        self.onOpenBook = onOpenBook
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)

                FocusableSearchTextField(
                    text: $keyword,
                    placeholder: NSLocalizedString("search.field.placeholder", comment: ""),
                    focusToken: searchFocusToken
                ) {
                    performSearch(shouldSaveHistory: true)
                }
                .frame(height: SearchBarStyle.height)

                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        results = []
                        errorMessage = nil
                        searchTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(Text("search.clearInput"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: SearchBarStyle.height)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: SearchBarStyle.cornerRadius, style: .continuous))

            if shouldShowHistory {
                historySection
            }

            resultList
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationTitle("search.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .task {
            await reloadHistory()
        }
        .onChange(of: keyword) { _ in
            guard !shouldSkipNextLiveSearch else {
                shouldSkipNextLiveSearch = false
                return
            }
            scheduleLiveSearch()
        }
        .onAppear {
            focusSearchField()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
        .alert(
            "search.error.title",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("common.ok", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowHistory: Bool {
        trimmedKeyword.isEmpty && !historyItems.isEmpty
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("search.history.title")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button("search.history.clear") {
                    clearHistory()
                }
                .font(.footnote)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(historyItems) { item in
                        Button {
                            shouldSkipNextLiveSearch = item.keyword != keyword
                            keyword = item.keyword
                            performSearch(keyword: item.keyword, shouldSaveHistory: true)
                        } label: {
                            Text(verbatim: item.keyword)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if trimmedKeyword.isEmpty {
            Spacer(minLength: 0)
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "books.vertical")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary)
                Text("search.empty.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        } else {
            List(results) { book in
                Button {
                    onOpenBook(book)
                } label: {
                    BookRowView(
                        book: book,
                        isSelecting: false,
                        isSelected: false
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.white)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                )
            }
            .listStyle(.plain)
            .background(Color.white)
            .padding(.horizontal, -16)
        }
    }

    private func scheduleLiveSearch() {
        searchTask?.cancel()
        errorMessage = nil

        let keyword = trimmedKeyword
        guard !keyword.isEmpty else {
            results = []
            searchTask = nil
            return
        }

        searchTask = Task {
            await runSearch(keyword: keyword, shouldSaveHistory: false)
        }
    }

    private func performSearch(shouldSaveHistory: Bool) {
        performSearch(keyword: trimmedKeyword, shouldSaveHistory: shouldSaveHistory)
    }

    private func performSearch(keyword: String, shouldSaveHistory: Bool) {
        searchTask?.cancel()
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            errorMessage = nil
            searchTask = nil
            return
        }

        searchTask = Task {
            await runSearch(keyword: keyword, shouldSaveHistory: shouldSaveHistory)
        }
    }

    @MainActor
    private func runSearch(keyword: String, shouldSaveHistory: Bool) async {
        guard let repository,
              !keyword.isEmpty
        else {
            results = []
            return
        }

        do {
            if shouldSaveHistory {
                try await repository.saveSearchKeyword(keyword)
            }
            let searchResults = try await repository.searchBooks(
                keyword: keyword,
                sortOrder: sortOrder
            )

            guard !Task.isCancelled,
                  keyword == trimmedKeyword
            else {
                return
            }

            results = searchResults

            if shouldSaveHistory {
                await reloadHistory()
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reloadHistory() async {
        guard let repository else {
            historyItems = []
            return
        }

        do {
            historyItems = try await repository.fetchSearchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        guard let repository else {
            historyItems = []
            return
        }

        Task {
            do {
                try await repository.clearSearchHistory()
                historyItems = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + SearchBarStyle.focusDelay) {
            searchFocusToken += 1
        }
    }
}

private struct FocusableSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusToken: Int
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> SearchTextField {
        let textField = SearchTextField()
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.font = .preferredFont(forTextStyle: .body)
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.returnKeyType = .search
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .never
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: SearchTextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }
        textField.placeholder = placeholder

        guard focusToken != context.coordinator.lastFocusToken else {
            return
        }
        context.coordinator.lastFocusToken = focusToken
        textField.focusWhenReady()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onSubmit: () -> Void
        var lastFocusToken = 0

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return true
        }
    }

    final class SearchTextField: UITextField {
        private var needsFocus = false

        func focusWhenReady() {
            needsFocus = true
            requestFocusIfPossible()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            requestFocusIfPossible()
        }

        private func requestFocusIfPossible() {
            guard needsFocus,
                  window != nil,
                  !isFirstResponder
            else {
                return
            }

            needsFocus = false
            DispatchQueue.main.async { [weak self] in
                self?.becomeFirstResponder()
            }
        }
    }
}

private enum SearchBarStyle {
    static let height: CGFloat = 36
    static let cornerRadius: CGFloat = 10
    static let focusDelay: TimeInterval = 0.65
}
