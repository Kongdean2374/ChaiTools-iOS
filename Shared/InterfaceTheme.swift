#if canImport(SwiftUI) && os(iOS)
import SwiftUI
import UIKit

enum InterfaceTheme {
    static let accent = adaptive(0x6353CB, 0x9588FF)
    static let accentStrong = Color(red: 0.388, green: 0.325, blue: 0.796)
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            var hex = traits.userInterfaceStyle == .dark ? dark : light
            if traits.accessibilityContrast == .high {
                if dark == 0xA9B1C0 { hex = traits.userInterfaceStyle == .dark ? 0xD1D6E0 : 0x354055 }
                if dark == 0xF6F7FB { hex = traits.userInterfaceStyle == .dark ? 0xFFFFFF : 0x111522 }
            }
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let background = adaptive(0xF5F6FA, 0x101218)
    static let surface = adaptive(0xFFFFFF, 0x1B1F29)
    static let secondarySurface = adaptive(0xECEEF5, 0x262B38)
    static let text = adaptive(0x202636, 0xF6F7FB)
    static let secondaryText = adaptive(0x526075, 0xA9B1C0)
    static let radius: CGFloat = 18
    static let spacing: CGFloat = 16
    static let touch: CGFloat = 44
}

struct SurfaceCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(InterfaceTheme.surface, in: RoundedRectangle(cornerRadius: InterfaceTheme.radius))
            .overlay(RoundedRectangle(cornerRadius: InterfaceTheme.radius).strokeBorder(InterfaceTheme.secondaryText.opacity(0.08)))
    }
}
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .frame(minHeight: InterfaceTheme.touch).padding(.horizontal, 12)
            .foregroundStyle(prominent ? Color.white : InterfaceTheme.text)
            .background(prominent ? InterfaceTheme.accentStrong : InterfaceTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
            .opacity(!isEnabled ? 0.5 : configuration.isPressed ? 0.65 : 1)
    }
}
struct AppSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(InterfaceTheme.background)
            .tint(InterfaceTheme.accent)
    }
}
extension View { func appSurface() -> some View { modifier(AppSurface()) } }

struct CTBarSurface: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency { InterfaceTheme.surface }
        else { Rectangle().fill(.regularMaterial) }
    }
}
struct CTSectionHeader: View {
    let title: String
    var body: some View { Text(title).font(.headline).foregroundStyle(InterfaceTheme.text) }
}
struct CTStatusPill: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).foregroundStyle(InterfaceTheme.secondaryText)
            .padding(.horizontal, 8).padding(.vertical, 5).background(InterfaceTheme.secondarySurface, in: Capsule())
    }
}
struct CTToolTile: View {
    let tool: Tool
    var compact = false
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        VStack(alignment: compact ? .center : .leading, spacing: compact ? 5 : 8) {
            HStack {
                Image(systemName: tool.icon).font(.system(size: compact ? 19 : 20, weight: .medium)).foregroundStyle(InterfaceTheme.accent)
                if !compact { Spacer(); if tool.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(InterfaceTheme.accent) } }
            }.frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            Text(tool.name).font(compact ? .caption.weight(.medium) : .subheadline.weight(.semibold))
                .lineLimit(compact && !size.isAccessibilitySize ? 1 : nil)
            if !compact { Text(tool.subtitle).font(.caption).foregroundStyle(InterfaceTheme.secondaryText).fixedSize(horizontal: false, vertical: true) }
        }.foregroundStyle(InterfaceTheme.text)
            .frame(maxWidth: .infinity, minHeight: compact ? 48 : 78, alignment: compact ? .center : .leading)
            .padding(compact ? 6 : 14)
            .background(InterfaceTheme.surface, in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
    }
}
struct CTPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay {
            RoundedRectangle(cornerRadius: 12).fill(InterfaceTheme.accent.opacity(configuration.isPressed ? 0.12 : 0))
        }.opacity(configuration.isPressed ? 0.85 : 1)
    }
}

@MainActor enum AppHaptics {
    static func tap(enabled: Bool = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func result(success: Bool) {
        guard UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
    }
}
#endif
