import Foundation

struct Tool: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var prompt: String
    var model: String = ""
    var enabled = true
    var favorite = false
    var fields = ""
    var format = ""
    static let defaults: [Tool] = [
        Tool(id: "translate", name: "智慧翻譯", icon: "character.bubble", prompt: "翻譯文字。判斷語境，I'm down 在邀約可能代表願意，thx/gg/brb 要解釋，THK 不確定時明示，不能認定唯一意思。詳細模式回傳 JSON：natural（自然譯文）、literal（直譯）、context（可能語境）、native（母語說法）、slang（縮寫俚語）、grammar（文法）、tone（禮貌與誤會）、alternatives（1至3種說法字串陣列）。快速模式只回自然譯文。"),
        Tool(id: "rewrite", name: "文字改寫", icon: "pencil.line", prompt: "按指定語氣與長度改寫，保留原意與事實。"),
        Tool(id: "generate", name: "文章生成", icon: "doc.badge.plus", prompt: "依主題、類型、對象及要求撰寫新內容。不需原文。"),
        Tool(id: "search", name: "網路搜尋", icon: "globe", prompt: "必須使用 web_search 搜尋，根據實際來源回答並附引用。無法查詢時明示，不使用舊知識冒充即時資訊。"),
        Tool(id: "calculate", name: "智慧計算", icon: "function", prompt: "將數學題轉成 JSON：expression（只含數字、+-*/()%）、unit（單位）、steps（推導說明字串）。不自行計算最終答案，不提供即時匯率或市場行情。"),
        Tool(id: "language", name: "語言解析", icon: "text.book.closed", prompt: "解析語意、文法、俚語、縮寫、常見搭配、誤解風險，給出母語表達與自然改寫。"),
        Tool(id: "summary", name: "摘要整理", icon: "list.bullet.rectangle", prompt: "依指定格式摘要、列重點、待辦或提取資訊。嚴格保留原文事實，不補造資訊。"),
        Tool(id: "custom", name: "自訂工具", icon: "slider.horizontal.3", prompt: "依使用者的追加指令處理文字。")
    ]
}
struct Preferences: Codable {
    var model = "gpt-6.1-terra"
    var language = "繁體中文（臺灣）"
    var context = "臺灣日常"
    var history = false
    var tools = Tool.defaults
}
struct Citation: Codable, Identifiable, Equatable {
    var title: String
    var url: String
    var id: String { url }
}
struct Answer: Codable, Equatable {
    var text: String
    var details: [String: String] = [:]
    var citations: [Citation] = []
    var inputTokens = 0
    var outputTokens = 0
    var searched = false
}
struct Revision: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var instruction: String
    var answer: Answer
}
struct WorkTask: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var tool: Tool
    var source: String
    var revisions: [Revision] = []
    var selected = 0
    var favorite = false
    mutating func append(_ answer: Answer, instruction: String) {
        revisions.append(Revision(instruction: instruction, answer: answer))
        if revisions.count > 30 { revisions.removeFirst() }
        selected = revisions.count - 1
    }
    var answer: Answer? { revisions.indices.contains(selected) ? revisions[selected].answer : nil }
}
enum ChaiError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
