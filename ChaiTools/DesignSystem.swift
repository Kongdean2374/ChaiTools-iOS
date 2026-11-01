import SwiftUI

struct OperationNotice: Identifiable, Equatable {
    enum Kind: Equatable { case info, success, failure }
    var id = UUID()
    var title: String
    var message: String
    var kind: Kind = .info
    var symbol: String { kind == .success ? "checkmark.circle.fill" : kind == .failure ? "exclamationmark.triangle.fill" : "info.circle.fill" }
    var color: Color { kind == .success ? InterfaceTheme.accent : kind == .failure ? .orange : .secondary }
}
struct NoticeCard: View {
    let notice: OperationNotice
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.symbol).foregroundStyle(notice.color).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title).font(.subheadline.bold())
                Text(notice.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(notice.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
struct BrandMark: View {
    var size: CGFloat = 56
    var body: some View {
        Image("BrandIcon").resizable().interpolation(.high).frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}
enum AppVersion {
    static var display: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v)（\(b)）"
    }
}
