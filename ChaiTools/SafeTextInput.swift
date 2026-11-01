import SwiftUI
import UIKit

/// Reject replacements BEFORE UITextView changes its buffer or SwiftUI receives the value.
/// Covers system Paste, hardware typing, dictation replacements and marked text.
struct SafeTextInput: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    var label: String
    var onBlocked: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.accessibilityLabel = label
        view.autocorrectionType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.isScrollEnabled = true
        view.keyboardDismissMode = .interactive
        view.inputAccessoryView = context.coordinator.dismissal.accessory(for: view)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = (try? SensitiveContentGuard.checked(text)) ?? "" }
        view.accessibilityLabel = label
        view.isEditable = isEnabled
        if !isEnabled && view.isFirstResponder { view.resignFirstResponder() }
    }
    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        view.resignFirstResponder()
        coordinator.dismissal.endedEditing()
        view.delegate = nil
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        let dismissal = InputDismissal()
        var parent: SafeTextInput
        init(_ parent: SafeTextInput) { self.parent = parent }
        func textViewDidBeginEditing(_ textView: UITextView) { dismissal.beganEditing(textView) }
        func textViewDidEndEditing(_ textView: UITextView) { dismissal.endedEditing() }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let proposed = (view.text as NSString).replacingCharacters(in: range, with: text)
            guard (try? SensitiveContentGuard.validate(proposed)) != nil else { parent.onBlocked(); return false }
            return true
        }
        func textViewDidChange(_ view: UITextView) {
            guard let safe = try? SensitiveContentGuard.checked(view.text) else {
                view.text = parent.text; parent.onBlocked(); return
            }
            parent.text = safe
        }
    }
}

struct SafeLabeledInput: View {
    let title: String
    @Binding var text: String
    var onBlocked: () -> Void
    init(_ title: String, text: Binding<String>, onBlocked: @escaping () -> Void) {
        self.title = title; _text = text; self.onBlocked = onBlocked
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            SafeTextInput(text: $text, label: title, onBlocked: onBlocked).frame(height: 64)
        }
    }
}
