import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var filter = ""
    @State private var deleteConfirmation = false
    @State private var clearHistoryConfirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        BrandMark()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("讓 ChaiTools 為你工作").font(.headline)
                            Text("金鑰 → 模型 → 測試連線").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6)
                }
                credentials
                preferences
                Section("隱私與紀錄") {
                    Toggle("保存工作紀錄", isOn: Binding(get: { model.preferences.history }, set: { enabled in
                        if enabled { model.setHistory(true) } else { clearHistoryConfirmation = true }
                    }))
                    Text("預設關閉。開啟後最多保留 7 天／50 筆；關閉會清除既有紀錄。").font(.caption).foregroundStyle(.secondary)
                    NavigationLink { PrivacyGuideView() } label: { Label("資料如何處理", systemImage: "hand.raised") }
                }
                Section("使用與關於") {
                    NavigationLink { KeyboardGuideView() } label: { Label("啟用與使用 AI 鍵盤", systemImage: "keyboard") }
                    HStack { Text("版本"); Spacer(); Text(AppVersion.display).foregroundStyle(.secondary) }
                    Text("原生 AI 工作台 · 由你決定何時送出").font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("設定")
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .top, spacing: 0) { feedback }
                .alert(item: $model.alert) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了"))) }
                .confirmationDialog("刪除已儲存的 API 金鑰？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                    Button("刪除金鑰", role: .destructive) { model.deleteKey() }
                } message: { Text("刪除後 AI 功能會停止，直到重新設定金鑰。") }
                .confirmationDialog("關閉並清除所有工作紀錄？", isPresented: $clearHistoryConfirmation, titleVisibility: .visible) {
                    Button("關閉並清除", role: .destructive) { model.setHistory(false) }
                }
                .onAppear { model.load() }
                .onDisappear { model.cancel() }
        }
    }
    private func dismissKeyKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private var credentials: some View {
        Section {
            Label(model.hasKey ? "已儲存金鑰" : "尚未設定金鑰", systemImage: model.hasKey ? "key.fill" : "key")
                .foregroundStyle(model.hasKey ? Color.teal : Color.secondary)
            APIKeyTextField(text: $model.key, placeholder: model.hasKey ? "輸入新金鑰以替換" : "貼上 OpenAI API 金鑰", isEnabled: !model.busy)
                .frame(minHeight: 44).privacySensitive()
            HStack {
                Button { dismissKeyKeyboard(); model.pasteKey() } label: {
                    Label("貼上金鑰", systemImage: "doc.on.clipboard")
                }.buttonStyle(.bordered).disabled(model.busy)
                Spacer()
                Button("清空輸入") { model.clearKeyInput() }
                    .buttonStyle(.borderless).disabled(model.busy || model.key.isEmpty)
            }
            Text(model.key.isEmpty ? "可長按輸入框貼上，或點『貼上金鑰』。" : "輸入欄已有 \(model.key.count) 個字元，尚未儲存。")
                .font(.caption).foregroundStyle(.secondary)
            if let pasteNotice = model.pasteNotice { NoticeCard(notice: pasteNotice) }
            Button { dismissKeyKeyboard(); model.saveKey() } label: {
                Label("儲存金鑰", systemImage: "lock.shield").frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).disabled(model.busy)
            Button { dismissKeyKeyboard(); model.testConnection() } label: {
                Label("測試 API 連線", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.bordered).disabled(model.busy)
            if model.hasKey {
                Button("刪除金鑰", role: .destructive) { deleteConfirmation = true }.disabled(model.busy)
            }
        } header: { Text("01 · 連線設定") } footer: {
            Text("金鑰存於 App 的加密保護檔案，排除備份；儲存後會讀回確認；測試會實際呼叫下方所選模型，可能產生少量 API 費用。新金鑰請先儲存再測試。")
        }
    }
    private var preferences: some View {
        Section {
            LabeledContent("模型") {
                TextField("模型 ID", text: $model.preferences.model).multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            LabeledContent("語言") { TextField("預設語言", text: $model.preferences.language).multilineTextAlignment(.trailing) }
            LabeledContent("語境") { TextField("例如：臺灣日常", text: $model.preferences.context).multilineTextAlignment(.trailing) }
            Button { dismissKeyKeyboard(); model.savePreferences() } label: { Label("儲存偏好", systemImage: "checkmark.circle") }
            Button { dismissKeyKeyboard(); model.scanModels() } label: { Label("掃描可用模型", systemImage: "arrow.clockwise") }
            if !model.models.isEmpty {
                NavigationLink {
                    List {
                        ForEach(model.models.filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }, id: \.self) { id in
                            Button {
                                model.preferences.model = id
                                model.savePreferences()
                            } label: {
                                HStack { Text(id); Spacer(); if model.preferences.model == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) } }
                            }.buttonStyle(.plain)
                        }
                    }.searchable(text: $filter, prompt: "搜尋模型 ID").navigationTitle("選擇模型")
                        .alert(item: $model.alert) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了"))) }
                } label: { Label("選擇模型（\(model.models.count)）", systemImage: "list.bullet") }
            }
        } header: { Text("02 · 模型與偏好") } footer: {
            Text("掃描結果代表帳號可看見模型，不保證支援網路搜尋等每項工具。選擇模型後可再次測試連線。")
        }.disabled(model.busy)
    }
    @ViewBuilder private var feedback: some View {
        if let title = model.activity {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.subheadline.bold())
                        TimelineView(.periodic(from: model.started, by: 1)) { context in
                            Text("已等待 \(max(0, Int(context.date.timeIntervalSince(model.started)))) 秒 · 最長約 60 秒").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("取消") { model.cancel() }.buttonStyle(.bordered)
                }
            }.padding().background(.regularMaterial)
        } else if let notice = model.notice {
            HStack(alignment: .top, spacing: 4) {
                NoticeCard(notice: notice)
                Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("收起操作結果")
            }.padding(.horizontal).padding(.vertical, 6).background(.regularMaterial)
        }
    }
}
struct KeyboardGuideView: View {
    var body: some View {
        List {
            Section {
                Label("1. 加入鍵盤", systemImage: "keyboard").font(.headline)
                Text("iOS 設定 → 一般 → 鍵盤 → 鍵盤 → 新增鍵盤 → ChaiTools。")
                Label("2. 開啟完整取用", systemImage: "network").font(.headline)
                Text("在 ChaiTools 鍵盤設定開啟『允許完整取用』，才能使用 AI 網路請求與共享資料。")
                Label("3. 貼上並處理", systemImage: "doc.on.clipboard").font(.headline)
                Text("複製要處理的文字 → 長按地球鍵切換 ChaiTools → 選工具 → 貼上 → 執行。")
                Label("4. 確認後插入", systemImage: "checkmark.bubble").font(.headline)
                Text("先預覽、修訂，再複製或插入。插入不會自動送出訊息。")
            }
            Section("使用界線") {
                Text("密碼欄位、部分電話欄位及禁止第三方鍵盤的 App 無法使用。選取文字可能取不到，請使用複製、貼上流程。")
                Text("中文自由編輯可在主 App 或其他輸入法完成後貼上；長篇處理建議使用主 App。")
            }
        }.navigationTitle("鍵盤使用指南").navigationBarTitleDisplayMode(.inline)
    }
}
struct PrivacyGuideView: View {
    var body: some View {
        List {
            Section("只處理你主動送出的文字") { Text("只有按下執行時，選定內容與必要指令才會傳送至 OpenAI。鍵盤不會自動讀取剪貼簿，不會擷取整個聊天紀錄。") }
            Section("本機保存") { Text("金鑰只保存在 App 私有共享容器的檔案，使用 iOS 完整檔案保護（鎖屏不可讀），排除備份。刪除 App 時會隨本 App 的容器清除；『卸載 App』會保留資料，不等同刪除。紀錄預設關閉；啟用後保留 7 天、50 筆，可隨時清除。沒有自建雲端資料庫或分析 SDK。") }
            Section("API 與費用") { Text("使用 store=false，但不代表 OpenAI 零資料保留。費用依帳號與模型計算；App 顯示的 token 用量不是帳務餘額。") }
            Section("金鑰保護") { Text("金鑰不進提示詞、工作紀錄、匯出或鍵盤插入；只用於 OpenAI HTTPS 授權。檔案保護無法消除裝置遭入侵的風險。App 與鍵盤的共享權限必須一致；讀寫失敗會顯示原因，不會假報成功。") }
        }.navigationTitle("資料與隱私").navigationBarTitleDisplayMode(.inline)
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
                .safeAreaInset(edge: .top) {
                    if !status.isEmpty { NoticeCard(notice: OperationNotice(title: "工具設定", message: status)).padding(.horizontal).padding(.vertical, 6).background(.regularMaterial) }
                }
                .toolbar { EditButton(); Button("新增", systemImage: "plus") { editing = Tool(id: UUID().uuidString, name: "", icon: "wand.and.stars", prompt: "") } }
                .sheet(item: $editing) { tool in ToolEditor(tool: tool) { updated in
                    if let index = tools.firstIndex(where: { $0.id == updated.id }) { tools[index] = updated } else { tools.append(updated) }
                    save()
                } }
                .onAppear { do { tools = try SharedStore.live().preferences().tools } catch { status = error.localizedDescription } }
        }
    }
    private func save() { do { try SharedStore.live().updatePreferences { $0.tools = tools }; status = "工具設定已儲存；重新開啟鍵盤後同步。" } catch { status = error.localizedDescription } }
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
