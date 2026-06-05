import Foundation
import SwiftUI
import UIKit

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

