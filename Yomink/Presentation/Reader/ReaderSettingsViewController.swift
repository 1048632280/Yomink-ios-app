import SwiftUI
import UIKit
import QuartzCore
import CoreText
import OSLog

private final class ReaderSettingsViewController: UIViewController {
    private var settings: ReaderSettings
    private let onChange: (ReaderSettings) -> Void
    private let fontValueLabel = UILabel()
    private let fontStepper = UIStepper()
    private lazy var pageModeControl = UISegmentedControl(
        items: ReaderSettings.PageMode.allCases.map(\.localizedTitle)
    )
    private lazy var themeControl = UISegmentedControl(
        items: ReaderSettings.Theme.allCases.map(\.localizedTitle)
    )

    init(
        settings: ReaderSettings,
        onChange: @escaping (ReaderSettings) -> Void
    ) {
        self.settings = settings.normalized
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("reader.settings.title", comment: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("common.close", comment: ""),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )

        configureControls()
    }

    private func configureControls() {
        pageModeControl.selectedSegmentIndex = ReaderSettings.PageMode.allCases
            .firstIndex(of: settings.pageMode) ?? 0
        pageModeControl.addTarget(self, action: #selector(pageModeChanged), for: .valueChanged)

        themeControl.selectedSegmentIndex = ReaderSettings.Theme.allCases
            .firstIndex(of: settings.theme) ?? 0
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)

        fontStepper.minimumValue = ReaderSettings.minimumFontSize
        fontStepper.maximumValue = ReaderSettings.maximumFontSize
        fontStepper.stepValue = 1
        fontStepper.value = settings.fontSize
        fontStepper.addTarget(self, action: #selector(fontSizeChanged), for: .valueChanged)
        updateFontValueLabel()

        let fontRow = UIStackView(arrangedSubviews: [fontValueLabel, fontStepper])
        fontRow.axis = .horizontal
        fontRow.alignment = .center
        fontRow.spacing = 12
        fontRow.distribution = .equalSpacing

        let stackView = UIStackView(arrangedSubviews: [
            settingsSection(
                title: NSLocalizedString("reader.settings.pageMode", comment: ""),
                control: pageModeControl
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.fontSize", comment: ""),
                control: fontRow
            ),
            settingsSection(
                title: NSLocalizedString("reader.settings.theme", comment: ""),
                control: themeControl
            )
        ])
        stackView.axis = .vertical
        stackView.spacing = 18
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }

    private func settingsSection(title: String, control: UIView) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        let stackView = UIStackView(arrangedSubviews: [titleLabel, control])
        stackView.axis = .vertical
        stackView.spacing = 8
        return stackView
    }

    private func updateFontValueLabel() {
        fontValueLabel.text = String(
            format: NSLocalizedString("reader.settings.fontSize.value", comment: ""),
            Int(settings.fontSize)
        )
        fontValueLabel.font = .preferredFont(forTextStyle: .body)
        fontValueLabel.adjustsFontForContentSizeCategory = true
    }

    @objc private func pageModeChanged() {
        let index = pageModeControl.selectedSegmentIndex
        guard ReaderSettings.PageMode.allCases.indices.contains(index) else {
            return
        }
        settings.pageMode = ReaderSettings.PageMode.allCases[index]
        onChange(settings)
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard ReaderSettings.Theme.allCases.indices.contains(index) else {
            return
        }
        settings.theme = ReaderSettings.Theme.allCases[index]
        onChange(settings)
    }

    @objc private func fontSizeChanged() {
        settings.fontSize = fontStepper.value
        updateFontValueLabel()
        onChange(settings)
    }

    @objc private func closeButtonTapped() {
        readerPopOrDismiss(animated: true)
    }
}

extension ReaderSettings.PageMode {
    init?(settingsPageTurnIndex: Int) {
        switch settingsPageTurnIndex {
        case 0:
            self = .paged
        case 1:
            self = .curl
        case 2:
            self = .scroll
        default:
            return nil
        }
    }

    var settingsPageTurnIndex: Int {
        switch self {
        case .paged:
            return 0
        case .curl:
            return 1
        case .scroll:
            return 2
        }
    }

    var localizedTitle: String {
        switch self {
        case .paged:
            return NSLocalizedString("reader.settings.pageMode.paged", comment: "")
        case .curl:
            return NSLocalizedString("reader.settings.pageTurn.curl", comment: "")
        case .scroll:
            return NSLocalizedString("reader.settings.pageMode.scroll", comment: "")
        }
    }
}

extension ReaderSettings.LayoutPreset {
    var localizedTitle: String {
        switch self {
        case .compact:
            return NSLocalizedString("reader.settings.layoutPreset.compact", comment: "")
        case .standard:
            return NSLocalizedString("reader.settings.layoutPreset.standard", comment: "")
        case .relaxed:
            return NSLocalizedString("reader.settings.layoutPreset.relaxed", comment: "")
        case .custom:
            return NSLocalizedString("reader.settings.layoutPreset.custom", comment: "")
        }
    }
}

extension ReaderSettings.Theme {
    var localizedTitle: String {
        switch self {
        case .white:
            return NSLocalizedString("reader.settings.theme.white", comment: "")
        case .eyeCare:
            return NSLocalizedString("reader.settings.theme.eyeCare", comment: "")
        case .paper:
            return NSLocalizedString("reader.settings.theme.paper", comment: "")
        case .dark:
            return NSLocalizedString("reader.settings.theme.dark", comment: "")
        }
    }
}
