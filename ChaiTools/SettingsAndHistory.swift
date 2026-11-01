import SwiftUI

struct SettingsView: View {
    @State private var p = Preferences()
    @State private var key = ""
    @State private var status = ""
    @State private var models: [String] = []
    @State private var filter = ""
    @State private var busy = false
    @State private var operation: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("API 金鑰 · 僅存於本機 Keychain") {
                    SecureField("輸入 OpenAI API 金鑰", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("儲存／變更金鑰") { perform { try Keychain.save(key); key = ""; status = "金鑰已存入 Keychain；尚未驗證連線。" } }
                    Button("刪除金鑰", role: .destructive) { perform { try Keychain.delete(); key = ""; status = "已刪除金鑰" } }
                    Button("測試連線／重新測試") {
                        start {
                            let answer = try await AIClient().run(tool: Tool(id: "test", name: "連線測試", icon: "checkmark", prompt: "只回覆 OK。"), source: "連線測試", instruction: "簡短回覆", preferences: p, key: Keychain.load())
                            status = "已取得 \(p.model) 的真實回應；使用 \(answer.inputTokens + answer.outputTokens) tokens。"
                        }
                    }
                    Text("測試會呼叫所選模型，可能產生少量 API 費用。金鑰不會出現在原始碼或建置設定。 ").font(.caption)
                }.disabled(busy)
                Section("模型與偏好") {
                    TextField("模型 ID", text: $p.model).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("預設語言", text: $p.language)
                    TextField("預設語境", text: $p.context)
                    Button("儲存偏好") { perform { try SharedStore.live().updatePreferences { $0.model = p.model; $0.language = p.language; $0.context = p.context }; status = "偏好已儲存" } }
                    Button("掃描可存取模型") { start { models = try await AIClient().models(key: Keychain.load()); status = "取得 \(models.count) 個模型；列出不代表支援所有工具。" } }.disabled(busy)
                    TextField("搜尋模型", text: $filter)
                    ForEach(models.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }, id: \.self) { id in
                        Button(id) { p.model = id }
                    }
                }
                Section("隱私與紀錄") {
                    Toggle("保存工作紀錄（最多 7 天／50 筆）", isOn: Binding(get: { p.history }, set: { enabled in
                        perform { try SharedStore.live().updatePreferences { $0.history = enabled }; p.history = enabled }
                    }))
                    Text("預設不保存原文。關閉紀錄會清除既有紀錄。啟用後 App 與鍵盤共用紀錄，版本最多 30 版。只有按下執行才送出內容至 OpenAI；store=false 不等同零資料保留。客戶端 Keychain 仍有裝置遭入侵的風險。").font(.caption)
                }
                Section("鍵盤使用說明") {
                    Text("iOS 設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → ChaiTools。需要 AI 時開啟『允許完整取用』。輸入框長按地球鍵切換。\n在其他 App 複製中文 → ChaiTools 點貼上 → 選工具 → 執行 → 預覽 → 插入或複製。\n鍵盤內使用貼上與快捷指令，長篇編輯請使用主 App。密碼欄位與禁止第三方鍵盤的 App 無法使用。")
                }
                Section("狀態") {
                    if busy { ProgressView(); Button("取消") { operation?.cancel() } }
                    Text(status.isEmpty ? "尚未測試連線" : status).textSelection(.enabled)
                    Text("ChaiTools 1.0.0 · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")")
                }
            }.navigationTitle("設定")
                .onAppear { perform { p = try SharedStore.live().preferences() } }
                .onDisappear { operation?.cancel() }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    private func start(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        operation = Task { @MainActor in
            defer { busy = false }
            do { try await action() } catch { status = error.localizedDescription }
        }
    }
}
struct HistoryView: View {
    @State private var tasks: [WorkTask] = []
    @State private var search = ""
    @State private var error = ""
    @State private var limit = 20
    @State private var confirm = false
    var body: some View {
        NavigationStack {
            List {
                Text("紀錄預設關閉；開啟後保存 7 天。未送出的草稿請明確儲存。 ").font(.caption)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                ForEach(Array(tasks.filter { search.isEmpty || $0.source.localizedCaseInsensitiveContains(search) || ($0.answer?.text.localizedCaseInsensitiveContains(search) ?? false) }.prefix(limit))) { item in
                    NavigationLink { ToolWorkspace(tool: item.tool, task: item) } label: {
                        VStack(alignment: .leading) {
                            Text((item.favorite ? "★ " : "") + item.tool.name).font(.headline)
                            Text(item.source.isEmpty ? item.answer?.text ?? "草稿" : item.source).lineLimit(2)
                            Text(item.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions {
                        Button("刪除", role: .destructive) { perform { try SharedStore.live().delete(item.id) } }
                        Button("收藏") { var changed = item; changed.favorite.toggle(); perform { try SharedStore.live().save(changed) } }.tint(.orange)
                    }
                }
                if tasks.count > limit { Button("載入更多") { limit += 20 } }
                if tasks.isEmpty { ContentUnavailableView("沒有工作紀錄", systemImage: "clock", description: Text("可在設定開啟；隱私模式不永久保存。")) }
            }.searchable(text: $search, prompt: "搜尋原文或結果").navigationTitle("工作紀錄")
                .toolbar { Button("清空", role: .destructive) { confirm = true } }
                .confirmationDialog("清除所有工作紀錄？", isPresented: $confirm) { Button("清除", role: .destructive) { perform { try SharedStore.live().delete() } } }
                .onAppear { perform {} }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); tasks = try SharedStore.live().history() } catch { self.error = error.localizedDescription } }
}
struct ManageToolsView: View {
    @State private var tools = Tool.defaults
    @State private var editing: Tool?
    @State private var transfer = ""
    @State private var status = ""
    var body: some View {
        NavigationStack {
            List {
                Section("拖曳排列 · 左滑刪除自訂工具") {
                    ForEach(tools) { tool in
                        Button { editing = tool } label: {
                            HStack { Image(systemName: tool.icon); Text(tool.name); Spacer(); if tool.favorite { Image(systemName: "star.fill") }; Text(tool.enabled ? "顯示" : "隱藏").foregroundStyle(.secondary) }
                        }
                    }.onMove { source, destination in tools.move(fromOffsets: source, toOffset: destination); save() }
                        .onDelete { offsets in let builtin = Set(Tool.defaults.map(\.id)); tools = tools.enumerated().filter { !offsets.contains($0.offset) || builtin.contains($0.element.id) }.map(\.element); save() }
                }
                Section("匯入／匯出文字設定（不含金鑰）") {
                    TextEditor(text: $transfer).frame(height: 120)
                    Button("匯出並複製") {
                        do { transfer = String(decoding: try JSONEncoder().encode(tools), as: UTF8.self); UIPasteboard.general.string = transfer; status = "已複製工具設定" } catch { status = error.localizedDescription }
                    }
                    PasteButton(payloadType: String.self) { transfer = $0.joined(separator: "\n") }
                    Button("匯入自訂工具") {
                        do {
                            guard transfer.utf8.count <= 100000 else { throw ChaiError.message("設定過大") }
                            let incoming = try JSONDecoder().decode([Tool].self, from: Data(transfer.utf8))
                            guard incoming.count <= 50, incoming.allSatisfy({ !$0.name.isEmpty && $0.prompt.count <= 8000 }) else { throw ChaiError.message("工具設定無效") }
                            for var tool in incoming { tool.id = UUID().uuidString; tools.append(tool) }
                            save(); status = "已匯入 \(incoming.count) 個工具"
                        } catch { status = error.localizedDescription }
                    }
                    Text(status)
                }
            }.navigationTitle("我的工具")
                .toolbar { EditButton(); Button("新增", systemImage: "plus") { editing = Tool(id: UUID().uuidString, name: "", icon: "wand.and.stars", prompt: "") } }
                .sheet(item: $editing) { tool in ToolEditor(tool: tool) { updated in
                    if let index = tools.firstIndex(where: { $0.id == updated.id }) { tools[index] = updated } else { tools.append(updated) }
                    save()
                } }
                .onAppear { do { tools = try SharedStore.live().preferences().tools } catch { status = error.localizedDescription } }
        }
    }
    private func save() { do { try SharedStore.live().updatePreferences { $0.tools = tools } } catch { status = error.localizedDescription } }
}
struct ToolEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var tool: Tool
    var onSave: (Tool) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("名稱", text: $tool.name)
                TextField("圖示（SF Symbol）", text: $tool.icon)
                TextField("說明與提示詞", text: $tool.prompt, axis: .vertical)
                TextField("輸入欄位說明", text: $tool.fields, axis: .vertical)
                TextField("輸出格式", text: $tool.format)
                TextField("模型覆寫（空白沿用全域）", text: $tool.model).textInputAutocapitalization(.never)
                Toggle("顯示於面板", isOn: $tool.enabled)
                Toggle("常用收藏", isOn: $tool.favorite)
            }.navigationTitle("工具設定")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("儲存") { onSave(tool); dismiss() }.disabled(tool.name.isEmpty || tool.prompt.isEmpty) } }
        }
    }
}
