import SwiftUI
import UIKit

@main struct ChaiToolsApp: App {
    var body: some Scene { WindowGroup { RootView() } }
}
struct RootView: View {
    @AppStorage("welcomed") private var welcomed = false
    @State private var cleanupError = ""
    var body: some View {
        TabView {
            ToolListView().tabItem { Label("工具", systemImage: "square.grid.2x2") }
            HistoryView().tabItem { Label("工作紀錄", systemImage: "clock") }
            ManageToolsView().tabItem { Label("我的工具", systemImage: "slider.horizontal.3") }
            SettingsView().tabItem { Label("設定", systemImage: "gearshape") }
        }
        .tint(.teal)
        .task {
            do { try LegacyCredentialCleanup.runOnce() }
            catch { cleanupError = error.localizedDescription }
        }
        .safeAreaInset(edge: .top) {
            if !cleanupError.isEmpty { NoticeCard(notice: OperationNotice(title: "舊版金鑰清除未完成", message: cleanupError, kind: .failure)).padding().background(.regularMaterial) }
        }
        .sheet(isPresented: Binding(get: { !welcomed }, set: { welcomed = !$0 })) {
            VStack(spacing: 24) {
                BrandMark(size: 88)
                Text("歡迎使用 ChaiTools").font(.largeTitle.bold())
                Text("原生 AI 工作台與工具型鍵盤\n貼上 → 處理 → 預覽 → 複製或插入").multilineTextAlignment(.center)
                Text("AI 功能會將你主動送出的文字傳至 OpenAI，可能產生 API 費用。預設不保存工作紀錄。沒有金鑰仍可瀏覽與本機計算。")
                Button("開始使用／稍後設定金鑰") { welcomed = true }.buttonStyle(.borderedProminent)
            }.padding(28)
        }
    }
}
struct ToolListView: View {
    @State private var preferences = Preferences()
    @State private var error = ""
    @State private var query = ""
    @State private var hasKey = false
    @State private var showSettings = false
    private var visible: [Tool] {
        preferences.tools.filter { $0.enabled && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.favorite && !$1.favorite }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    if !error.isEmpty { NoticeCard(notice: OperationNotice(title: "設定需要確認", message: error, kind: .failure)) }
                    if !hasKey {
                        Button { showSettings = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill").font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("連接你的 AI").font(.headline)
                                    Text("設定金鑰後開始使用；本機計算無需連線。點此設定 →").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding().background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain)
                    }
                    HStack { Text(query.isEmpty ? "選擇你的工具" : "搜尋結果").font(.title3.bold()); Spacer(); Text("\(visible.count) 項").font(.caption).foregroundStyle(.secondary) }
                    if visible.isEmpty {
                        ContentUnavailableView("沒有符合的工具", systemImage: "magnifyingglass", description: Text("試試其他關鍵字，或在『我的工具』啟用工具。"))
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(visible) { tool in
                            NavigationLink { ToolWorkspace(tool: tool) } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Image(systemName: tool.icon).font(.title3.weight(.semibold)).foregroundStyle(tool.accent)
                                            .frame(width: 44, height: 44).background(tool.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                        Spacer()
                                        if tool.favorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(tool.name).font(.headline).foregroundStyle(.primary)
                                        Text(tool.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                    HStack { Text(tool.id == "calculate" ? "支援離線" : "AI 工具").font(.caption2); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }.foregroundStyle(tool.accent)
                                }.padding(18).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.045), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                    NavigationLink { KeyboardGuideView() } label: {
                        Label("在其他 App 也能使用 · 鍵盤指南", systemImage: "keyboard").font(.subheadline).frame(maxWidth: .infinity).padding()
                    }.buttonStyle(.bordered)
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("ChaiTools")
                .searchable(text: $query, prompt: "搜尋翻譯、改寫、計算⋯")
                .sheet(isPresented: $showSettings, onDismiss: { hasKey = (try? CredentialStore.hasKey()) == true }) { SettingsView() }
                .onAppear {
                    error = ""
                    do { preferences = try SharedStore.live().preferences() } catch { self.error = error.localizedDescription }
                    do { hasKey = try CredentialStore.hasKey() } catch { self.error = error.localizedDescription }
                }
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { BrandMark(size: 48); Spacer(); Label("你的文字工作台", systemImage: "sparkles").font(.caption.weight(.medium)) }
            Text("把想法，\n化成好表達。").font(.system(.largeTitle, design: .rounded).bold()).fixedSize(horizontal: false, vertical: true)
            Text("翻譯、寫作、整理，一處完成。\n先預覽，再由你決定如何使用。").font(.subheadline).opacity(0.85)
            HStack { Label("主動送出才處理", systemImage: "hand.raised"); Spacer(); Text(preferences.history ? "紀錄已開啟" : "隱私模式") }.font(.caption)
        }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.04, green: 0.27, blue: 0.29), Color(red: 0.06, green: 0.44, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
    }
}
struct ToolWorkspace: View {
    @StateObject private var model: WorkspaceModel
    @State private var preferences = Preferences()
    @State private var detail = false
    @State private var tone = "自然"
    @State private var length = "適中"
    @State private var kind = "一般訊息"
    @State private var audience = ""
    @State private var constraints = ""
    @State private var keepFormat = true
    @State private var correctGrammar = true
    @State private var from = "m"
    @State private var to = "cm"
    @State private var clearConfirmation = false
    @State private var originalLanguage = "自動偵測"
    init(tool: Tool, task: WorkTask? = nil) { _model = StateObject(wrappedValue: WorkspaceModel(tool: tool, task: task)) }
    var body: some View {
        Form {
            Section(model.task.tool.id == "generate" ? "主題／要求（可不提供原文）" : "來源文字 · \(model.task.source.count) 字") {
                TextEditor(text: $model.task.source).frame(minHeight: 140).disabled(model.busy)
                PasteButton(payloadType: String.self) { strings in model.task.source = strings.joined(separator: "\n") }
                    .disabled(model.busy)
                Text("局部改寫：將要改寫的段落放入來源欄，確認結果後自行替換原文。 ").font(.caption).foregroundStyle(.secondary)
            }
            Section("工具設定") {
                TextField("目標語言", text: $preferences.language)
                TextField("語境／對象", text: $preferences.context)
                if model.task.tool.id == "translate" {
                    TextField("來源語言", text: $originalLanguage)
                    Toggle("詳細翻譯解析", isOn: $detail)
                }
                if ["rewrite","generate","custom"].contains(model.task.tool.id) {
                    Picker("語氣", selection: $tone) { ForEach(["自然","正式","可愛","禮貌","簡短","詳細","流暢","專業","社群風格","遊戲聊天"], id: \.self) { Text($0) } }
                    Picker("長度", selection: $length) { ForEach(["精簡","適中","詳細"], id: \.self) { Text($0) } }
                    Toggle("保留原格式", isOn: $keepFormat)
                    Toggle("修正文法", isOn: $correctGrammar)
                }
                if model.task.tool.id == "generate" {
                    Picker("類型", selection: $kind) { ForEach(["一般訊息","Email 草稿","文章","摘要","公告","說明文","創意文案","社群貼文","自由格式"], id: \.self) { Text($0) } }
                    TextField("讀者對象", text: $audience)
                    TextField("必須包含／避免的內容", text: $constraints, axis: .vertical)
                }
                if model.task.tool.id == "summary" {
                    Picker("整理方式", selection: $kind) { ForEach(["一般訊息","摘要","條列重點","待辦清單","表格式整理","提取指定資訊","排版校正"], id: \.self) { Text($0) } }
                }
                if model.task.tool.id == "language" { Toggle("詳細學習模式", isOn: $detail) }
                if model.task.tool.id == "search" { Text("搜尋使用 web_search，可能產生額外工具費用。可在要求中限定網站與日期；不保證模型／帳號支援。").font(.caption) }
                if model.task.tool.id == "calculate" {
                    Text("支援 + − * /、括號、百分比。百分比是 ÷100；例如 200*(1+10%)。自然語言題才會送往 AI。即時匯率與行情不提供。")
                    HStack {
                        Picker("從", selection: $from) { ForEach(["m","cm","km","in","ft","kg","g","lb","°C","°F"], id: \.self) { Text($0) } }
                        Picker("至", selection: $to) { ForEach(["m","cm","km","in","ft","kg","g","lb","°C","°F"], id: \.self) { Text($0) } }
                    }
                    Button("本機單位換算") {
                        do { let v = try Calculator.evaluate(model.task.source); let converted = try Calculator.convert(v, from: from, to: to); model.accept(Answer(text: "\(v) \(from) = \(converted) \(to)")) } catch { model.error = error.localizedDescription }
                    }
                    Button("圓面積公式（將半徑填入算式）") { model.task.source = "3.141592653589793 * (1 * 1)" }
                }
                TextField("自訂要求／追加指令", text: $model.instruction, axis: .vertical)
            }
            Section {
                Text("送出約 \(model.task.source.count + model.instruction.count) 字；不代表確切 token 或帳務費用。").font(.caption)
                if model.busy { HStack { ProgressView(); Button("取消") { model.cancel() } } }
                else { Button("執行／重新生成") { execute() }.buttonStyle(.borderedProminent) }
                if !model.error.isEmpty { Text(model.error).foregroundStyle(.red) }
            }
            if !model.task.revisions.isEmpty {
                Section("結果 · 可直接編輯") {
                    TextEditor(text: $model.result).frame(minHeight: 180).disabled(model.busy)
                    HStack {
                        Button("複製") { UIPasteboard.general.string = model.result; model.status = "已複製結果"; UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        Button("儲存編輯版本") { model.saveEdit(model.result) }
                    }
                    ResultDetails(answer: model.task.answer)
                    Text("本次 API 使用量：輸入 \(model.task.answer?.inputTokens ?? 0)／輸出 \(model.task.answer?.outputTokens ?? 0) tokens；不是帳務餘額。").font(.caption)
                }
                Section("繼續修改") {
                    ScrollView(.horizontal) {
                        HStack { ForEach(["更自然","更精簡","更正式","口語化","補充細節","保留原意"], id: \.self) { chip in
                            Button(chip) { model.instruction = chip; model.run(preferences: preferences, revision: true) }.buttonStyle(.bordered)
                        } }
                    }
                    Button("依追加指令修訂目前結果") { model.run(preferences: preferences, revision: true) }
                    Picker("版本", selection: Binding(get: { model.task.selected }, set: { model.select($0) })) {
                        ForEach(Array(model.task.revisions.enumerated()), id: \.element.id) { i, rev in Text("第 \(i + 1) 版 · \(rev.date.formatted(date: .omitted, time: .shortened))").tag(i) }
                    }
                    if model.task.selected > 0 {
                        DisclosureGroup("與上一版對照") { Text(model.task.revisions[model.task.selected - 1].answer.text).textSelection(.enabled) }
                    }
                }.disabled(model.busy)
            }
            Section { Button("儲存草稿（需開啟紀錄）") { model.persist(manual: true) }; Button("清空工作區", role: .destructive) { clearConfirmation = true } }
        }.navigationTitle(model.task.tool.name)
            .buttonStyle(.borderless)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.busy {
                    HStack { ProgressView(); Text("正在處理，請稍候⋯").font(.subheadline); Spacer(); Button("取消") { model.cancel() } }.padding().background(.regularMaterial)
                } else if !model.error.isEmpty || !model.status.isEmpty {
                    NoticeCard(notice: OperationNotice(title: model.error.isEmpty ? "操作完成" : "需要處理", message: model.error.isEmpty ? model.status : model.error, kind: model.error.isEmpty ? .success : .failure)).padding(.horizontal).padding(.vertical, 6).background(.regularMaterial)
                }
            }
            .confirmationDialog("清空目前原文與所有未儲存版本？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("清空工作區", role: .destructive) { model.clear() }
            }
            .onAppear { do { preferences = try SharedStore.live().preferences() } catch { model.error = error.localizedDescription } }
            .onDisappear { model.cancel() }
    }
    private func execute() {
        let custom = model.instruction
        model.instruction = "\(detail ? "詳細模式" : "快速模式")；來源語言：\(originalLanguage)；語氣：\(tone)；長度：\(length)；格式：\(kind)；對象：\(audience)；\(constraints)；保留格式：\(keepFormat)；修正文法：\(correctGrammar)。\(custom)"
        model.run(preferences: preferences)
        model.instruction = custom
    }
}
struct ResultDetails: View {
    let answer: Answer?
    let fields = [("literal","直譯／字面意思"),("context","可能語境"),("native","母語人士說法"),("slang","俚語與縮寫"),("grammar","文法要點"),("tone","語氣與誤會"),("alternatives","其他自然說法")]
    var body: some View {
        ForEach(fields, id: \.0) { key, title in
            if let value = answer?.details[key] { DisclosureGroup(title) { Text(value).textSelection(.enabled) } }
        }
        ForEach(answer?.citations ?? []) { citation in
            if let url = URL(string: citation.url) { Link(citation.title, destination: url) }
        }
    }
}
