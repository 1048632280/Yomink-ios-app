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
        ReadingProgressFormatter.percentString(from: book.progressPercentage)
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

