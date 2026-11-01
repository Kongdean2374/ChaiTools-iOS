import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var host: UIHostingController<KeyboardPanel>?
    private let bridge = KeyboardBridge()
    private var heightConstraint: NSLayoutConstraint?
    private var lastDocument: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        bridge.controller = self
        view.backgroundColor = .secondarySystemBackground
        // One host for the entire extension lifecycle; pages never replace it.
        let host = UIHostingController(rootView: KeyboardPanel(bridge: bridge))
        self.host = host
        host.view.backgroundColor = .clear
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardLayoutMetrics.contentHeight(width: 390, landscape: false, accessibility: false))
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        bridge.needsGlobe = needsInputModeSwitchKey
        bridge.refresh()
        if let previous = lastDocument, previous != textDocumentProxy.documentIdentifier { bridge.resetContext() }
        lastDocument = textDocumentProxy.documentIdentifier
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? (view.bounds.width > 600)
        let proposal = KeyboardLayoutMetrics.contentHeight(width: view.bounds.width, landscape: landscape,
            accessibility: traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        // UIKit owns any system bottom row; count only safe insets actually supplied to this view.
        let height = proposal + view.safeAreaInsets.top + view.safeAreaInsets.bottom
        if let constraint = heightConstraint, abs(constraint.constant - height) > 0.5 { constraint.constant = height }
        let needs = needsInputModeSwitchKey
        if bridge.needsGlobe != needs { DispatchQueue.main.async { [weak self] in self?.bridge.needsGlobe = needs } }
    }
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if lastDocument != textDocumentProxy.documentIdentifier { bridge.resetContext() }
        lastDocument = textDocumentProxy.documentIdentifier
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); bridge.suspend()
    }
}

/// The globe occupies a single toolbar item, not a separate row or hidden constraint.
struct KeyboardGlobe: UIViewRepresentable {
    let bridge: KeyboardBridge
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.accessibilityLabel = "下一個鍵盤；長按選擇鍵盤"
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        button.removeTarget(nil, action: nil, for: .allTouchEvents)
        if let controller = bridge.controller {
            button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        }
        button.tintColor = UIColor(InterfaceTheme.accent)
    }
}
