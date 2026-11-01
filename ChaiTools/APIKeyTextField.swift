import SwiftUI
import UIKit

/// Keep secure entry and the standard UIKit edit menu. Avoid rewriting text on
/// every SwiftUI update, which can disrupt the selection or a pending paste.
struct APIKeyTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.keyboardType = .asciiCapable
        field.textContentType = nil
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .done
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.inputAccessoryView = context.coordinator.dismissal.accessory(for: field)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.accessibilityLabel = "API 金鑰"
        field.accessibilityHint = "可長按貼上，或使用下方貼上金鑰按鈕；內容以密碼遮罩顯示。"
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        field.placeholder = placeholder
        if !isEnabled && field.isFirstResponder { field.resignFirstResponder() }
        field.isEnabled = isEnabled
        // Only replace for an external change (paste button, clear, saved key).
        // User typing and edit-menu paste already update the binding via editingChanged.
        if field.text != text { field.text = text }
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        field.resignFirstResponder()
        coordinator.dismissal.endedEditing()
        field.delegate = nil
        field.removeTarget(coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        let dismissal = InputDismissal()
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ sender: UITextField) { text.wrappedValue = sender.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { dismissal.beganEditing(textField) }
        func textFieldDidEndEditing(_ textField: UITextField) { dismissal.endedEditing() }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
