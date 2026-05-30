import Foundation
import SwiftUI
import UIKit

struct LibraryGroupsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onGroupsChanged: (UUID?) -> Void

    @State private var groups: [BookGroup] = []
    @State private var books: [Book] = []
    @State private var isEditing = false
    @State private var groupNameEditor: GroupNameEditor?
    @State private var groupPendingDeletion: BookGroup?
    @State private var nameDraft = ""
    @State private var errorMessage: String?
    @State private var pressedGroupID: UUID?
    @State private var draggedGroupID: UUID?
    @State private var reorderStartIndex: Int?
    @State private var dragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0) {
                    DedicatedGroupListRow(
                        title: groupTitle(
                            name: NSLocalizedString("sidebar.ungrouped", comment: ""),
                            count: books.filter { $0.groupID == nil }.count
                        )
                    )

                    ForEach(groups) { group in
                        DedicatedGroupListRow(
                            title: groupTitle(
                                name: group.name,
                                count: books.filter { $0.groupID == group.id }.count
                            ),
                            showsDeleteControl: isEditing,
                            showsReorderControl: isEditing,
                            isPressed: pressedGroupID == group.id,
                            isDragging: draggedGroupID == group.id,
                            dragOffset: dragOffset(for: group),
                            deleteAction: {
                                groupPendingDeletion = group
                            },
                            reorderDragChanged: { translation in
                                reorderGroup(group, translation: translation)
                            },
                            reorderDragEnded: {
                                finishReordering()
                            }
                        )
                        .overlay {
                            if !isEditing {
                                NonBlockingLongPressRecognizer(
                                    isEnabled: true,
                                    onBegan: {
                                        pressedGroupID = group.id
                                    },
                                    onEnded: {
                                        pressedGroupID = nil
                                    },
                                    onRecognized: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                            pressedGroupID = nil
                                            beginRename(group)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGray6))
            .animation(.easeInOut(duration: 0.18), value: isEditing)

            if groupNameEditor != nil {
                groupNameOverlay
            }

            if groupPendingDeletion != nil {
                deleteConfirmationOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("groups.page.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("common.new") {
                    beginAdd()
                }

                Button(editButtonTitle) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditing.toggle()
                        pressedGroupID = nil
                    }
                }
            }
        }
        .task {
            await reloadGroups()
        }
        .alert(
            "groups.error.title",
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

    private var editTitle: LocalizedStringKey {
        groupNameEditor?.title ?? "groups.new"
    }

    private var editButtonTitle: LocalizedStringKey {
        isEditing ? "common.done" : "common.edit"
    }

    private var groupNameOverlay: some View {
        DedicatedPromptOverlay(
            title: editTitle,
            message: "groups.name.message",
            text: $nameDraft,
            placeholder: NSLocalizedString("groups.name.placeholder", comment: ""),
            confirmTitle: "common.save",
            confirmRole: nil,
            confirmAction: saveGroup,
            cancelAction: cancelEditing
        )
    }

    private var deleteConfirmationOverlay: some View {
        DedicatedConfirmationOverlay(
            title: "groups.delete.title",
            message: "groups.delete.message",
            confirmTitle: "library.delete",
            confirmRole: .destructive,
            confirmAction: deletePendingGroup,
            cancelAction: {
                groupPendingDeletion = nil
            }
        )
    }

    @MainActor
    private func reloadGroups() async {
        do {
            groups = try await repository.fetchGroups()
            books = try await repository.fetchBooks(scope: .all, sortOrder: .lastReadAt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginAdd() {
        nameDraft = ""
        groupNameEditor = .new
    }

    private func beginRename(_ group: BookGroup) {
        nameDraft = group.name
        groupNameEditor = .rename(group)
    }

    private func cancelEditing() {
        groupNameEditor = nil
        nameDraft = ""
    }

    private func saveGroup() {
        let editor = groupNameEditor
        let name = nameDraft

        Task {
            do {
                if case let .rename(group) = editor {
                    try await repository.renameGroup(id: group.id, name: name)
                } else {
                    _ = try await repository.createGroup(name: name)
                }
                cancelEditing()
                await reloadGroups()
                onGroupsChanged(nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingGroup() {
        guard let group = groupPendingDeletion else {
            return
        }

        Task {
            do {
                try await repository.deleteGroup(id: group.id)
                groupPendingDeletion = nil
                await reloadGroups()
                onGroupsChanged(group.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persistGroupOrder() {
        let ids = groups.map(\.id)

        Task {
            do {
                try await repository.reorderGroups(ids: ids)
                await reloadGroups()
                onGroupsChanged(nil)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reorderGroup(_ group: BookGroup, translation: CGSize) {
        dragTranslation = translation

        if draggedGroupID != group.id {
            draggedGroupID = group.id
            reorderStartIndex = groups.firstIndex(of: group)
        }

        guard let startIndex = reorderStartIndex,
              let currentIndex = groups.firstIndex(where: { $0.id == group.id })
        else {
            return
        }

        let offset = Int((translation.height / DedicatedPageStyle.rowHeight).rounded())
        let targetIndex = min(max(startIndex + offset, 0), max(groups.count - 1, 0))

        guard targetIndex != currentIndex else {
            return
        }

        withAnimation(DedicatedPageStyle.reorderAnimation) {
            groups.move(
                fromOffsets: IndexSet(integer: currentIndex),
                toOffset: targetIndex > currentIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    private func finishReordering() {
        guard draggedGroupID != nil else {
            return
        }

        withAnimation(DedicatedPageStyle.reorderAnimation) {
            draggedGroupID = nil
            reorderStartIndex = nil
            dragTranslation = .zero
        }
        persistGroupOrder()
    }

    private func dragOffset(for group: BookGroup) -> CGSize {
        guard draggedGroupID == group.id,
              let startIndex = reorderStartIndex,
              let currentIndex = groups.firstIndex(where: { $0.id == group.id })
        else {
            return .zero
        }

        let settledOffset = CGFloat(currentIndex - startIndex) * DedicatedPageStyle.rowHeight
        return CGSize(width: 0, height: dragTranslation.height - settledOffset)
    }

    private func groupTitle(name: String, count: Int) -> String {
        String(
            format: NSLocalizedString("sidebar.groupWithCount", comment: ""),
            name,
            count
        )
    }
}

private enum GroupNameEditor {
    case new
    case rename(BookGroup)

    var title: LocalizedStringKey {
        switch self {
        case .new:
            return "groups.new"
        case .rename:
            return "groups.rename"
        }
    }
}

private struct NonBlockingLongPressRecognizer: UIViewRepresentable {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onEnded: () -> Void
    let onRecognized: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.isRecognizerEnabled = isEnabled
        view.onBegan = onBegan
        view.onEnded = onEnded
        view.onRecognized = onRecognized
        view.isUserInteractionEnabled = isEnabled
    }

    final class TouchView: UIView {
        var isRecognizerEnabled = false
        var onBegan: () -> Void
        var onEnded: () -> Void
        var onRecognized: () -> Void
        private var startPoint: CGPoint?
        private var isPressing = false
        private var recognitionWorkItem: DispatchWorkItem?

        init() {
            onBegan = {}
            onEnded = {}
            onRecognized = {}
            super.init(frame: .zero)
            isMultipleTouchEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            guard isRecognizerEnabled,
                  let touch = touches.first
            else {
                return
            }

            startPoint = touch.location(in: self)
            isPressing = true
            onBegan()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      self.isPressing
                else {
                    return
                }
                self.onRecognized()
            }
            recognitionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            guard let startPoint,
                  let touch = touches.first
            else {
                return
            }

            let point = touch.location(in: self)
            let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
            if distance > 10 {
                cancelPress()
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            cancelPress()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            cancelPress()
        }

        private func cancelPress() {
            recognitionWorkItem?.cancel()
            recognitionWorkItem = nil
            startPoint = nil
            guard isPressing else {
                return
            }
            isPressing = false
            onEnded()
        }
    }
}

struct ReadingHistoryPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onOpenBook: (Book) -> Void

    @State private var historyItems: [ReadingHistoryItem] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            if historyItems.isEmpty {
                Text("history.empty.message")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReadingHistoryTableView(
                    items: $historyItems,
                    onOpenBook: onOpenBook,
                    onDelete: persistDeletedHistoryItem
                )
                .background(Color(.systemGray6))
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("add.reading.history")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("history.clear") {
                    clearHistory()
                }
                .disabled(historyItems.isEmpty)
            }
        }
        .task {
            await reloadHistory()
        }
        .alert(
            "history.error.title",
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

    @MainActor
    private func reloadHistory() async {
        do {
            historyItems = try await repository.fetchReadingHistory(limit: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearHistory() {
        Task {
            do {
                try await repository.clearReadingHistory()
                historyItems = []
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func persistDeletedHistoryItem(_ item: ReadingHistoryItem, originalIndex: Int) {
        Task {
            do {
                try await repository.deleteReadingHistory(bookID: item.book.id)
            } catch {
                historyItems.insert(item, at: min(originalIndex, historyItems.count))
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct RandomBookPickerPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let onOpenBook: (Book) -> Void

    @State private var groups: [BookGroup] = []
    @State private var books: [Book] = []
    @State private var selectedScopes: Set<RandomPickerScope> = []
    @State private var pickerState = RandomPickerState.default
    @State private var carouselBooks: [Book] = []
    @State private var carouselOffset: CGFloat = 0
    @State private var resultBook: Book?
    @State private var highlightedIndex: Int?
    @State private var isDrawing = false
    @State private var resetMessageID = UUID()
    @State private var showsCooldownResetMessage = false
    @State private var errorMessage: String?
    @State private var drawTask: Task<Void, Never>?
    @State private var drawGeneration = 0
    @State private var activeDrawBaseState = RandomPickerState.default
    @State private var showsScopePanel = false
    @State private var showsStatsPage = false

    private let cardWidth: CGFloat = 126
    private let cardHeight: CGFloat = 226
    private let cardSpacing: CGFloat = 12

    private var scopeOptions: [RandomPickerScope] {
        [.ungrouped] + groups.map { .group($0.id) }
    }

    private var selectedScopeList: [RandomPickerScope] {
        scopeOptions.filter { selectedScopes.contains($0) }
    }

    private var candidateBooks: [Book] {
        let scopes = selectedScopes
        guard !scopes.isEmpty else {
            return []
        }

        return books.filter { book in
            if book.groupID == nil,
               scopes.contains(.ungrouped) {
                return true
            }
            if let groupID = book.groupID,
               scopes.contains(.group(groupID)) {
                return true
            }
            return false
        }
    }

    private var recentBooks: [Book] {
        pickerState.recentBookIDs.compactMap { id in
            books.first { $0.id == id }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(.systemGray6)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    scopeSection
                    Spacer(minLength: 8)
                    carouselSection
                    Spacer(minLength: 8)
                    actionSection
                    Spacer(minLength: 8)
                    historySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                NavigationLink(
                    destination: RandomPickerStatsPage(
                        books: books,
                        pickerState: pickerState,
                        onOpenBook: onOpenBook
                    ),
                    isActive: $showsStatsPage
                ) {
                    EmptyView()
                }
                .hidden()
                .frame(width: 0, height: 0)

                if showsScopePanel {
                    scopePanelOverlay(maxHeight: proxy.size.height)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("randomPicker.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("randomPicker.stats.title") {
                    showsStatsPage = true
                }
            }
        }
        .task {
            await loadPickerData()
        }
        .onDisappear {
            drawTask?.cancel()
            drawTask = nil
        }
        .alert(
            "randomPicker.error.title",
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

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("randomPicker.scope.title")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(scopeSummaryText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    openScopePanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("randomPicker.scope.choose")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(isDrawing)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func scopePanelOverlay(maxHeight: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture {
                    closeScopePanel()
                }

            VStack(alignment: .leading, spacing: 14) {
                Capsule()
                    .fill(Color(.systemGray3))
                    .frame(width: 38, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("randomPicker.scope.title")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(scopeSummaryText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("common.done") {
                        closeScopePanel()
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 138), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(scopeOptions, id: \.storageKey) { scope in
                            Button {
                                toggleScope(scope)
                            } label: {
                                RandomPickerScopeChip(
                                    title: title(for: scope),
                                    count: bookCount(for: scope),
                                    isSelected: selectedScopes.contains(scope)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isDrawing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: min(maxHeight * 0.58, 480), alignment: .top)
            .background(Color.white)
            .clipShape(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: -6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .transition(.opacity)
        .zIndex(10)
    }

    private var scopeSummaryText: String {
        guard !selectedScopes.isEmpty else {
            return NSLocalizedString("randomPicker.scope.emptySummary", comment: "")
        }

        return String(
            format: NSLocalizedString("randomPicker.scope.selectedSummary", comment: ""),
            selectedScopes.count,
            candidateBooks.count
        )
    }

    private func openScopePanel() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            showsScopePanel = true
        }
    }

    private func closeScopePanel() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showsScopePanel = false
        }
    }

    private var carouselSection: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                ZStack {
                    if carouselBooks.isEmpty {
                        RandomPickerPlaceholderCard(
                            textKey: candidateBooks.isEmpty
                                ? "randomPicker.empty.message"
                                : "randomPicker.result.placeholder"
                        )
                        .frame(width: cardWidth, height: cardHeight)
                    } else {
                        HStack(spacing: cardSpacing) {
                            ForEach(Array(carouselBooks.enumerated()), id: \.offset) { index, book in
                                RandomPickerBookCard(
                                    book: book,
                                    isHighlighted: highlightedIndex == index
                                )
                                .frame(width: cardWidth, height: cardHeight)
                                .scaleEffect(highlightedIndex == index ? 1.08 : 1)
                                .shadow(
                                    color: highlightedIndex == index
                                        ? Color.accentColor.opacity(0.32)
                                        : Color.black.opacity(0.08),
                                    radius: highlightedIndex == index ? 18 : 8,
                                    x: 0,
                                    y: highlightedIndex == index ? 10 : 5
                                )
                            }
                        }
                        .offset(x: carouselOffset + (proxy.size.width - cardWidth) / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            Text("randomPicker.cooldownReset")
                .font(.caption.weight(.medium))
                .foregroundColor(.orange)
                .opacity(showsCooldownResetMessage ? 1 : 0)
                .padding(.bottom, 2)
        }
        .frame(height: cardHeight + 34)
        .padding(.vertical, 18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var actionSection: some View {
        if isDrawing {
            Button {
                skipAnimation()
            } label: {
                Text("randomPicker.action.skip")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
        } else if let resultBook {
            HStack(spacing: 12) {
                Button {
                    onOpenBook(resultBook)
                } label: {
                    Text("randomPicker.action.read")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    startDraw()
                } label: {
                    Text("randomPicker.action.redraw")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .disabled(candidateBooks.isEmpty)
            }
        } else {
            Button {
                startDraw()
            } label: {
                Text("randomPicker.action.draw")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(candidateBooks.isEmpty || selectedScopes.isEmpty)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("randomPicker.history.title")
                .font(.headline)
                .foregroundColor(.primary)

            if recentBooks.isEmpty {
                Text("randomPicker.history.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(recentBooks) { book in
                            Button {
                                onOpenBook(book)
                            } label: {
                                RandomPickerHistoryCard(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @MainActor
    private func loadPickerData() async {
        do {
            async let fetchedGroups = repository.fetchGroups()
            async let fetchedBooks = repository.fetchBooks(scope: .all, sortOrder: .lastReadAt)
            async let fetchedState = repository.fetchRandomPickerState()
            groups = try await fetchedGroups
            books = try await fetchedBooks
            pickerState = try await fetchedState
            applyPersistedScopes()
            pruneMissingPickerStateEntries()
            refreshCarouselSeed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyPersistedScopes() {
        let options = scopeOptions
        guard !options.isEmpty else {
            selectedScopes = []
            return
        }

        if let persistedScopes = pickerState.selectedScopes {
            let filtered = persistedScopes.filter { options.contains($0) }
            selectedScopes = filtered.isEmpty && !persistedScopes.isEmpty
                ? Set(options)
                : Set(filtered)
        } else {
            selectedScopes = Set(options)
        }
    }

    private func pruneMissingPickerStateEntries() {
        let bookIDs = Set(books.map(\.id))
        var nextState = pickerState
        nextState.recentBookIDs = nextState.recentBookIDs.filter { bookIDs.contains($0) }
        nextState.drawCounts = nextState.drawCounts.filter { entry in
            bookIDs.contains(entry.key) && entry.value > 0
        }
        nextState = nextState.normalized

        guard nextState != pickerState else {
            return
        }
        pickerState = nextState
        persistPickerState()
    }

    private func refreshCarouselSeed() {
        let sourceBooks = resultBook.map { [$0] } ?? Array(candidateBooks.prefix(8))
        carouselBooks = sourceBooks
        highlightedIndex = resultBook == nil ? nil : 0
        carouselOffset = 0
    }

    private func toggleScope(_ scope: RandomPickerScope) {
        if selectedScopes.contains(scope) {
            selectedScopes.remove(scope)
        } else {
            selectedScopes.insert(scope)
        }
        resultBook = nil
        highlightedIndex = nil
        refreshCarouselSeed()
        persistPickerState()
    }

    private func title(for scope: RandomPickerScope) -> String {
        switch scope {
        case .ungrouped:
            return NSLocalizedString("randomPicker.scope.ungrouped", comment: "")
        case let .group(id):
            return groups.first { $0.id == id }?.name
                ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
        }
    }

    private func bookCount(for scope: RandomPickerScope) -> Int {
        books.filter { book in
            switch scope {
            case .ungrouped:
                return book.groupID == nil
            case let .group(id):
                return book.groupID == id
            }
        }.count
    }

    private func startDraw() {
        drawTask?.cancel()
        drawGeneration += 1
        let generation = drawGeneration
        let candidates = candidateBooks
        guard !candidates.isEmpty else {
            return
        }

        var state = pickerState.normalized
        let candidateIDs = Set(candidates.map(\.id))
        var availableBooks = candidates.filter { !state.recentBookIDs.contains($0.id) }
        if availableBooks.isEmpty {
            state.recentBookIDs.removeAll { candidateIDs.contains($0) }
            availableBooks = candidates
            showCooldownResetMessage()
        }

        guard let winner = availableBooks.randomElement() else {
            return
        }

        resultBook = nil
        highlightedIndex = nil
        isDrawing = true

        let sequence = animationSequence(candidates: candidates, winner: winner)
        let targetIndex = sequence.count - 1
        activeDrawBaseState = state.normalized
        carouselBooks = sequence
        carouselOffset = 0

        drawTask = Task { @MainActor in
            await runDrawAnimation(
                generation: generation,
                winner: winner,
                targetIndex: targetIndex,
                baseState: activeDrawBaseState
            )
        }
    }

    @MainActor
    private func runDrawAnimation(
        generation: Int,
        winner: Book,
        targetIndex: Int,
        baseState: RandomPickerState
    ) async {
        let stride = cardWidth + cardSpacing
        let targetOffset = -stride * CGFloat(targetIndex)
        let overshootOffset = targetOffset - min(18, stride * 0.14)
        let duration: TimeInterval = 2.72
        let startDate = Date()

        while shouldContinueDraw(generation) {
            let elapsed = Date().timeIntervalSince(startDate)
            let progress = min(max(elapsed / duration, 0), 1)
            let easedProgress = drawAnimationProgress(progress)

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                carouselOffset = overshootOffset * CGFloat(easedProgress)
            }

            if progress >= 1 {
                break
            }

            try? await Task.sleep(nanoseconds: 16_000_000)
        }

        guard shouldContinueDraw(generation) else {
            return
        }

        withAnimation(.interpolatingSpring(stiffness: 210, damping: 18)) {
            carouselOffset = targetOffset
            highlightedIndex = targetIndex
        }
        try? await Task.sleep(nanoseconds: 260_000_000)
        guard shouldContinueDraw(generation) else {
            return
        }

        finishDraw(
            winner: winner,
            targetIndex: targetIndex,
            baseState: baseState
        )
    }

    private func drawAnimationProgress(_ progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        return clampedProgress * clampedProgress * clampedProgress
            * (clampedProgress * (clampedProgress * 6 - 15) + 10)
    }

    private func skipAnimation() {
        guard let winner = carouselBooks.last else {
            return
        }
        let targetIndex = max(carouselBooks.count - 1, 0)
        let state = activeDrawBaseState.normalized
        drawTask?.cancel()
        drawTask = nil
        drawGeneration += 1
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            carouselOffset = -(cardWidth + cardSpacing) * CGFloat(targetIndex)
            highlightedIndex = targetIndex
        }
        finishDraw(
            winner: winner,
            targetIndex: targetIndex,
            baseState: state
        )
    }

    private func shouldContinueDraw(_ generation: Int) -> Bool {
        !Task.isCancelled && drawGeneration == generation
    }

    private func finishDraw(
        winner: Book,
        targetIndex: Int,
        baseState: RandomPickerState
    ) {
        highlightedIndex = targetIndex
        resultBook = winner
        isDrawing = false
        drawTask = nil

        var nextState = baseState
        nextState.selectedScopes = selectedScopeList
        nextState.recentBookIDs.removeAll { $0 == winner.id }
        nextState.recentBookIDs.insert(winner.id, at: 0)
        nextState.recentBookIDs = Array(nextState.recentBookIDs.prefix(RandomPickerState.cooldownLimit))
        nextState.drawCounts[winner.id, default: 0] += 1
        pickerState = nextState.normalized
        persistPickerState()
    }

    private func animationSequence(candidates: [Book], winner: Book) -> [Book] {
        var sequence: [Book] = []
        let spinCount = max(18, min(30, candidates.count * 6))
        for _ in 0..<spinCount {
            if let book = candidates.randomElement() {
                sequence.append(book)
            }
        }
        sequence.append(winner)
        return sequence
    }

    private func showCooldownResetMessage() {
        resetMessageID = UUID()
        let messageID = resetMessageID
        withAnimation(.easeInOut(duration: 0.18)) {
            showsCooldownResetMessage = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            guard resetMessageID == messageID else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                showsCooldownResetMessage = false
            }
        }
    }

    private func persistPickerState() {
        var state = pickerState
        state.selectedScopes = selectedScopeList
        pickerState = state.normalized
        let repository = repository
        let nextState = pickerState
        Task {
            do {
                try await repository.saveRandomPickerState(nextState)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct RandomPickerStatsPage: View {
    @Environment(\.dismiss) private var dismiss

    let books: [Book]
    let pickerState: RandomPickerState
    let onOpenBook: (Book) -> Void

    private var rankedBooks: [RandomPickerRankedBook] {
        let bookLookup = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        return pickerState.drawCounts.compactMap { entry -> RandomPickerCountedBook? in
            guard entry.value > 0,
                  let book = bookLookup[entry.key]
            else {
                return nil
            }
            return RandomPickerCountedBook(book: book, count: entry.value)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let titleOrder = lhs.book.title.localizedStandardCompare(rhs.book.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.book.id.uuidString < rhs.book.id.uuidString
        }
        .prefix(10)
        .enumerated()
        .map { index, item in
            RandomPickerRankedBook(rank: index + 1, book: item.book, count: item.count)
        }
    }

    private var remainingRankedBooks: [RandomPickerRankedBook] {
        Array(rankedBooks.dropFirst(3))
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            if rankedBooks.isEmpty {
                Text("randomPicker.stats.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        podiumSection
                        leaderboardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("randomPicker.stats.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
    }

    private var podiumSection: some View {
        HStack(alignment: .bottom, spacing: 10) {
            podiumColumn(
                item: rankedBook(forRank: 2),
                rank: 2,
                width: 92,
                coverHeight: 112,
                baseHeight: 58
            )
            podiumColumn(
                item: rankedBook(forRank: 1),
                rank: 1,
                width: 110,
                coverHeight: 140,
                baseHeight: 74
            )
            podiumColumn(
                item: rankedBook(forRank: 3),
                rank: 3,
                width: 92,
                coverHeight: 104,
                baseHeight: 50
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    private func rankedBook(forRank rank: Int) -> RandomPickerRankedBook? {
        rankedBooks.first { $0.rank == rank }
    }

    @ViewBuilder
    private func podiumColumn(
        item: RandomPickerRankedBook?,
        rank: Int,
        width: CGFloat,
        coverHeight: CGFloat,
        baseHeight: CGFloat
    ) -> some View {
        VStack(spacing: 8) {
            if let item {
                Button {
                    onOpenBook(item.book)
                } label: {
                    VStack(spacing: 7) {
                        RandomPickerCoverView(
                            title: item.book.title,
                            initialFontSize: rank == 1 ? 40 : 32
                        )
                        .frame(width: coverHeight * 0.75, height: coverHeight)
                        .shadow(
                            color: rank == 1
                                ? Color.accentColor.opacity(0.28)
                                : Color.black.opacity(0.08),
                            radius: rank == 1 ? 14 : 8,
                            x: 0,
                            y: rank == 1 ? 8 : 5
                        )

                        Text(displayTitle(for: item.book))
                            .font(rank == 1 ? .subheadline.weight(.semibold) : .caption.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: width)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: width, height: coverHeight + 42)
            }

            if let item {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(rank == 1 ? Color.accentColor.opacity(0.2) : Color.white)

                    VStack(spacing: 3) {
                        Text(verbatim: "\(rank)")
                            .font(.system(size: rank == 1 ? 22 : 18, weight: .bold))
                            .foregroundColor(rank == 1 ? .accentColor : .primary)

                        Text(countText(item.count))
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(width: width, height: baseHeight)
            } else {
                Color.clear
                    .frame(width: width, height: baseHeight)
            }
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        if !remainingRankedBooks.isEmpty {
            VStack(spacing: 0) {
                ForEach(remainingRankedBooks) { item in
                    RandomPickerStatsRow(
                        item: item,
                        countText: countText(item.count),
                        onOpenBook: onOpenBook
                    )

                    if item.id != remainingRankedBooks.last?.id {
                        DedicatedPageStyle.separator
                            .padding(.leading, 76)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func displayTitle(for book: Book) -> String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private func countText(_ count: Int) -> String {
        String(
            format: NSLocalizedString("randomPicker.stats.count", comment: ""),
            count
        )
    }
}

private struct RandomPickerCountedBook: Equatable {
    let book: Book
    let count: Int
}

private struct RandomPickerRankedBook: Identifiable, Equatable {
    let rank: Int
    let book: Book
    let count: Int

    var id: UUID {
        book.id
    }
}

private struct RandomPickerStatsRow: View {
    let item: RandomPickerRankedBook
    let countText: String
    let onOpenBook: (Book) -> Void

    var body: some View {
        Button {
            onOpenBook(item.book)
        } label: {
            HStack(spacing: 12) {
                Text(verbatim: "\(item.rank)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24)

                RandomPickerCoverView(title: item.book.title, initialFontSize: 22)
                    .frame(width: 42, height: 56)

                Text(displayTitle)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(countText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        let trimmed = item.book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

private struct RandomPickerScopeChip: View {
    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .accentColor : Color(.systemGray3))

            Text(verbatim: title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(
                String(
                    format: NSLocalizedString("randomPicker.scope.count", comment: ""),
                    count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        }
    }
}

private struct RandomPickerBookCard: View {
    let book: Book
    let isHighlighted: Bool
    private let coverWidth: CGFloat = 106

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RandomPickerCoverView(title: displayTitle, initialFontSize: 42)
                .frame(width: coverWidth, height: coverWidth * 4.0 / 3.0)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: RandomPickerCoverStyle.cornerRadius)
                        .stroke(
                            isHighlighted ? Color.accentColor.opacity(0.65) : Color.clear,
                            lineWidth: 2
                        )
                }

            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(progressText)
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var progressText: String {
        NumberFormatter.dedicatedReadingProgress.string(
            from: NSNumber(value: min(max(book.progressPercentage, 0), 1))
        ) ?? "0%"
    }
}

private struct RandomPickerPlaceholderCard: View {
    let textKey: LocalizedStringKey

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay {
                Text(textKey)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
    }
}

private struct RandomPickerHistoryCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RandomPickerCoverView(title: displayTitle, initialFontSize: 24)
                .frame(width: 50, height: 50 * 4.0 / 3.0)

            Text(displayTitle)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: 66, alignment: .leading)
        }
        .frame(width: 66, height: 100, alignment: .topLeading)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

private struct RandomPickerCoverView: View {
    let title: String
    let initialFontSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: RandomPickerCoverStyle.cornerRadius, style: .continuous)
            .fill(RandomPickerCoverStyle.background)
            .overlay {
                Text(verbatim: coverInitial)
                    .font(.system(size: initialFontSize, weight: .semibold))
                    .foregroundColor(RandomPickerCoverStyle.coverText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
    }

    private var coverInitial: String {
        title.dedicatedFirstBookCoverCharacter
            .map(String.init)
            ?? NSLocalizedString("library.cover.fallbackInitial", comment: "")
    }
}

private enum RandomPickerCoverStyle {
    static let cornerRadius: CGFloat = 5
    static let background = Color(.systemGray5)
    static let coverText = Color(.darkGray).opacity(0.62)
}

struct LibrarySettingsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let fileStore: AppFileStore
    let onOpenBook: (Book) -> Void
    let onLibraryChanged: () -> Void
    let onChange: (LibrarySettings) -> Void

    @State private var settings: LibrarySettings
    @State private var errorMessage: String?

    init(
        repository: any LibraryRepository,
        fileStore: AppFileStore,
        settings: LibrarySettings,
        onOpenBook: @escaping (Book) -> Void,
        onLibraryChanged: @escaping () -> Void,
        onChange: @escaping (LibrarySettings) -> Void
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.onOpenBook = onOpenBook
        self.onLibraryChanged = onLibraryChanged
        self.onChange = onChange
        _settings = State(initialValue: settings)
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    settingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
            .background(Color(.systemGray6))
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("settings.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .onChange(of: settings) { nextSettings in
            onChange(nextSettings)
            persistSettings(nextSettings)
        }
        .alert(
            "settings.error.title",
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

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                SettingsSortOrderPage(selection: $settings.sortOrder)
            } label: {
                SettingsListRow(
                    title: "settings.sortOrder",
                    value: settings.sortOrder.localizedTitle
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                SettingsViewModePage(selection: $settings.viewMode)
            } label: {
                SettingsListRow(
                    title: "settings.viewMode",
                    value: settings.viewMode.localizedTitle
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                StorageManagementPage(
                    repository: repository,
                    fileStore: fileStore,
                    onOpenBook: onOpenBook,
                    onLibraryChanged: onLibraryChanged
                )
            } label: {
                SettingsListRow(
                    title: "storage.title",
                    value: "settings.storage.open"
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func persistSettings(_ settings: LibrarySettings) {
        Task {
            do {
                try await repository.saveLibrarySettings(settings)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct StorageManagementPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let fileStore: AppFileStore
    let onOpenBook: (Book) -> Void
    let onLibraryChanged: () -> Void

    @State private var snapshot: StorageUsageSnapshot?
    @State private var sort: StorageBookSort = .size
    @State private var filter: StorageBookFilter = .all
    @State private var isLoading = true
    @State private var errorTitle: LocalizedStringKey = "storage.error.title"
    @State private var errorMessage: String?
    @State private var exportPayload: StorageExportPayload?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    if let snapshot {
                        StorageUsageChartCard(snapshot: snapshot)
                        StorageDashboardCard(snapshot: snapshot)
                        StorageBookManagementCard(
                            books: snapshot.books,
                            groups: snapshot.groups,
                            sort: $sort,
                            filter: $filter,
                            onOpenBook: onOpenBook,
                            onExportBook: exportBook,
                            onDeleteBook: deleteBook
                        )
                    } else {
                        StorageLoadingCard(isLoading: isLoading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .refreshable {
                await reloadStorage()
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("storage.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .task {
            await reloadStorage()
        }
        .sheet(item: $exportPayload) { payload in
            ActivityPresenter(activityItems: [payload.url as Any])
        }
        .alert(
            errorTitle,
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

    @MainActor
    private func reloadStorage() async {
        isLoading = true
        do {
            async let fetchedBooks = repository.fetchBooks(scope: .all, sortOrder: .lastReadAt)
            async let fetchedGroups = repository.fetchGroups()
            let books = try await fetchedBooks
            let groups = try await fetchedGroups
            snapshot = await StorageUsageScanner.snapshot(
                fileStore: fileStore,
                books: books,
                groups: groups
            )
        } catch {
            errorTitle = "storage.error.title"
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func exportBook(_ book: Book) {
        do {
            let url = try StorageBookExporter.exportURL(for: book, fileStore: fileStore)
            exportPayload = StorageExportPayload(url: url)
        } catch {
            errorTitle = "library.export.error.title"
            errorMessage = error.localizedDescription
        }
    }

    private func deleteBook(_ book: Book) {
        Task {
            do {
                try fileStore.removeBookFiles(id: book.id)
                try await repository.deleteBook(id: book.id)
                await reloadStorage()
                await MainActor.run {
                    onLibraryChanged()
                }
            } catch {
                await MainActor.run {
                    errorTitle = "library.delete.error.title"
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct StorageUsageChartCard: View {
    let snapshot: StorageUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("storage.usage.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 18) {
                StorageDonutChart(categories: snapshot.categories)
                    .frame(width: 132, height: 132)
                    .overlay {
                        VStack(spacing: 3) {
                            Text(StorageByteCountFormatter.string(from: snapshot.totalBytes))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.64)
                                .lineLimit(1)

                            Text("storage.total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }

                VStack(spacing: 8) {
                    ForEach(snapshot.categories) { category in
                        StorageLegendRow(category: category)
                    }
                }
            }
        }
        .storageCardStyle()
    }
}

private struct StorageDonutChart: View {
    let categories: [StorageUsageCategory]

    private var visibleCategories: [StorageUsageCategory] {
        categories.filter { $0.bytes > 0 }
    }

    private var totalBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 18)

            if totalBytes > 0 {
                ForEach(chartSlices) { slice in
                    Circle()
                        .trim(from: CGFloat(slice.start), to: CGFloat(slice.end))
                        .stroke(
                            slice.category.kind.color,
                            style: StrokeStyle(lineWidth: 18, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
    }

    private var chartSlices: [StorageDonutSlice] {
        guard totalBytes > 0 else {
            return []
        }

        var start = 0.0
        return visibleCategories.map { category in
            let fraction = Double(category.bytes) / Double(totalBytes)
            let slice = StorageDonutSlice(
                category: category,
                start: start,
                end: min(start + fraction, 1)
            )
            start += fraction
            return slice
        }
    }
}

private struct StorageLegendRow: View {
    let category: StorageUsageCategory

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(category.kind.color)
                .frame(width: 9, height: 9)

            Text(category.kind.titleKey)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(verbatim: StorageByteCountFormatter.string(from: category.bytes))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

private struct StorageDashboardCard: View {
    let snapshot: StorageUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("storage.dashboard.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 12) {
                StorageMetricTile(
                    title: "storage.dashboard.books",
                    value: "\(snapshot.bookCount)"
                )
                StorageMetricTile(
                    title: "storage.dashboard.total",
                    value: StorageByteCountFormatter.string(from: snapshot.totalBytes)
                )
            }
        }
        .storageCardStyle()
    }
}

private struct StorageMetricTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(verbatim: value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StorageBookManagementCard: View {
    let books: [StorageBookUsage]
    let groups: [BookGroup]
    @Binding var sort: StorageBookSort
    @Binding var filter: StorageBookFilter
    let onOpenBook: (Book) -> Void
    let onExportBook: (Book) -> Void
    let onDeleteBook: (Book) -> Void

    private var visibleBooks: [StorageBookUsage] {
        let now = Date()
        return books
            .filter { filter.includes($0, groups: groups, now: now) }
            .sorted { sort.areInIncreasingOrder($0, $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("storage.books.title")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 10) {
                StorageSortMenu(sort: $sort)
                StorageFilterMenu(
                    filter: $filter,
                    groups: groups
                )
            }

            if visibleBooks.isEmpty {
                Text("storage.books.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 86, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleBooks.enumerated()), id: \.element.id) { index, book in
                        NavigationLink {
                            StorageBookDetailPage(
                                bookUsage: book,
                                groups: groups,
                                onOpenBook: onOpenBook,
                                onExportBook: onExportBook,
                                onDeleteBook: onDeleteBook
                            )
                        } label: {
                            StorageBookUsageRow(book: book)
                        }
                        .buttonStyle(.plain)

                        if index < visibleBooks.count - 1 {
                            SettingsPageStyle.separator
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .storageCardStyle()
    }
}

private struct StorageSortMenu: View {
    @Binding var sort: StorageBookSort

    var body: some View {
        Menu {
            ForEach(StorageBookSort.allCases, id: \.self) { option in
                Button {
                    sort = option
                } label: {
                    if sort == option {
                        Label(option.titleKey, systemImage: "checkmark")
                    } else {
                        Text(option.titleKey)
                    }
                }
            }
        } label: {
            StorageSelectorLabel(
                title: "storage.sort.title",
                value: sort.titleKey,
                systemImage: "arrow.up.arrow.down"
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StorageFilterMenu: View {
    @Binding var filter: StorageBookFilter
    let groups: [BookGroup]

    var body: some View {
        Menu {
            Button {
                filter = .all
            } label: {
                if filter == .all {
                    Label("storage.filter.all", systemImage: "checkmark")
                } else {
                    Text("storage.filter.all")
                }
            }

            Button {
                filter = .ungrouped
            } label: {
                if filter == .ungrouped {
                    Label("sidebar.ungrouped", systemImage: "checkmark")
                } else {
                    Text("sidebar.ungrouped")
                }
            }

            ForEach(groups) { group in
                Button {
                    filter = .group(group.id)
                } label: {
                    if filter == .group(group.id) {
                        Label {
                            Text(verbatim: group.name)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(verbatim: group.name)
                    }
                }
            }

            Button {
                filter = .unread
            } label: {
                if filter == .unread {
                    Label("storage.filter.unread", systemImage: "checkmark")
                } else {
                    Text("storage.filter.unread")
                }
            }

            Button {
                filter = .longUnread
            } label: {
                if filter == .longUnread {
                    Label("storage.filter.longUnread", systemImage: "checkmark")
                } else {
                    Text("storage.filter.longUnread")
                }
            }
        } label: {
            StorageSelectorLabel(
                title: "storage.filter.title",
                value: filter.title(groups: groups),
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StorageSelectorLabel: View {
    let title: LocalizedStringKey
    let value: Text
    let systemImage: String

    init(
        title: LocalizedStringKey,
        value: LocalizedStringKey,
        systemImage: String
    ) {
        self.title = title
        self.value = Text(value)
        self.systemImage = systemImage
    }

    init(
        title: LocalizedStringKey,
        value: String,
        systemImage: String
    ) {
        self.title = title
        self.value = Text(verbatim: value)
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                value
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StorageBookUsageRow: View {
    let book: StorageBookUsage

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: displayTitle)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(verbatim: StorageByteCountFormatter.string(from: book.bytes))
                .font(.body.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.white)
    }

    private var displayTitle: String {
        let trimmed = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }
}

private struct StorageBookDetailPage: View {
    @Environment(\.dismiss) private var dismiss

    let bookUsage: StorageBookUsage
    let groups: [BookGroup]
    let onOpenBook: (Book) -> Void
    let onExportBook: (Book) -> Void
    let onDeleteBook: (Book) -> Void

    @State private var showsDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    detailCard
                    actionCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("storage.book.detail.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .alert(
            "storage.book.delete.title",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("storage.book.delete.action", role: .destructive) {
                dismiss()
                onDeleteBook(bookUsage.book)
            }
        } message: {
            Text("storage.book.delete.message")
        }
    }

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)
                .padding(.bottom, 12)

            StorageBookDetailRow(
                title: "storage.book.size",
                value: StorageByteCountFormatter.string(from: bookUsage.bytes)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.importedAt",
                value: StorageDateFormatter.string(from: bookUsage.importedAt)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.lastReadAt",
                value: bookUsage.lastReadAt.map { StorageDateFormatter.string(from: $0) }
                    ?? NSLocalizedString("storage.book.neverRead", comment: "")
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.progress",
                value: StorageProgressFormatter.string(from: bookUsage.progressPercentage)
            )
            SettingsPageStyle.separator

            StorageBookDetailRow(
                title: "storage.book.group",
                value: groupName
            )
        }
        .storageCardStyle()
    }

    private var actionCard: some View {
        VStack(spacing: 0) {
            Button {
                onOpenBook(bookUsage.book)
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.read",
                    systemImage: "book",
                    tint: .accentColor
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            Button {
                onExportBook(bookUsage.book)
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.export",
                    systemImage: "square.and.arrow.up",
                    tint: .accentColor
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                StorageBookActionRow(
                    title: "storage.book.action.delete",
                    systemImage: "trash",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayTitle: String {
        let trimmed = bookUsage.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : trimmed
    }

    private var groupName: String {
        guard let groupID = bookUsage.groupID else {
            return NSLocalizedString("sidebar.ungrouped", comment: "")
        }
        return groups.first { $0.id == groupID }?.name
            ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
    }
}

private struct StorageBookDetailRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.secondary)

            Spacer(minLength: 16)

            Text(verbatim: value)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }
}

private struct StorageBookActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 22)

            Text(title)
                .font(.body)
                .foregroundColor(tint)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private struct StorageLoadingCard: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if isLoading {
                ProgressView()
                Text("storage.loading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .storageCardStyle()
    }
}

private enum StorageUsageScanner {
    static func snapshot(
        fileStore: AppFileStore,
        books: [Book],
        groups: [BookGroup]
    ) async -> StorageUsageSnapshot {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let bookUsages = books.map { book in
                StorageBookUsage(
                    book: book,
                    bytes: Self.contentSize(for: book, fileStore: fileStore, fileManager: fileManager)
                )
            }

            let txtBytes = bookUsages.reduce(Int64(0)) { $0 + $1.bytes }
            let booksDirectoryBytes = Self.directorySize(at: fileStore.booksURL, fileManager: fileManager)
            let documentsBytes = Self.directorySize(at: fileStore.documentsURL, fileManager: fileManager)
            let applicationSupportBytes = Self.directorySize(
                at: fileStore.applicationSupportURL,
                fileManager: fileManager
            )
            let databaseBytes = Self.databaseSize(fileStore: fileStore, fileManager: fileManager)
            let temporaryExportBytes = Self.directorySize(
                at: Self.temporaryExportURL(fileManager: fileManager),
                fileManager: fileManager
            )
            let indexCacheBytes = max(0, booksDirectoryBytes - txtBytes)
                + max(0, applicationSupportBytes - databaseBytes)
            let otherBytes = max(0, documentsBytes - booksDirectoryBytes)

            let categories = [
                StorageUsageCategory(kind: .txt, bytes: txtBytes),
                StorageUsageCategory(kind: .database, bytes: databaseBytes),
                StorageUsageCategory(kind: .temporaryExport, bytes: temporaryExportBytes),
                StorageUsageCategory(kind: .indexCache, bytes: indexCacheBytes),
                StorageUsageCategory(kind: .other, bytes: otherBytes)
            ]

            return StorageUsageSnapshot(
                categories: categories,
                books: bookUsages,
                groups: groups
            )
        }.value
    }

    private static func contentSize(
        for book: Book,
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        guard let url = try? fileStore.url(forRelativePath: book.sourcePath) else {
            return 0
        }
        return fileSize(at: url, fileManager: fileManager)
    }

    private static func databaseSize(
        fileStore: AppFileStore,
        fileManager: FileManager
    ) -> Int64 {
        [
            fileStore.databaseURL,
            URL(fileURLWithPath: fileStore.databaseURL.path + "-wal"),
            URL(fileURLWithPath: fileStore.databaseURL.path + "-shm")
        ].reduce(Int64(0)) { result, url in
            result + fileSize(at: url, fileManager: fileManager)
        }
    }

    private static func temporaryExportURL(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("YominkExports", isDirectory: true)
    }

    private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                    .fileSizeKey
                ]
              )
        else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
            ]),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
        return total
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
                .fileSizeKey
              ])
        else {
            return 0
        }
        return Int64(
            values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
        )
    }
}

private struct StorageUsageSnapshot: Sendable {
    let categories: [StorageUsageCategory]
    let books: [StorageBookUsage]
    let groups: [BookGroup]

    var totalBytes: Int64 {
        categories.reduce(Int64(0)) { $0 + $1.bytes }
    }

    var bookCount: Int {
        books.count
    }
}

private struct StorageUsageCategory: Identifiable, Sendable {
    let kind: StorageUsageKind
    let bytes: Int64

    var id: String {
        kind.rawValue
    }
}

private enum StorageUsageKind: String, Sendable {
    case txt
    case database
    case temporaryExport
    case indexCache
    case other

    var titleKey: LocalizedStringKey {
        switch self {
        case .txt:
            return "storage.category.txt"
        case .database:
            return "storage.category.database"
        case .temporaryExport:
            return "storage.category.temporaryExport"
        case .indexCache:
            return "storage.category.indexCache"
        case .other:
            return "storage.category.other"
        }
    }

    var color: Color {
        switch self {
        case .txt:
            return Color(red: 0.20, green: 0.45, blue: 0.78)
        case .database:
            return Color(red: 0.28, green: 0.58, blue: 0.34)
        case .temporaryExport:
            return Color(red: 0.84, green: 0.52, blue: 0.22)
        case .indexCache:
            return Color(red: 0.48, green: 0.38, blue: 0.70)
        case .other:
            return Color(.systemGray3)
        }
    }
}

private struct StorageDonutSlice: Identifiable {
    let category: StorageUsageCategory
    let start: Double
    let end: Double

    var id: String {
        category.id
    }
}

private struct StorageBookUsage: Identifiable, Sendable {
    let book: Book
    let bytes: Int64

    var id: UUID {
        book.id
    }

    var title: String {
        book.title
    }

    var groupID: UUID? {
        book.groupID
    }

    var importedAt: Date {
        book.importedAt
    }

    var lastReadAt: Date? {
        book.lastReadAt
    }

    var progressPercentage: Double {
        book.progressPercentage
    }

    var isUnread: Bool {
        progressPercentage <= 0.0001
    }
}

private enum StorageBookSort: CaseIterable, Hashable {
    case size
    case lastReadAt
    case importedAt

    var titleKey: LocalizedStringKey {
        switch self {
        case .size:
            return "storage.sort.size"
        case .lastReadAt:
            return "storage.sort.lastReadAt"
        case .importedAt:
            return "storage.sort.importedAt"
        }
    }

    func areInIncreasingOrder(_ lhs: StorageBookUsage, _ rhs: StorageBookUsage) -> Bool {
        switch self {
        case .size:
            if lhs.bytes == rhs.bytes {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.bytes > rhs.bytes
        case .lastReadAt:
            let leftDate = lhs.lastReadAt ?? .distantPast
            let rightDate = rhs.lastReadAt ?? .distantPast
            if leftDate == rightDate {
                return lhs.importedAt > rhs.importedAt
            }
            return leftDate > rightDate
        case .importedAt:
            return lhs.importedAt > rhs.importedAt
        }
    }
}

private enum StorageBookFilter: Equatable {
    case all
    case ungrouped
    case group(UUID)
    case unread
    case longUnread

    private static let longUnreadInterval: TimeInterval = 30 * 24 * 60 * 60

    func title(groups: [BookGroup]) -> String {
        switch self {
        case .all:
            return NSLocalizedString("storage.filter.all", comment: "")
        case .ungrouped:
            return NSLocalizedString("sidebar.ungrouped", comment: "")
        case let .group(id):
            return groups.first { $0.id == id }?.name
                ?? NSLocalizedString("sidebar.untitledGroup", comment: "")
        case .unread:
            return NSLocalizedString("storage.filter.unread", comment: "")
        case .longUnread:
            return NSLocalizedString("storage.filter.longUnread", comment: "")
        }
    }

    func includes(
        _ book: StorageBookUsage,
        groups: [BookGroup],
        now: Date
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .ungrouped:
            return book.groupID == nil
        case let .group(id):
            return book.groupID == id && groups.contains { $0.id == id }
        case .unread:
            return book.isUnread
        case .longUnread:
            guard let lastReadAt = book.lastReadAt else {
                return false
            }
            return lastReadAt < now.addingTimeInterval(-Self.longUnreadInterval)
        }
    }
}

private enum StorageByteCountFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(bytes, 0))
    }
}

private enum StorageDateFormatter {
    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum StorageProgressFormatter {
    static func string(from progress: Double) -> String {
        NumberFormatter.dedicatedReadingProgress.string(
            from: NSNumber(value: min(max(progress, 0), 1))
        ) ?? "0%"
    }
}

private enum StorageBookExporter {
    static func exportURL(for book: Book, fileStore: AppFileStore) throws -> URL {
        cleanupExportDirectory()
        let exportDirectory = exportDirectoryURL()
        try FileManager.default.createDirectory(
            at: exportDirectory,
            withIntermediateDirectories: true
        )
        let contentURL = try fileStore.url(forRelativePath: book.sourcePath)
        let destinationURL = exportDirectory.appendingPathComponent(
            exportFileName(for: book, contentURL: contentURL),
            isDirectory: false
        )
        try FileManager.default.copyItem(at: contentURL, to: destinationURL)
        return destinationURL
    }

    private static func cleanupExportDirectory() {
        try? FileManager.default.removeItem(at: exportDirectoryURL())
    }

    private static func exportDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("YominkExports", isDirectory: true)
    }

    private static func exportFileName(for book: Book, contentURL: URL) -> String {
        let rawTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = sanitizedExportFileName(
            rawTitle.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : rawTitle
        )
        let contentExtension = contentURL.pathExtension
        let fileExtension = contentExtension.isEmpty ? "txt" : contentExtension
        return "\(baseName).\(fileExtension)"
    }

    private static func sanitizedExportFileName(_ fileName: String) -> String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let sanitized = fileName
            .components(separatedBy: illegalCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? NSLocalizedString("library.untitledBook", comment: "") : sanitized
    }
}

private struct StorageExportPayload: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

private extension View {
    func storageCardStyle() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ImportBookEditPage: View {
    @Environment(\.dismiss) private var dismiss

    let preview: ImportBookPreview
    let importService: ImportService
    let onImported: () -> Void
    let onOpenExistingBook: (Book) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var author: String
    @State private var intro: String
    @State private var isImporting = false
    @State private var duplicateBook: Book?
    @State private var errorMessage: String?

    init(
        preview: ImportBookPreview,
        importService: ImportService,
        onImported: @escaping () -> Void,
        onOpenExistingBook: @escaping (Book) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.preview = preview
        self.importService = importService
        self.onImported = onImported
        self.onOpenExistingBook = onOpenExistingBook
        self.onCancel = onCancel
        _title = State(initialValue: preview.title)
        _author = State(initialValue: preview.author ?? "")
        _intro = State(initialValue: preview.intro ?? "")
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                metadataRows

                Spacer(minLength: 0)
            }

            if isImporting {
                importingOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    cancel()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("import.action") {
                    startImport()
                }
                .disabled(isImporting)
            }
        }
        .alert(item: $duplicateBook) { book in
            Alert(
                title: Text("import.duplicate.title"),
                message: Text("import.duplicate.message"),
                primaryButton: .default(Text("import.duplicate.openExisting")) {
                    isImporting = false
                    onOpenExistingBook(book)
                },
                secondaryButton: .cancel(Text("import.duplicate.cancel")) {
                    isImporting = false
                    cancel()
                }
            )
        }
        .alert(
            "import.error.title",
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

    private var navigationTitle: String {
        String(
            format: NSLocalizedString("import.edit.title", comment: ""),
            preview.fileName
        )
    }

    private var metadataRows: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.title",
                    text: $title
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.title",
                    value: title
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.author",
                    text: $author
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.author",
                    value: author
                )
            }
            .buttonStyle(.plain)

            SettingsPageStyle.separator

            NavigationLink {
                ImportMetadataFieldEditor(
                    title: "import.field.intro",
                    text: $intro
                )
            } label: {
                ImportMetadataRow(
                    title: "import.field.intro",
                    value: intro
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
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

    private func startImport() {
        guard !isImporting else {
            return
        }

        isImporting = true
        let metadata = ImportBookMetadata(
            title: title,
            author: author,
            intro: intro
        )
        Task {
            do {
                switch try await importService.importBookCheckingDuplicate(
                    from: preview.sourceURL,
                    metadata: metadata
                ) {
                case let .duplicate(existingBook):
                    isImporting = false
                    duplicateBook = existingBook
                case .imported(_):
                    isImporting = false
                    onImported()
                }
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel() {
        onCancel()
        dismiss()
    }
}

private struct ImportMetadataRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            if !trimmedValue.isEmpty {
                Text(verbatim: trimmedValue)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }

    private var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ImportMetadataFieldEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.top, 20)
            .background(Color.white)
            .navigationBarBackButtonHidden(true)
            .background(InteractivePopGestureRestorer())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BackTextButton {
                        dismiss()
                    }
                }
            }
    }
}

private struct SettingsSortOrderPage: View {
    @Binding var selection: LibrarySettings.SortOrder

    var body: some View {
        SettingsOptionListPage(title: "settings.sortOrder") {
            ForEach(Array(LibrarySettings.SortOrder.allCases.enumerated()), id: \.element) { index, sortOrder in
                Button {
                    selection = sortOrder
                } label: {
                    SettingsOptionRow(
                        title: sortOrder.localizedTitle,
                        isSelected: selection == sortOrder
                    )
                }
                .buttonStyle(.plain)

                if index < LibrarySettings.SortOrder.allCases.count - 1 {
                    SettingsPageStyle.separator
                }
            }
        }
    }
}

private struct SettingsViewModePage: View {
    @Binding var selection: LibrarySettings.ViewMode

    var body: some View {
        SettingsOptionListPage(title: "settings.viewMode") {
            ForEach(Array(LibrarySettings.ViewMode.allCases.enumerated()), id: \.element) { index, viewMode in
                Button {
                    selection = viewMode
                } label: {
                    SettingsOptionRow(
                        title: viewMode.localizedTitle,
                        isSelected: selection == viewMode
                    )
                }
                .buttonStyle(.plain)

                if index < LibrarySettings.ViewMode.allCases.count - 1 {
                    SettingsPageStyle.separator
                }
            }
        }
    }
}

private struct SettingsOptionListPage<Content: View>: View {
    let title: LocalizedStringKey
    private let content: () -> Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.content = content
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 28)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BackTextButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("<")
                Text("common.back")
            }
        }
    }
}

private struct DedicatedPromptOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @Binding var text: String
    let placeholder: String
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isFocused = true
            }
        }
    }
}

private struct DedicatedConfirmationOverlay: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmTitle: LocalizedStringKey
    let confirmRole: ButtonRole?
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        DedicatedModalBackdrop {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 0) {
                    Button("common.cancel", role: .cancel, action: cancelAction)
                        .frame(maxWidth: .infinity, minHeight: 44)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 0.5, height: 44)

                    Button(confirmTitle, role: confirmRole, action: confirmAction)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 0.5)
                }
                .padding(.horizontal, -18)
                .padding(.bottom, -14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
    }
}

private struct DedicatedModalBackdrop<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        Color.black.opacity(0.28)
            .ignoresSafeArea()
            .overlay {
                content()
                    .frame(width: 270)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
    }
}

private struct InteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onMoveToNavigationController = { navigationController in
            context.coordinator.restoreGesture(on: navigationController)
        }
        DispatchQueue.main.async {
            context.coordinator.restoreGesture(on: controller.navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?

        func restoreGesture(on navigationController: UINavigationController?) {
            guard let navigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer
            else {
                return
            }

            self.navigationController = navigationController
            gesture.delegate = self
            gesture.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    final class Controller: UIViewController {
        var onMoveToNavigationController: ((UINavigationController?) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onMoveToNavigationController?(navigationController)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onMoveToNavigationController?(navigationController)
        }
    }
}

private struct DedicatedListRow: View {
    let title: String
    var showsDeleteControl = false
    var deleteAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
    }
}

private struct DedicatedGroupListRow: View {
    let title: String
    var showsDeleteControl = false
    var showsReorderControl = false
    var isPressed = false
    var isDragging = false
    var dragOffset: CGSize = .zero
    var deleteAction: (() -> Void)?
    var reorderDragChanged: ((CGSize) -> Void)?
    var reorderDragEnded: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if showsDeleteControl {
                Button(role: .destructive) {
                    deleteAction?()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("library.delete"))
                .zIndex(2)
                .allowsHitTesting(true)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Text(verbatim: title)
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showsReorderControl {
                ReorderHandle(
                    onChanged: { translation in
                        reorderDragChanged?(translation)
                    },
                    onEnded: {
                        reorderDragEnded?()
                    }
                )
                .frame(width: DedicatedPageStyle.controlHitWidth, height: DedicatedPageStyle.rowHeight)
                .zIndex(2)
                .accessibilityLabel(Text("groups.reorder"))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: DedicatedPageStyle.rowHeight, alignment: .leading)
        .background(isPressed ? Color(.systemGray5) : Color.white)
        .overlay(alignment: .bottom) {
            DedicatedPageStyle.separator
        }
        .contentShape(Rectangle())
        .offset(y: isDragging ? dragOffset.height : 0)
        .scaleEffect(isDragging ? 1.02 : 1)
        .shadow(
            color: Color.black.opacity(isDragging ? 0.18 : 0),
            radius: isDragging ? 10 : 0,
            x: 0,
            y: isDragging ? 5 : 0
        )
        .zIndex(isDragging ? 1 : 0)
        .animation(DedicatedPageStyle.reorderAnimation, value: isDragging)
    }
}

private struct ReorderHandle: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> HandleView {
        let view = HandleView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let imageView = UIImageView(image: UIImage(systemName: "line.3.horizontal"))
        imageView.tintColor = .systemGray2
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        panGesture.cancelsTouchesInView = true
        panGesture.delaysTouchesBegan = false
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        view.panGesture = panGesture
        context.coordinator.view = view

        return view
    }

    func updateUIView(_ view: HandleView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.view = view
    }

    final class HandleView: UIView {
        weak var panGesture: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let panGesture else {
                return
            }
            nearestScrollView()?.panGestureRecognizer.require(toFail: panGesture)
        }

        private func nearestScrollView() -> UIScrollView? {
            var parent = superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: () -> Void
        weak var view: UIView?

        init(
            onChanged: @escaping (CGSize) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .began:
                setParentScrollEnabled(false)
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .changed:
                onChanged(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                setParentScrollEnabled(true)
                onEnded()
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        private func setParentScrollEnabled(_ isEnabled: Bool) {
            nearestScrollView(from: view)?.isScrollEnabled = isEnabled
        }

        private func nearestScrollView(from view: UIView?) -> UIScrollView? {
            var parent = view?.superview
            while let current = parent {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                parent = current.superview
            }
            return nil
        }
    }
}

private struct ReadingHistoryTableView: UIViewRepresentable {
    @Binding var items: [ReadingHistoryItem]
    let onOpenBook: (Book) -> Void
    let onDelete: (ReadingHistoryItem, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            items: $items,
            onOpenBook: onOpenBook,
            onDelete: onDelete
        )
    }

    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .systemGray6
        tableView.separatorStyle = .none
        tableView.rowHeight = DedicatedPageStyle.compactRowHeight
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.register(
            ReadingHistoryCell.self,
            forCellReuseIdentifier: ReadingHistoryCell.reuseIdentifier
        )
        return tableView
    }

    func updateUIView(_ tableView: UITableView, context: Context) {
        context.coordinator.items = $items
        context.coordinator.onOpenBook = onOpenBook
        context.coordinator.onDelete = onDelete
        tableView.reloadData()
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var items: Binding<[ReadingHistoryItem]>
        var onOpenBook: (Book) -> Void
        var onDelete: (ReadingHistoryItem, Int) -> Void

        init(
            items: Binding<[ReadingHistoryItem]>,
            onOpenBook: @escaping (Book) -> Void,
            onDelete: @escaping (ReadingHistoryItem, Int) -> Void
        ) {
            self.items = items
            self.onOpenBook = onOpenBook
            self.onDelete = onDelete
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            items.wrappedValue.count
        }

        func tableView(
            _ tableView: UITableView,
            cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ReadingHistoryCell.reuseIdentifier,
                for: indexPath
            ) as? ReadingHistoryCell ?? ReadingHistoryCell(
                style: .default,
                reuseIdentifier: ReadingHistoryCell.reuseIdentifier
            )
            cell.configure(item: items.wrappedValue[indexPath.row])
            return cell
        }

        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            guard items.wrappedValue.indices.contains(indexPath.row) else {
                return
            }
            onOpenBook(items.wrappedValue[indexPath.row].book)
        }

        func tableView(
            _ tableView: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            let action = UIContextualAction(
                style: .destructive,
                title: NSLocalizedString("library.delete", comment: "")
            ) { [weak self] _, _, completion in
                guard let self,
                      self.items.wrappedValue.indices.contains(indexPath.row)
                else {
                    completion(false)
                    return
                }
                let item = self.items.wrappedValue[indexPath.row]
                self.items.wrappedValue.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.onDelete(item, indexPath.row)
                completion(true)
            }
            return UISwipeActionsConfiguration(actions: [action])
        }
    }
}

private final class ReadingHistoryCell: UITableViewCell {
    static let reuseIdentifier = "readingHistory"

    private let titleLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: ReadingHistoryItem) {
        titleLabel.text = item.book.title
        dateLabel.text = Self.dateFormatter.localizedString(for: item.readAt, relativeTo: Date())
    }

    private func configureViews() {
        selectionStyle = .default
        backgroundColor = .white
        contentView.backgroundColor = .white

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = .preferredFont(forTextStyle: .subheadline)
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = .secondaryLabel
        dateLabel.numberOfLines = 1
        dateLabel.textAlignment = .right
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = UIView()
        separator.backgroundColor = .systemGray4
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            dateLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

private enum DedicatedPageStyle {
    static let rowHeight: CGFloat = 54
    static let compactRowHeight: CGFloat = 44
    static let controlHitWidth: CGFloat = 44
    static let reorderAnimation = Animation.interactiveSpring(
        response: 0.28,
        dampingFraction: 0.82,
        blendDuration: 0.12
    )

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
    }
}

private extension NumberFormatter {
    static let dedicatedReadingProgress: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}

private extension String {
    var dedicatedFirstBookCoverCharacter: Character? {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .first { character in
                character.unicodeScalars.contains { scalar in
                    CharacterSet.letters.contains(scalar)
                }
            }
    }
}

private struct SettingsListRow: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: SettingsPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private struct SettingsOptionRow: View {
    let title: LocalizedStringKey
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer(minLength: 16)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: SettingsPageStyle.rowHeight, alignment: .leading)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private enum SettingsPageStyle {
    static let rowHeight: CGFloat = 50

    static var separator: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }
}
