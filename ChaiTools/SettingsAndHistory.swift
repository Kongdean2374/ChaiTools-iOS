import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var filter = ""
    @State private var deleteConfirmation = false
    @State private var clearHistoryConfirmation = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    var body: some View {
        NavigationStack {
            Form {
                Section("AI 連線") {
                    NavigationLink { connectionPage } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").foregroundStyle(InterfaceTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("金鑰與模型").font(.headline)
                                Text(model.hasKey ? model.preferences.model : "尚未設定金鑰").font(.caption).foregroundStyle(InterfaceTheme.secondaryText).lineLimit(1)
                            }
                        }.padding(.vertical, 6)
                    }
                }
                Section("鍵盤／使用") {
                    NavigationLink { KeyboardGuideView() } label: { Label("啟用與使用 AI 鍵盤", systemImage: "keyboard") }
                    LabeledContent("主 App 群組容器", value: model.sharingAvailable ? "可取得" : "無共享授權")
                    LabeledContent("鍵盤完整取用／群組", value: "請在鍵盤狀態頁確認")
                    LabeledContent("金鑰檔案", value: model.hasKey ? "存在" : "尚未設定")
                    LabeledContent("目前模型", value: model.connectionStatus)
                    DisclosureGroup(model.sharingAvailable ? "可與鍵盤共用" : "主 App 獨立儲存") {
                        Text(model.sharingAvailable ? "金鑰、偏好與紀錄可供鍵盤使用；鍵盤仍需完整取用權限。" : "目前沒有鍵盤共享權限，主 App 仍可儲存金鑰與紀錄、測試 API 及使用所有工具。鍵盤 AI 暫不可用，可在主 App 生成後複製。").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                    }
                }
                Section("資料與隱私") {
                    Toggle("保存工作紀錄", isOn: Binding(get: { model.preferences.history }, set: { enabled in
                        if enabled { model.setHistory(true) } else { clearHistoryConfirmation = true }
                    }))
                    Text("預設關閉 · 最多 7 天／50 筆").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                    NavigationLink { PrivacyGuideView() } label: { Label("資料如何處理", systemImage: "hand.raised") }
                }
                Section("外觀與互動") {
                    Picker("主 App 外觀", selection: $appearance) {
                        Text("跟隨系統").tag("system"); Text("淺色").tag("light"); Text("深色").tag("dark")
                    }
                    Toggle("主 App 觸覺回饋", isOn: $hapticsEnabled)
                    Text("鍵盤跟隨系統外觀；鍵盤觸覺可在其更多選單調整。減少動態效果沿用 iOS 設定。").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                }
                Section("關於") {
                    HStack { BrandMark(size: 32); Text("ChaiTools"); Spacer(); Text(AppVersion.display).font(.caption).foregroundStyle(InterfaceTheme.secondaryText) }
                    if let message = model.legacyCleanupMessage { DisclosureGroup("舊版資料清理狀態") { Text(message).font(.caption).foregroundStyle(InterfaceTheme.secondaryText) } }
                }
            }.appSurface().navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
                .alert(item: $model.alert) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了"))) }
                .confirmationDialog("關閉並清除所有工作紀錄？", isPresented: $clearHistoryConfirmation, titleVisibility: .visible) {
                    Button("關閉並清除", role: .destructive) { model.setHistory(false) }
                }
                .onAppear { model.load() }
        }
    }
    private var connectionPage: some View {
        Form { credentials; preferences }
            .appSurface().navigationTitle("AI 連線").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) { feedback }
            .alert(item: $model.alert) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了"))) }
            .confirmationDialog("刪除已儲存的 API 金鑰？", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("刪除金鑰", role: .destructive) { deleteConfirmation = false; model.deleteKey() }
            } message: { Text("刪除後需重新設定金鑰，本機計算仍可使用。") }
            .task(id: model.notice?.id) {
                guard let notice = model.notice, notice.kind != .failure, !model.busy else { return }
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled, model.notice?.id == notice.id { model.notice = nil }
            }
            .onDisappear { model.cancel() }
    }
    private func dismissKeyKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    private var credentials: some View {
        Section {
            Label(model.hasKey ? "已儲存金鑰" : "尚未設定金鑰", systemImage: model.hasKey ? "key.fill" : "key")
                .foregroundStyle(model.hasKey ? InterfaceTheme.accent : Color.secondary)
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
            if model.clipboardMayContainKey {
                Text("剪貼簿可能仍保留金鑰；請勿貼到普通文字區。").font(.caption)
                Button("清除目前剪貼簿") { model.clearClipboard() }.disabled(model.busy)
            }
            if let pasteNotice = model.pasteNotice { NoticeCard(notice: pasteNotice) }
            Button { dismissKeyKeyboard(); model.saveKey() } label: {
                Label("儲存金鑰", systemImage: "lock.shield").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(model.busy)
            Button { dismissKeyKeyboard(); model.testConnection() } label: {
                Label("測試 API 連線", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(model.busy)
            if model.hasKey {
                Button("刪除金鑰", role: .destructive) { deleteConfirmation = true }.disabled(model.busy)
            }
        } header: { Text("API 金鑰") } footer: {
            Text("金鑰存於 App 的加密保護檔案，排除備份；儲存後會讀回確認；測試會實際呼叫下方所選模型，可能產生少量 API 費用。新金鑰請先儲存再測試。")
        }
    }
    private var preferences: some View {
        Section {
            LabeledContent("模型") {
                SafeLabeledInput("模型 ID", text: $model.preferences.model, onBlocked: model.blocked).multilineTextAlignment(.trailing).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            LabeledContent("語言") { SafeLabeledInput("預設語言", text: $model.preferences.language, onBlocked: model.blocked).multilineTextAlignment(.trailing) }
            LabeledContent("語境") { SafeLabeledInput("例如：臺灣日常", text: $model.preferences.context, onBlocked: model.blocked).multilineTextAlignment(.trailing) }
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
                                HStack { Text(id); Spacer(); if model.preferences.model == id { Image(systemName: "checkmark.circle.fill").foregroundStyle(InterfaceTheme.accent) } }
                            }.buttonStyle(.plain)
                        }
                    }.appSurface().searchable(text: $filter.guarded(onBlocked: model.blocked), prompt: "搜尋模型 ID").navigationTitle("選擇模型")
                        .alert(item: $model.alert) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("知道了"))) }
                } label: { Label("選擇模型（\(model.models.count)）", systemImage: "list.bullet") }
            }
        } header: { Text("模型與偏好") } footer: {
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
            }.padding().background(CTBarSurface())
        } else if let notice = model.notice {
            HStack(alignment: .top, spacing: 4) {
                NoticeCard(notice: notice)
                Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("收起操作結果")
            }.padding(.horizontal).padding(.vertical, 6).background(CTBarSurface())
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
        }.appSurface().navigationTitle("鍵盤使用指南").navigationBarTitleDisplayMode(.inline)
    }
}
struct PrivacyGuideView: View {
    var body: some View {
        List {
            Section("只處理你主動送出的文字") { Text("只有按下執行時，選定內容與必要指令才會傳送至 OpenAI。鍵盤不會自動讀取剪貼簿，不會擷取整個聊天紀錄。") }
            Section("本機保存") { Text("金鑰保存在 App 的私有檔案；有共享權限時使用共享容器，否則使用主 App 本機空間，使用 iOS 完整檔案保護（鎖屏不可讀），排除備份。刪除 App 時會隨本 App 的容器清除；『卸載 App』會保留資料，不等同刪除。紀錄預設關閉；啟用後保留 7 天、50 筆，可隨時清除。沒有自建雲端資料庫或分析 SDK。") }
            Section("API 與費用") { Text("使用 store=false，但不代表 OpenAI 零資料保留。費用依帳號與模型計算；App 顯示的 token 用量不是帳務餘額。") }
            Section("金鑰保護") { Text("金鑰不進提示詞、工作紀錄、匯出或鍵盤插入；只用於 OpenAI HTTPS 授權。檔案保護無法消除裝置遭入侵的風險。主 App 不依賴共享權限；鍵盤需有一致的共享權限才能共用。讀寫失敗會顯示原因，不會假報成功。") }
        }.appSurface().navigationTitle("資料與隱私").navigationBarTitleDisplayMode(.inline)
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
            }.appSurface().searchable(text: $search.guarded(onBlocked: { error = SensitiveContentGuard.message }), prompt: "搜尋原文或結果").navigationTitle("工作紀錄").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("清空", role: .destructive) { confirm = true } }
                .confirmationDialog("清除所有工作紀錄？", isPresented: $confirm) { Button("清除", role: .destructive) { perform { try SharedStore.live().delete() } } }
                .onAppear { perform {} }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); tasks = try SharedStore.live().history() } catch { self.error = SensitiveContentGuard.userMessage(error) } }
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
                            HStack(spacing: 12) { Image(systemName: tool.icon).foregroundStyle(InterfaceTheme.accent).frame(width: 32); Text(tool.name); Spacer(); if tool.favorite { Image(systemName: "star.fill") }; Text(tool.enabled ? "顯示" : "隱藏").foregroundStyle(.secondary) }
                        }
                    }.onMove { source, destination in tools.move(fromOffsets: source, toOffset: destination); save() }
                        .onDelete { offsets in let builtin = Set(Tool.defaults.map(\.id)); tools = tools.enumerated().filter { !offsets.contains($0.offset) || builtin.contains($0.element.id) }.map(\.element); save() }
                }
                Section {
                    DisclosureGroup("匯入／匯出工具設定") {
                    SafeTextInput(text: $transfer, label: "工具匯入資料", onBlocked: { status = SensitiveContentGuard.message }).frame(height: 120)
                    Button("匯出並複製") {
                        do { try SensitiveContentGuard.validate(value: tools); transfer = String(decoding: try JSONEncoder().encode(tools), as: UTF8.self); UIPasteboard.general.string = try SensitiveContentGuard.checked(transfer); status = "已複製工具設定" } catch { status = SensitiveContentGuard.userMessage(error) }
                    }
                    PasteButton(payloadType: String.self) { values in
                        do { transfer = try SensitiveContentGuard.checked(values.joined(separator: "\n")) } catch { status = SensitiveContentGuard.message }
                    }
                    Button("匯入自訂工具") {
                        do {
                            guard transfer.utf8.count <= 100000 else { throw ChaiError.message("設定過大") }
                            let incoming = try JSONDecoder().decode([Tool].self, from: Data(transfer.utf8))
                            guard incoming.count <= 50, incoming.allSatisfy({ !$0.name.isEmpty && $0.prompt.count <= 8000 }) else { throw ChaiError.message("工具設定無效") }
                            try SensitiveContentGuard.validate(value: incoming)
                            for var tool in incoming { tool.id = UUID().uuidString; tools.append(tool) }
                            if save() { status = "已匯入 \(incoming.count) 個工具" }
                        } catch { status = SensitiveContentGuard.userMessage(error) }
                    }
                    Text(status)
                    }
                }
            }.appSurface().navigationTitle("我的工具").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    if !status.isEmpty { NoticeCard(notice: OperationNotice(title: "工具設定", message: status)).padding(.horizontal).padding(.vertical, 6).background(CTBarSurface()) }
                }
                .toolbar { EditButton(); Button("新增", systemImage: "plus") { editing = Tool(id: UUID().uuidString, name: "", icon: "wand.and.stars", prompt: "") } }
                .sheet(item: $editing) { tool in ToolEditor(tool: tool) { updated in
                    if let index = tools.firstIndex(where: { $0.id == updated.id }) { tools[index] = updated } else { tools.append(updated) }
                    save()
                } }
                .onAppear { do { tools = try SharedStore.live().preferences().tools } catch { status = SensitiveContentGuard.userMessage(error) } }
        }
    }
    @discardableResult private func save() -> Bool { do { try SharedStore.live().updatePreferences { $0.tools = tools }; status = try StorageLocation.current().isShared ? "工具設定已儲存；重新開啟鍵盤後同步。" : "工具設定已儲存在主 App；此版本無法與鍵盤共用。"; return true } catch { status = SensitiveContentGuard.userMessage(error); return false } }
}
struct ToolEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var warning = ""
    @State var tool: Tool
    var onSave: (Tool) -> Void
    private let symbols = ["wand.and.stars", "text.bubble", "doc.text", "envelope", "book", "lightbulb", "star", "bolt", "list.bullet", "pencil.line", "character.bubble", "globe"]
    private var validation: String? {
        if tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "請為工具取一個名稱。" }
        if tool.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "請填寫這個工具要做什麼。" }
        if tool.name.count > 40 || tool.prompt.count > 8000 { return "名稱最多 40 字；提示詞最多 8,000 字。" }
        if UIImage(systemName: tool.icon) == nil { return "請選擇有效的系統圖示。" }
        return nil
    }
    var body: some View {
        NavigationStack {
            Form {
                if !warning.isEmpty { Text(warning).font(.caption).foregroundStyle(.red) }
                Section("工具名稱與圖示") {
                    SafeLabeledInput("例如：禮貌回覆", text: $tool.name, onBlocked: { warning = SensitiveContentGuard.message })
                    Picker("圖示", selection: $tool.icon) {
                        ForEach(Array(Set(symbols + [tool.icon])).sorted(), id: \.self) { icon in Label(icon, systemImage: icon).tag(icon) }
                    }
                }
                Section("處理方式") {
                    SafeLabeledInput("描述如何處理輸入文字", text: $tool.prompt, onBlocked: { warning = SensitiveContentGuard.message }).lineLimit(4...10)
                    SafeLabeledInput("需要使用者提供什麼資料？", text: $tool.fields, onBlocked: { warning = SensitiveContentGuard.message })
                    SafeLabeledInput("輸出格式，例如：三個條列重點", text: $tool.format, onBlocked: { warning = SensitiveContentGuard.message })
                }
                Section("選項") {
                    SafeLabeledInput("模型 ID（空白沿用全域）", text: $tool.model, onBlocked: { warning = SensitiveContentGuard.message }).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("顯示於面板", isOn: $tool.enabled)
                    Toggle("常用收藏", isOn: $tool.favorite)
                }
                if let message = validation { Section { Label(message, systemImage: "info.circle").font(.caption).foregroundStyle(InterfaceTheme.secondaryText) } }
            }.appSurface().navigationTitle("工具設定").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存") {
                            tool.name = tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard (try? SensitiveContentGuard.validate(value: tool)) != nil else { warning = SensitiveContentGuard.message; return }
                            onSave(tool); AppHaptics.tap(); dismiss()
                        }.disabled(validation != nil)
                    }
                }
        }
    }
}
