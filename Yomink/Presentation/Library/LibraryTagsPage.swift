import Foundation
import SwiftUI
import UIKit

struct LibraryTagsPage: View {
    @Environment(\.dismiss) private var dismiss

    let repository: any LibraryRepository
    let sortOrder: LibrarySettings.SortOrder
    let onOpenBook: (Book) -> Void

    @State private var tagUsages: [BookTagUsage] = []
    @State private var selectedUsage: BookTagUsage?
    @State private var tagNameEditorPresented = false
    @State private var isEditingTags = false
    @State private var tagPendingDeletion: BookTagUsage?
    @State private var tagNameDraft = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tagUsages.isEmpty {
                        emptyTagsView
                    } else {
                        tagCloudCard
                        tagListCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }

            tagRouteLink

            if tagNameEditorPresented {
                DedicatedPromptOverlay(
                    title: "tags.new",
                    message: "tags.name.message",
                    text: $tagNameDraft,
                    placeholder: NSLocalizedString("tags.name.placeholder", comment: ""),
                    confirmTitle: "common.save",
                    confirmRole: nil,
                    confirmAction: createTag,
                    cancelAction: cancelCreatingTag
                )
            }

            if tagPendingDeletion != nil {
                DedicatedConfirmationOverlay(
                    title: "tags.delete.title",
                    message: "tags.delete.message",
                    confirmTitle: "tags.delete.action",
                    confirmRole: .destructive,
                    confirmAction: deletePendingTag,
                    cancelAction: {
                        tagPendingDeletion = nil
                    }
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("tags.page.title")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("common.new") {
                    beginCreatingTag()
                }

                if !tagUsages.isEmpty {
                    Button(tagEditButtonTitle) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isEditingTags.toggle()
                        }
                    }
                }
            }
        }
        .task {
            await reloadTags()
        }
        .alert(
            "tags.error.title",
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

    private var emptyTagsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("tags.empty.message")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("tags.new") {
                beginCreatingTag()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .storageCardStyle()
    }

    private var tagCloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("tags.cloud.title")
                .font(.headline)
                .foregroundColor(.primary)

            TagWordCloudView(tagUsages: tagUsages) { usage in
                selectedUsage = usage
            }
            .frame(height: 260)
        }
        .storageCardStyle()
    }

    private var tagEditButtonTitle: LocalizedStringKey {
        isEditingTags ? "common.done" : "common.edit"
    }

    private var tagListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tags.all.title")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 0) {
                ForEach(Array(tagUsages.enumerated()), id: \.element.id) { index, usage in
                    if isEditingTags {
                        LibraryTagListRow(
                            usage: usage,
                            countText: countText(for: usage.bookCount),
                            isEditing: true,
                            deleteAction: {
                                tagPendingDeletion = usage
                            }
                        )
                    } else {
                        Button {
                            selectedUsage = usage
                        } label: {
                            LibraryTagListRow(
                                usage: usage,
                                countText: countText(for: usage.bookCount),
                                isEditing: false,
                                deleteAction: {}
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if index < tagUsages.count - 1 {
                        SettingsPageStyle.separator
                    }
                }
            }
        }
        .storageCardStyle()
    }

    private var tagRouteLink: some View {
        NavigationLink(
            isActive: Binding(
                get: { selectedUsage != nil },
                set: { isActive in
                    if !isActive {
                        selectedUsage = nil
                    }
                }
            )
        ) {
            if let selectedUsage {
                TaggedBooksPage(
                    tag: selectedUsage.tag,
                    repository: repository,
                    sortOrder: sortOrder,
                    onOpenBook: onOpenBook
                )
            } else {
                EmptyView()
            }
        } label: {
            EmptyView()
        }
        .hidden()
        .frame(width: 0, height: 0)
    }

    private func countText(for count: Int) -> String {
        String(
            format: NSLocalizedString("tags.count.format", comment: ""),
            count
        )
    }

    @MainActor
    private func reloadTags() async {
        do {
            tagUsages = try await repository.fetchTagsWithUsage()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginCreatingTag() {
        tagNameDraft = ""
        tagNameEditorPresented = true
    }

    private func cancelCreatingTag() {
        tagNameDraft = ""
        tagNameEditorPresented = false
    }

    private func createTag() {
        let name = tagNameDraft

        Task {
            do {
                _ = try await repository.createTag(name: name)
                cancelCreatingTag()
                await reloadTags()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingTag() {
        guard let usage = tagPendingDeletion else {
            return
        }

        Task {
            do {
                try await repository.deleteTag(id: usage.id)
                if selectedUsage?.id == usage.id {
                    selectedUsage = nil
                }
                tagPendingDeletion = nil
                await reloadTags()
                if tagUsages.isEmpty {
                    isEditingTags = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LibraryTagListRow: View {
    let usage: BookTagUsage
    let countText: String
    let isEditing: Bool
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            deleteSlot

            Text(verbatim: usage.tag.name)
                .font(.body.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(verbatim: countText)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .trailing)

            ZStack {
                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .frame(width: 14)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var deleteSlot: some View {
        ZStack {
            if isEditing {
                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                        .frame(width: 28, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("tags.delete.action"))
            }
        }
        .frame(width: isEditing ? 30 : 0)
        .clipped()
    }
}

private struct TaggedBooksPage: View {
    @Environment(\.dismiss) private var dismiss

    let tag: BookTag
    let repository: any LibraryRepository
    let sortOrder: LibrarySettings.SortOrder
    let onOpenBook: (Book) -> Void

    @State private var books: [Book] = []
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            if books.isEmpty {
                Text("tags.books.empty")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(books) { book in
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
                    .listRowBackground(Color(.systemGray6))
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                    )
                }
                .listStyle(.plain)
                .background(Color(.systemGray6))
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(InteractivePopGestureRestorer())
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(tag.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackTextButton {
                    dismiss()
                }
            }
        }
        .task {
            await reloadBooks()
        }
        .alert(
            "tags.error.title",
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
    private func reloadBooks() async {
        do {
            books = try await repository.fetchBooks(
                scope: .tag(tag.id),
                sortOrder: sortOrder
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TagWordCloudView: UIViewRepresentable {
    let tagUsages: [BookTagUsage]
    let onSelect: (BookTagUsage) -> Void

    func makeUIView(context: Context) -> TagWordCloudUIKitView {
        let view = TagWordCloudUIKitView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TagWordCloudUIKitView, context: Context) {
        view.configure(
            tagUsages: tagUsages,
            onSelect: onSelect
        )
    }
}

private final class TagWordCloudUIKitView: UIView {
    private var tagUsages: [BookTagUsage] = []
    private var wordLabels: [TagWordLabel] = []
    private var onSelect: ((BookTagUsage) -> Void)?

    func configure(
        tagUsages: [BookTagUsage],
        onSelect: @escaping (BookTagUsage) -> Void
    ) {
        self.tagUsages = tagUsages
        self.onSelect = onSelect
        rebuildLabels()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutWordLabels()
    }

    private func rebuildLabels() {
        wordLabels.forEach { $0.removeFromSuperview() }
        wordLabels = tagUsages
            .sorted { lhs, rhs in
                if lhs.bookCount != rhs.bookCount {
                    return lhs.bookCount > rhs.bookCount
                }
                return lhs.tag.name.localizedCaseInsensitiveCompare(rhs.tag.name) == .orderedAscending
            }
            .map { usage in
                let label = TagWordLabel()
                label.usage = usage
                label.text = usage.tag.name
                label.textAlignment = .center
                label.numberOfLines = 1
                label.textColor = TagWordCloudPalette.color(for: usage.tag.id)
                label.font = .systemFont(
                    ofSize: fontSize(for: usage),
                    weight: usage.bookCount == maxBookCount ? .bold : .semibold
                )
                label.adjustsFontForContentSizeCategory = false
                label.adjustsFontSizeToFitWidth = true
                label.minimumScaleFactor = 0.7
                label.isUserInteractionEnabled = true
                label.addGestureRecognizer(
                    UITapGestureRecognizer(
                        target: self,
                        action: #selector(wordTapped(_:))
                    )
                )
                addSubview(label)
                return label
            }
    }

    private func layoutWordLabels() {
        guard bounds.width > 20,
              bounds.height > 20
        else {
            return
        }

        var placedFrames: [CGRect] = []
        let cloudBounds = bounds.insetBy(dx: 3, dy: 3)
        let center = CGPoint(
            x: cloudBounds.midX,
            y: cloudBounds.midY
        )

        for label in wordLabels {
            let targetSize = label.sizeThatFits(
                CGSize(
                    width: cloudBounds.width * 0.88,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
            let size = CGSize(
                width: min(max(targetSize.width, 12), cloudBounds.width),
                height: min(max(targetSize.height, 16), cloudBounds.height)
            )

            let frame: CGRect
            if placedFrames.isEmpty {
                frame = clampedFrame(centeredAt: center, size: size, in: cloudBounds)
            } else {
                frame = placementFrame(
                    for: label,
                    size: size,
                    center: center,
                    in: cloudBounds,
                    avoiding: placedFrames
                )
            }

            label.frame = frame.integral
            placedFrames.append(frame.insetBy(dx: -4, dy: -2))
        }
    }

    private func placementFrame(
        for label: TagWordLabel,
        size: CGSize,
        center: CGPoint,
        in bounds: CGRect,
        avoiding placedFrames: [CGRect]
    ) -> CGRect {
        let seed = TagWordCloudPalette.stableHash(for: label.usage?.tag.id ?? UUID())
        let candidates = edgeCandidates(
            size: size,
            avoiding: placedFrames,
            seed: seed
        ) + gridCandidates(
            size: size,
            in: bounds,
            seed: seed
        )

        if let bestFrame = candidates
            .filter({ bounds.contains($0) && !intersects($0, with: placedFrames) })
            .min(by: {
                placementScore(for: $0, center: center, in: bounds, seed: seed)
                    < placementScore(for: $1, center: center, in: bounds, seed: seed)
            }) {
            return bestFrame
        }

        return fallbackFrame(
            size: size,
            in: bounds,
            avoiding: placedFrames
        )
    }

    private func edgeCandidates(
        size: CGSize,
        avoiding placedFrames: [CGRect],
        seed: UInt64
    ) -> [CGRect] {
        let offsets: [CGFloat] = [-0.58, -0.34, -0.16, 0, 0.16, 0.34, 0.58]
        var candidates: [CGRect] = []

        for (placedIndex, baseFrame) in placedFrames.enumerated() {
            let xJitter = jitter(seed: seed, salt: UInt64(placedIndex * 19 + 5), amplitude: 3)
            let yJitter = jitter(seed: seed, salt: UInt64(placedIndex * 23 + 11), amplitude: 3)

            for offset in offsets {
                let yOffset = offset * max(baseFrame.height, size.height) + yJitter
                candidates.append(
                    CGRect(
                        x: baseFrame.minX - size.width - 4,
                        y: baseFrame.midY - size.height / 2 + yOffset,
                        width: size.width,
                        height: size.height
                    )
                )
                candidates.append(
                    CGRect(
                        x: baseFrame.maxX + 4,
                        y: baseFrame.midY - size.height / 2 + yOffset,
                        width: size.width,
                        height: size.height
                    )
                )

                let xOffset = offset * max(baseFrame.width, size.width) + xJitter
                candidates.append(
                    CGRect(
                        x: baseFrame.midX - size.width / 2 + xOffset,
                        y: baseFrame.minY - size.height - 2,
                        width: size.width,
                        height: size.height
                    )
                )
                candidates.append(
                    CGRect(
                        x: baseFrame.midX - size.width / 2 + xOffset,
                        y: baseFrame.maxY + 2,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }

        return candidates
    }

    private func gridCandidates(
        size: CGSize,
        in bounds: CGRect,
        seed: UInt64
    ) -> [CGRect] {
        let stepX = max(size.width + 4, 14)
        let stepY = max(size.height + 2, 12)
        let rowOffset = CGFloat(seed % 11)
        var candidates: [CGRect] = []
        var y = bounds.minY

        while y <= bounds.maxY - size.height {
            var x = bounds.minX + rowOffset
            while x <= bounds.maxX - size.width {
                candidates.append(
                    CGRect(
                        origin: CGPoint(x: x, y: y),
                        size: size
                    )
                )
                x += stepX
            }
            y += stepY
        }

        return candidates
    }

    private func placementScore(
        for frame: CGRect,
        center: CGPoint,
        in bounds: CGRect,
        seed: UInt64
    ) -> CGFloat {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let dx = (point.x - center.x) / max(bounds.width, 1)
        let dy = (point.y - center.y) / max(bounds.height, 1)
        let distance = sqrt(dx * dx + dy * dy)
        let jitter = abs(jitter(seed: seed, salt: 97, amplitude: 0.018))
        return distance + jitter
    }

    private func intersects(
        _ frame: CGRect,
        with placedFrames: [CGRect]
    ) -> Bool {
        let hitFrame = frame.insetBy(dx: -3, dy: -1)
        return placedFrames.contains { placedFrame in
            placedFrame.intersects(hitFrame)
        }
    }

    private func fallbackFrame(
        size: CGSize,
        in bounds: CGRect,
        avoiding placedFrames: [CGRect]
    ) -> CGRect {
        let stepX = max(size.width + 4, 14)
        let stepY = max(size.height + 2, 12)
        var y = bounds.minY

        while y <= bounds.maxY - size.height {
            var x = bounds.minX
            while x <= bounds.maxX - size.width {
                let candidate = CGRect(origin: CGPoint(x: x, y: y), size: size)
                if !intersects(candidate, with: placedFrames) {
                    return candidate
                }
                x += stepX
            }
            y += stepY
        }

        return clampedFrame(
            centeredAt: CGPoint(x: bounds.midX, y: bounds.midY),
            size: size,
            in: bounds
        )
    }

    private func jitter(
        seed: UInt64,
        salt: UInt64,
        amplitude: CGFloat
    ) -> CGFloat {
        let mixed = TagWordCloudPalette.mix(seed &+ (salt &* 97))
        let unit = CGFloat(Int(mixed % 2_001) - 1_000) / 1_000
        return unit * amplitude
    }

    private func clampedFrame(
        centeredAt point: CGPoint,
        size: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        let x = min(
            max(point.x - size.width / 2, bounds.minX),
            bounds.maxX - size.width
        )
        let y = min(
            max(point.y - size.height / 2, bounds.minY),
            bounds.maxY - size.height
        )
        return CGRect(
            origin: CGPoint(x: x, y: y),
            size: size
        )
    }

    private func fontSize(for usage: BookTagUsage) -> CGFloat {
        guard maxBookCount > minBookCount else {
            return 22
        }

        let progress = CGFloat(usage.bookCount - minBookCount) / CGFloat(maxBookCount - minBookCount)
        return 15 + progress * 20
    }

    private var minBookCount: Int {
        tagUsages.map(\.bookCount).min() ?? 0
    }

    private var maxBookCount: Int {
        tagUsages.map(\.bookCount).max() ?? 0
    }

    @objc private func wordTapped(_ recognizer: UITapGestureRecognizer) {
        guard let label = recognizer.view as? TagWordLabel,
              let usage = label.usage
        else {
            return
        }
        onSelect?(usage)
    }

    private final class TagWordLabel: UILabel {
        var usage: BookTagUsage?
    }
}

private enum TagWordCloudPalette {
    private static let colors: [UIColor] = [
        makeColor(red: 0xA3, green: 0x41, blue: 0x58),
        makeColor(red: 0x38, green: 0x52, blue: 0x7A),
        makeColor(red: 0xB5, green: 0x9A, blue: 0x45),
        makeColor(red: 0x6B, green: 0x7D, blue: 0x53),
        makeColor(red: 0x84, green: 0x74, blue: 0xA1),
        makeColor(red: 0xB8, green: 0x63, blue: 0x41),
        makeColor(red: 0x54, green: 0x63, blue: 0x6D),
        makeColor(red: 0x5C, green: 0x6E, blue: 0x58),
        makeColor(red: 0x8D, green: 0x4A, blue: 0x5B),
        makeColor(red: 0x4D, green: 0x80, blue: 0x76)
    ]

    static func color(for id: UUID) -> UIColor {
        colors[Int(stableHash(for: id) % UInt64(colors.count))]
    }

    private static func makeColor(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) -> UIColor {
        UIColor(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: 1
        )
    }

    static func stableHash(for id: UUID) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    static func mix(_ value: UInt64) -> UInt64 {
        var mixed = value
        mixed ^= mixed >> 33
        mixed = mixed &* 0xff51afd7ed558ccd
        mixed ^= mixed >> 33
        mixed = mixed &* 0xc4ceb9fe1a85ec53
        mixed ^= mixed >> 33
        return mixed
    }
}

