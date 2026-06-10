import SwiftUI
import UIKit

@MainActor
final class ReaderPageTouchAreasViewController: UIViewController {
    private var settings: ReaderSettings
    private let onSave: (ReaderSettings) -> Void
    private var buttons: [UIButton] = []
    private var didSaveSettings = false

    init(
        settings: ReaderSettings,
        onSave: @escaping (ReaderSettings) -> Void
    ) {
        self.settings = settings.normalized
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        edgesForExtendedLayout = [.top, .bottom]
        extendedLayoutIncludesOpaqueBars = true
        configureGrid()
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || navigationController?.isBeingDismissed == true else {
            return
        }

        if let transitionCoordinator,
           transitionCoordinator.isInteractive {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self] context in
                guard !context.isCancelled else {
                    return
                }
                self?.saveSettingsIfNeeded()
            }
            return
        }

        saveSettingsIfNeeded()
    }

    private func configureGrid() {
        buttons = []

        let rows = (0..<3).map { rowIndex in
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill
            rowStack.spacing = 0

            for columnIndex in 0..<3 {
                let index = rowIndex * 3 + columnIndex
                rowStack.addArrangedSubview(cellButton(at: index))
            }

            return rowStack
        }

        let gridStack = UIStackView(arrangedSubviews: rows)
        gridStack.axis = .vertical
        gridStack.distribution = .fillEqually
        gridStack.alignment = .fill
        gridStack.spacing = 0
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridStack)

        NSLayoutConstraint.activate([
            gridStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridStack.topAnchor.constraint(equalTo: view.topAnchor),
            gridStack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func cellButton(at index: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = index
        button.titleLabel?.font = .preferredFont(forTextStyle: .title2)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: #selector(touchAreaButtonTapped(_:)), for: .touchUpInside)
        buttons.append(button)
        update(button, at: index)

        if index == 3 {
            addEdgeHint(to: button)
        }

        return button
    }

    private func addEdgeHint(to container: UIView) {
        let hintLabel = UILabel()
        hintLabel.text = NSLocalizedString("reader.touchAreas.edgeBackHint", comment: "")
            .map(String.init)
            .joined(separator: "\n")
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        hintLabel.font = .preferredFont(forTextStyle: .caption2)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.isUserInteractionEnabled = false
        container.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            hintLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            hintLabel.widthAnchor.constraint(equalToConstant: 18),
            hintLabel.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.7)
        ])
    }

    private func update(
        _ button: UIButton,
        at index: Int
    ) {
        let action = settings.touchAreaMap[index]
        button.backgroundColor = action.touchAreaColor
        button.setTitle(action.localizedTitle, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.72), for: .highlighted)
    }

    @objc private func touchAreaButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard settings.touchAreaMap.indices.contains(index) else {
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("reader.touchAreas.bindTitle", comment: ""),
            message: nil,
            preferredStyle: .actionSheet
        )
        let isOnlyMenuArea = settings.touchAreaMap[index] == .menu
            && settings.touchAreaMap.filter { $0 == .menu }.count == 1
        for action in ReaderSettings.TouchAreaAction.allCases {
            let item = UIAlertAction(title: action.localizedTitle, style: .default) { [weak self] _ in
                guard let self else {
                    return
                }
                self.settings.touchAreaMap[index] = action
                self.update(sender, at: index)
            }
            item.isEnabled = !(isOnlyMenuArea && action != .menu)
            alert.addAction(item)
        }
        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("reader.touchAreas.saveAndExit", comment: ""),
                style: .destructive
            ) { [weak self] _ in
                self?.saveAndExit()
            }
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("common.cancel", comment: ""), style: .cancel))
        alert.popoverPresentationController?.sourceView = sender
        alert.popoverPresentationController?.sourceRect = sender.bounds
        present(alert, animated: true)
    }

    private func saveAndExit() {
        saveSettingsIfNeeded()
        readerPopOrDismiss(animated: true)
    }

    private func saveSettingsIfNeeded() {
        guard !didSaveSettings else {
            return
        }

        didSaveSettings = true
        onSave(settings.normalized)
    }
}

private extension ReaderSettings.TouchAreaAction {
    var localizedTitle: String {
        switch self {
        case .previousPage:
            return NSLocalizedString("reader.touchAreas.previousPage", comment: "")
        case .menu:
            return NSLocalizedString("reader.touchAreas.menu", comment: "")
        case .nextPage:
            return NSLocalizedString("reader.touchAreas.nextPage", comment: "")
        case .none:
            return NSLocalizedString("reader.touchAreas.none", comment: "")
        }
    }

    var touchAreaColor: UIColor {
        switch self {
        case .previousPage:
            return UIColor(red: 0.29, green: 0.33, blue: 0.58, alpha: 1)
        case .menu:
            return UIColor(red: 0.70, green: 0.48, blue: 0.30, alpha: 1)
        case .nextPage:
            return UIColor(red: 0.36, green: 0.54, blue: 0.24, alpha: 1)
        case .none:
            return UIColor(red: 0.31, green: 0.31, blue: 0.33, alpha: 1)
        }
    }
}

