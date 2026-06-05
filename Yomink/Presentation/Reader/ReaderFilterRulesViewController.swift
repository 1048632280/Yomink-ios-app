import SwiftUI
import UIKit

@MainActor
final class ReaderFilterRulesViewController: UITableViewController {
    private let bookID: UUID
    private let repository: any LibraryRepository
    private var rules: [TextFilterRule]
    private let onRulesChanged: ([TextFilterRule]) -> Void

    init(
        bookID: UUID,
        repository: any LibraryRepository,
        rules: [TextFilterRule],
        onRulesChanged: @escaping ([TextFilterRule]) -> Void
    ) {
        self.bookID = bookID
        self.repository = repository
        self.rules = rules
        self.onRulesChanged = onRulesChanged
        super.init(style: .plain)
        title = NSLocalizedString("reader.filter.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemGroupedBackground
        configureCloseButtonIfNeeded()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addButtonTapped)
        )
        updateEmptyState()
    }

    private func configureCloseButtonIfNeeded() {
        guard navigationController?.viewControllers.first === self else {
            return
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.back", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rules.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let reuseIdentifier = "filterRule"
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseIdentifier)
            ?? UITableViewCell(style: .value1, reuseIdentifier: reuseIdentifier)
        let rule = rules[indexPath.row]
        cell.textLabel?.text = rule.source
        cell.detailTextLabel?.text = rule.replacement ?? ""
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard rules.indices.contains(indexPath.row) else {
            return
        }

        showRuleEditor(rule: rules[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(
            style: .destructive,
            title: NSLocalizedString("library.delete", comment: "")
        ) { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            let rule = self.rules[indexPath.row]
            Task { [weak self] in
                guard let self else {
                    await MainActor.run {
                        completion(false)
                    }
                    return
                }
                do {
                    try await self.repository.deleteFilterRule(id: rule.id)
                    await MainActor.run {
                        guard let currentIndex = self.rules.firstIndex(where: { $0.id == rule.id }) else {
                            completion(false)
                            return
                        }
                        self.rules.remove(at: currentIndex)
                        self.tableView.deleteRows(
                            at: [IndexPath(row: currentIndex, section: indexPath.section)],
                            with: .automatic
                        )
                        self.updateEmptyState()
                        self.onRulesChanged(self.rules)
                        completion(true)
                    }
                } catch {
                    await MainActor.run {
                        completion(false)
                    }
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }

    @objc private func addButtonTapped() {
        showRuleEditor(rule: nil)
    }

    private func showRuleEditor(rule: TextFilterRule?) {
        let alert = UIAlertController(
            title: NSLocalizedString(
                rule == nil ? "reader.filter.addTitle" : "reader.filter.editTitle",
                comment: ""
            ),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.source", comment: "")
            textField.text = rule?.source
        }
        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("reader.filter.replacement", comment: "")
            textField.text = rule?.replacement
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let source = alert?.textFields?.first?.text
            else {
                return
            }
            let replacement = alert?.textFields?[safe: 1]?.text
            if let rule {
                self.updateRule(id: rule.id, source: source, replacement: replacement)
            } else {
                self.createRule(source: source, replacement: replacement)
            }
        })
        present(alert, animated: true)
    }

    private func createRule(source: String, replacement: String?) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let rule = try await repository.createFilterRule(
                    bookID: bookID,
                    source: source,
                    replacement: replacement
                )
                await MainActor.run {
                    self.rules.append(rule)
                    self.tableView.insertRows(
                        at: [IndexPath(row: self.rules.count - 1, section: 0)],
                        with: .automatic
                    )
                    self.updateEmptyState()
                    self.onRulesChanged(self.rules)
                }
            } catch {
                await MainActor.run {
                    self.showError(error)
                }
            }
        }
    }

    private func updateRule(id: UUID, source: String, replacement: String?) {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let rule = try await repository.updateFilterRule(
                    id: id,
                    source: source,
                    replacement: replacement
                )
                await MainActor.run {
                    guard let index = self.rules.firstIndex(where: { $0.id == id }) else {
                        return
                    }
                    self.rules[index] = rule
                    self.tableView.reloadRows(
                        at: [IndexPath(row: index, section: 0)],
                        with: .automatic
                    )
                    self.onRulesChanged(self.rules)
                }
            } catch {
                await MainActor.run {
                    self.showError(error)
                }
            }
        }
    }

    private func updateEmptyState() {
        if rules.isEmpty {
            let label = UILabel()
            label.text = NSLocalizedString("reader.filter.empty", comment: "")
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            tableView.backgroundView = label
        } else {
            tableView.backgroundView = nil
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: NSLocalizedString("reader.error.title", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.ok", comment: ""), style: .default))
        present(alert, animated: true)
    }
}


private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

