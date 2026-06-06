import Foundation
import SwiftUI
import UIKit

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
