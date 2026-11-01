import UIKit

/// Owned by each native editor coordinator. Listen only while that editor has
/// focus, in its own window; never cancel a button, selection or scroll gesture.
final class InputDismissal: NSObject, UIGestureRecognizerDelegate {
    private weak var input: UIView?
    private var outsideTap: UITapGestureRecognizer?

    func accessory(for input: UIView) -> UIToolbar {
        self.input = input
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        toolbar.autoresizingMask = [.flexibleWidth]
        let done = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(dismiss))
        done.accessibilityLabel = "完成輸入，收起鍵盤"
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        return toolbar
    }

    func beganEditing(_ input: UIView) {
        endedEditing()
        self.input = input
        guard let window = input.window else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismiss))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        outsideTap = tap
    }

    func endedEditing() {
        if let tap = outsideTap { tap.view?.removeGestureRecognizer(tap) }
        outsideTap = nil
    }

    @objc private func dismiss() {
        // End editing commits any pending input; do not clear the binding or draft.
        input?.resignFirstResponder()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard input?.isFirstResponder == true else { return false }
        var touched = touch.view
        while let view = touched {
            // Preserve caret placement, selection, edit menus, input switching,
            // keyboard/accessory controls and normal button actions.
            if view is UITextView || view is UITextField || view is UIControl || view is UIInputView || view is UIToolbar { return false }
            touched = view.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
