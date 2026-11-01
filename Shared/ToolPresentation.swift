#if canImport(SwiftUI) && os(iOS)
import SwiftUI
extension Tool {
    var actionTitle: String {
        switch id {
        case "translate": return "翻譯"
        case "rewrite": return "改寫"
        case "generate": return "生成"
        case "search": return "搜尋"
        case "calculate": return "計算"
        case "language": return "解析"
        case "summary": return "整理"
        default: return "執行"
        }
    }
    var subtitle: String {
        switch id {
        case "translate": return "自然譯文與語境解析"
        case "rewrite": return "保留原意，調整表達"
        case "generate": return "從想法開始寫作"
        case "search": return "查詢資訊，保留來源"
        case "calculate": return "離線算式與單位換算"
        case "language": return "讀懂語法、口語與俚語"
        case "summary": return "長文重點，一目了然"
        default: return "你的提示詞，你的工作方式"
        }
    }
    var accent: Color {
        switch id {
        case "translate", "language": return InterfaceTheme.accent
        case "rewrite", "generate": return InterfaceTheme.accent
        case "search": return InterfaceTheme.accent
        case "calculate": return .orange
        case "summary": return .purple
        default: return .pink
        }
    }
}

#endif
