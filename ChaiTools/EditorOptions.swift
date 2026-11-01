import SwiftUI

struct EditorOptions {
    var detailed = false
    var tone = "自然"
    var length = "適中"
    var kind = "一般訊息"
    var audience = ""
    var constraints = ""
    var keepFormat = true
    var correctGrammar = true
    var sourceLanguage = "自動偵測"
    var prompt: String {
        "\(detailed ? "詳細模式" : "快速模式")；來源語言：\(sourceLanguage)；語氣：\(tone)；長度：\(length)；格式：\(kind)；對象：\(audience)；\(constraints)；保留格式：\(keepFormat)；修正文法：\(correctGrammar)。"
    }
}
struct EditorOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let tool: Tool
    @Binding var preferences: Preferences
    @Binding var options: EditorOptions
    var body: some View {
        NavigationStack {
            Form {
                Section("語言與情境") {
                    TextField("目標語言", text: $preferences.language)
                    TextField("語境／對象", text: $preferences.context)
                    if tool.id == "translate" {
                        TextField("來源語言", text: $options.sourceLanguage)
                        Toggle("詳細翻譯解析", isOn: $options.detailed)
                    }
                    if tool.id == "language" { Toggle("詳細學習模式", isOn: $options.detailed) }
                }
                if ["rewrite", "generate", "custom"].contains(tool.id) {
                    Section("表達方式") {
                        Picker("語氣", selection: $options.tone) { ForEach(["自然", "正式", "可愛", "禮貌", "簡短", "詳細", "流暢", "專業", "社群風格", "遊戲聊天"], id: \.self) { Text($0) } }
                        Picker("長度", selection: $options.length) { ForEach(["精簡", "適中", "詳細"], id: \.self) { Text($0) } }
                        Toggle("保留原格式", isOn: $options.keepFormat)
                        Toggle("修正文法", isOn: $options.correctGrammar)
                    }
                }
                if tool.id == "generate" {
                    Section("寫作需求") {
                        Picker("類型", selection: $options.kind) { ForEach(["一般訊息", "Email 草稿", "文章", "摘要", "公告", "說明文", "創意文案", "社群貼文", "自由格式"], id: \.self) { Text($0) } }
                        TextField("讀者對象", text: $options.audience)
                        TextField("必須包含／避免的內容", text: $options.constraints, axis: .vertical)
                    }
                }
                if tool.id == "summary" {
                    Section("整理方式") {
                        Picker("格式", selection: $options.kind) { ForEach(["一般訊息", "摘要", "條列重點", "待辦清單", "表格式整理", "提取指定資訊", "排版校正"], id: \.self) { Text($0) } }
                    }
                }
            }.appSurface().navigationTitle("情境設定").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
