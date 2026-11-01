import Foundation

/// A proposal based only on device geometry. Tool/source/result never affect it.
/// Actual heights and system keyboard differences still require device measurement.
enum KeyboardLayoutMetrics {
    static func contentHeight(width: CGFloat, landscape: Bool, accessibility: Bool) -> CGFloat {
        let normal: CGFloat = landscape ? (width < 700 ? 204 : 216) : min(300, max(270, 270 + (width - 320) * 0.22))
        return normal + (accessibility ? 24 : 0)
    }
}
