import SwiftUI
import UIKit

struct ToolWorkspace: View {
    @StateObject private var model: WorkspaceModel
    @State private var preferences = Preferences()
    @State private var options = EditorOptions()
    @State private var showOptions = false
    @State private var clearConfirmation = false
    @State private var from = "m"
    @State private var to = "cm"
    @State private var showFeedback = false
    init(tool: Tool, task: WorkTask? = nil) {
        _model = StateObject(wrappedValue: WorkspaceModel(tool: tool, task: task))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(model.task.tool.subtitle, systemImage: model.task.tool.icon).font(.subheadline).foregroundStyle(InterfaceTheme.secondaryText)
                    Spacer()
                }
                if !model.error.isEmpty {
                    SurfaceCard {
                        NoticeCard(notice: OperationNotice(title: "未能完成操作", message: model.error, kind: .failure))
                        Button("收起提示") { model.error = "" }.buttonStyle(QuietButtonStyle())
                    }
                } else if showFeedback && !model.status.isEmpty {
                    NoticeCard(notice: OperationNotice(title: "操作完成", message: model.status, kind: .success))
                }
                sourceCard
                contextCard
                if model.task.tool.id == "calculate" { calculationCard }
                if model.task.tool.id == "search" { Text("使用即時搜尋可能產生額外工具費用。來源只取自 API，查詢失敗不會用舊知識冒充結果。").font(.caption).foregroundStyle(InterfaceTheme.secondaryText) }
                if !model.task.revisions.isEmpty { resultCard; revisionCard }
                HStack {
                    Button("儲存草稿") { model.persist(manual: true) }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button("清空工作", role: .destructive) { clearConfirmation = true }.frame(minHeight: 44)
                }.disabled(model.busy)
            }.padding(16)
        }.appSurface().navigationTitle(model.task.tool.name).navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { executionBar }
            .sheet(isPresented: $showOptions) { EditorOptionsView(tool: model.task.tool, preferences: $preferences, options: $options) }
            .confirmationDialog("清空目前原文與未儲存版本？", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("清空工作區", role: .destructive) { model.clear() }
            }
            .task {
                let result = await Task.detached(priority: .utility) { () -> Result<Preferences, Error> in Result { try SharedStore.live().preferences() } }.value
                guard !Task.isCancelled else { return }
                switch result { case .success(let p): preferences = p; case .failure(let e): model.error = e.localizedDescription }
            }
            .task(id: model.status) {
                guard !model.status.isEmpty else { return }
                showFeedback = true
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { showFeedback = false }
            }
            .onDisappear { model.cancel() }
    }
    private var sourceCard: some View {
        SurfaceCard {
            HStack {
                Text(model.task.tool.id == "generate" ? "01 · 主題與素材" : "01 · 原文").font(.headline)
                Spacer(); Button("清空") { model.task.source = "" }.font(.caption).frame(minHeight: 44); Text("\(model.task.source.count) 字").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            }
            ZStack(alignment: .topLeading) {
                if model.task.source.isEmpty { Text(model.task.tool.id == "generate" ? "寫下主題，或在下方描述你想產生的內容。" : "輸入或貼上要處理的文字。局部改寫可只放入選定段落。").font(.body).foregroundStyle(InterfaceTheme.secondaryText).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false) }
                TextEditor(text: $model.task.source).frame(minHeight: 140).scrollContentBackground(.hidden).accessibilityLabel("原文或主題")
            }
            HStack {
                PasteButton(payloadType: String.self) { model.task.source = $0.joined(separator: "\n"); AppHaptics.tap() }
                Spacer()
                Text("只在執行時傳送").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            }
        }.disabled(model.busy)
    }
    private var contextCard: some View {
        SurfaceCard {
            Button { showOptions = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("02 · 情境設定").font(.headline).foregroundStyle(InterfaceTheme.text)
                        Text("\(preferences.language) · \(options.tone) · \(options.detailed ? "詳細" : "精簡")").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                    }
                    Spacer(); Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }
            }.buttonStyle(.plain)
            Divider().opacity(0.3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu(preferences.language) {
                        ForEach(["繁體中文（臺灣）", "English", "日本語"], id: \.self) { language in Button(language) { preferences.language = language } }
                    }.buttonStyle(QuietButtonStyle())
                    if ["translate", "language"].contains(model.task.tool.id) {
                        Button(options.detailed ? "詳細解析" : "快速模式") { options.detailed.toggle() }.buttonStyle(QuietButtonStyle())
                    }
                    if ["rewrite", "generate", "custom"].contains(model.task.tool.id) {
                        Menu(options.tone) { ForEach(["自然", "正式", "禮貌", "社群風格"], id: \.self) { tone in Button(tone) { options.tone = tone } } }.buttonStyle(QuietButtonStyle())
                        Menu(options.length) { ForEach(["精簡", "適中", "詳細"], id: \.self) { length in Button(length) { options.length = length } } }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
            if model.task.revisions.isEmpty {
                TextField("額外要求", text: $model.instruction, axis: .vertical).lineLimit(2...5).frame(minHeight: 44)
            }
        }.disabled(model.busy)
    }
    private var calculationCard: some View {
        SurfaceCard {
            Text("本機計算").font(.headline)
            Text("四則運算、括號、百分比（÷100）。例如 200*(1+10%)。自然語言題才會使用 AI；不提供即時匯率。").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            HStack {
                Picker("從", selection: $from) { ForEach(["m", "cm", "km", "in", "ft", "kg", "g", "lb", "°C", "°F"], id: \.self) { Text($0) } }
                Image(systemName: "arrow.right")
                Picker("至", selection: $to) { ForEach(["m", "cm", "km", "in", "ft", "kg", "g", "lb", "°C", "°F"], id: \.self) { Text($0) } }
                Spacer()
            }.pickerStyle(.menu)
            ViewThatFits(in: .horizontal) {
                HStack { calculationButtons }
                VStack(alignment: .leading) { calculationButtons }
            }
        }.disabled(model.busy)
    }
    @ViewBuilder private var calculationButtons: some View {
        Button("單位換算") {
            do {
                let v = try Calculator.evaluate(model.task.source)
                let value = try Calculator.convert(v, from: from, to: to)
                model.accept(Answer(text: "\(v) \(from) = \(value) \(to)"))
            } catch { model.error = error.localizedDescription }
        }.buttonStyle(QuietButtonStyle())
        Button("帶入圓面積公式") { model.task.source = "3.141592653589793 * (1 * 1)" }.buttonStyle(QuietButtonStyle())
    }
    private var resultCard: some View {
        SurfaceCard {
            HStack {
                Text(model.task.tool.id == "translate" ? "03 · 自然譯文" : "03 · 結果").font(.headline)
                Spacer(); Text("可直接編輯").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            }
            TextEditor(text: $model.result).frame(minHeight: 180).scrollContentBackground(.hidden)
                .font(model.task.tool.id == "calculate" ? .system(.body, design: .monospaced) : .body)
                .accessibilityLabel("結果，可編輯").disabled(model.busy)
            ViewThatFits(in: .horizontal) {
                HStack { resultButtons }
                VStack(alignment: .leading) { resultButtons }
            }
            ResultDetails(answer: model.task.answer)
            Text("本次使用量：輸入 \(model.task.answer?.inputTokens ?? 0)／輸出 \(model.task.answer?.outputTokens ?? 0) tokens；非帳務餘額。").font(.caption2).foregroundStyle(InterfaceTheme.secondaryText)
        }
    }
    @ViewBuilder private var resultButtons: some View {
        Button { UIPasteboard.general.string = model.result; model.status = "已複製結果"; AppHaptics.result(success: true) } label: { Label("複製", systemImage: "doc.on.doc") }.buttonStyle(QuietButtonStyle(prominent: true))
        ShareLink(item: model.result) { Label("分享", systemImage: "square.and.arrow.up") }.buttonStyle(QuietButtonStyle())
        Button("儲存編輯版本") { model.saveEdit(model.result) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
    }
    private var revisionCard: some View {
        SurfaceCard {
            Text("繼續修訂").font(.headline)
            TextField("輸入追加指令", text: $model.instruction, axis: .vertical).lineLimit(2...5).frame(minHeight: 44)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(["更自然", "更精簡", "更正式", "口語化", "補充細節", "保留原意"], id: \.self) { chip in
                    Button(chip) { model.instruction = chip; model.run(preferences: preferences, revision: true, configuration: options.prompt); AppHaptics.tap() }.buttonStyle(QuietButtonStyle())
                } }
            }
            Button("依上方追加指令修訂") { model.run(preferences: preferences, revision: true, configuration: options.prompt) }.buttonStyle(QuietButtonStyle())
            Picker("版本", selection: Binding(get: { model.task.selected }, set: { model.select($0); AppHaptics.tap() })) {
                ForEach(Array(model.task.revisions.enumerated()), id: \.element.id) { i, revision in Text("第 \(i + 1) 版 · \(revision.date.formatted(date: .omitted, time: .shortened))").tag(i) }
            }.pickerStyle(.menu)
            if model.task.selected > 0 { DisclosureGroup("與上一版對照") { Text(model.task.revisions[model.task.selected - 1].answer.text).textSelection(.enabled) } }
        }.disabled(model.busy)
    }
    private var executionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.busy ? "正在處理⋯" : "\(model.task.source.count + model.instruction.count) 字待處理").font(.subheadline.weight(.medium))
                Text(model.busy ? "取消會保留上一版" : model.task.tool.id == "search" ? "網路搜尋含工具費用" : "先預覽，再複製使用").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            }
            Spacer(minLength: 0)
            Button {
                if model.busy { model.cancel() }
                else {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    model.run(preferences: preferences, configuration: options.prompt); AppHaptics.tap()
                }
            } label: {
                HStack { if model.busy { ProgressView().tint(.white) }; Text(model.busy ? "取消" : !model.error.isEmpty ? "重試" : model.task.tool.actionTitle) }
            }.buttonStyle(QuietButtonStyle(prominent: true))
        }.padding(.horizontal, 16).padding(.vertical, 10).background(CTBarSurface())
    }
}
struct ResultDetails: View {
    let answer: Answer?
    let fields = [("literal", "直譯／字面意思"), ("context", "可能語境"), ("native", "母語人士說法"), ("slang", "俚語與縮寫"), ("grammar", "文法要點"), ("tone", "語氣與誤會"), ("alternatives", "其他自然說法")]
    var body: some View {
        ForEach(fields, id: \.0) { key, title in
            if let value = answer?.details[key] {
                DisclosureGroup(title) { Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
                    .padding(12).background(InterfaceTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        ForEach(answer?.citations ?? []) { citation in
            if let url = URL(string: citation.url) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "link")
                        VStack(alignment: .leading, spacing: 4) { Text(citation.title).font(.subheadline); Text(url.host ?? citation.url).font(.caption).foregroundStyle(InterfaceTheme.secondaryText) }
                        Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.caption)
                    }.padding(12).frame(minHeight: 44).background(InterfaceTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
