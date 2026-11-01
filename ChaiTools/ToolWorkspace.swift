import SwiftUI
import UIKit

/// A single conversation surface, also used when reopening saved work.
struct ToolWorkspace: View {
    @StateObject private var model: WorkspaceModel
    @State private var preferences = Preferences()
    @State private var options = EditorOptions()
    @State private var composer = ""
    @State private var showOptions = false
    @State private var showTools = false
    @State private var editing = false
    @State private var editedText = ""
    @State private var share: SharedText?
    @State private var pendingTool: Tool?
    @State private var clearConfirmation = false
    @State private var showFeedback = false
    @State private var from = "m"
    @State private var to = "cm"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(tool: Tool = Tool.defaults[2], task: WorkTask? = nil) {
        _model = StateObject(wrappedValue: WorkspaceModel(tool: tool, task: task))
    }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if model.task.source.isEmpty && model.task.revisions.isEmpty { welcome }
                    if !model.task.source.isEmpty { userMessage(model.task.source, label: model.task.tool.id == "generate" ? "你的主題" : "你的原文") }
                    ForEach(Array(model.task.revisions.enumerated()), id: \.element.id) { index, revision in
                        if !revision.instruction.isEmpty { userMessage(revision.instruction, label: "追加要求") }
                        answerMessage(revision, index: index)
                    }
                    if model.busy {
                        HStack(spacing: 12) { ProgressView(); Text("正在\(model.task.tool.actionTitle)…可隨時取消").font(.subheadline).foregroundStyle(InterfaceTheme.secondaryText) }
                    }
                    Color.clear.frame(height: 1).id("conversation-end")
                }.padding(InterfaceTheme.spacing)
            }.scrollDismissesKeyboard(.interactively)
                .onChange(of: model.task.revisions.last?.id) { _, _ in
                    if reduceMotion { reader.scrollTo("conversation-end", anchor: .bottom) }
                    else { withAnimation(.easeOut(duration: 0.18)) { reader.scrollTo("conversation-end", anchor: .bottom) } }
                    if model.error.isEmpty { composer = "" }
                }
        }.appSurface().navigationTitle("ChaiTools").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputDock }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(preferences.tools.filter(\.enabled)) { tool in Button(tool.name, systemImage: tool.icon) { choose(tool) } }
                        Button("所有工具與收藏") { showTools = true }
                    } label: { Label(model.task.tool.name, systemImage: model.task.tool.icon).font(.caption) }.disabled(model.busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text("模型：\(preferences.model)")
                        Button("情境設定", systemImage: "slider.horizontal.3") { showOptions = true }
                        Button("儲存草稿") { if model.task.revisions.isEmpty { _ = model.setSource(composer) }; model.persist(manual: true) }
                        Button("開新對話", systemImage: "plus.bubble") { clearConfirmation = true }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("模型與對話選項")
                }
            }
            .sheet(isPresented: $showOptions) {
                EditorOptionsView(tool: model.task.tool, preferences: $preferences, options: $options)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showTools) { ToolListView() }
            .sheet(isPresented: $editing) { editSheet }
            .sheet(item: $share) { ShareSheet(text: $0.text) }
            .confirmationDialog("開新對話？目前內容可先儲存至工作紀錄。", isPresented: $clearConfirmation, titleVisibility: .visible) {
                Button("開新對話", role: .destructive) { reset(tool: model.task.tool) }
            }
            .confirmationDialog("切換工具會開啟新對話，避免混用上一個結果。", isPresented: Binding(get: { pendingTool != nil }, set: { if !$0 { pendingTool = nil } }), titleVisibility: .visible) {
                Button("切換並開新對話") { if let tool = pendingTool { reset(tool: tool) }; pendingTool = nil }
            }
            .task {
                do { preferences = try await Task.detached(priority: .utility) { try SharedStore.live().preferences() }.value }
                catch { model.error = SensitiveContentGuard.userMessage(error) }
                if model.task.revisions.isEmpty { composer = model.task.source }
            }
            .task(id: model.status) {
                showFeedback = !model.status.isEmpty
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { showFeedback = false }
            }
            .onDisappear { model.cancel() }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: model.task.tool.icon).font(.system(size: 28, weight: .medium)).foregroundStyle(InterfaceTheme.accent)
            Text("今天想完成什麼？").font(.title2.weight(.semibold))
            Text(model.task.tool.id == "generate" ? "寫下想法，我們一起把它寫好。" : model.task.tool.subtitle).foregroundStyle(InterfaceTheme.secondaryText)
            Text("在下方輸入或貼上，結果會留在這段對話中。").font(.subheadline).foregroundStyle(InterfaceTheme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(preferences.tools.filter { ["generate", "translate", "rewrite", "search", "calculate"].contains($0.id) && $0.enabled }) { tool in
                        Button(tool.name) { choose(tool) }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
            Text("\(preferences.model) · 金鑰與連線狀態請見設定").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            if model.task.tool.id == "calculate" { calculationTools }
        }.padding(.vertical, 24)
    }
    private func userMessage(_ text: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            Text(text).textSelection(.enabled).padding(16)
                .background(InterfaceTheme.secondarySurface, in: RoundedRectangle(cornerRadius: InterfaceTheme.radius))
        }.frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, 24)
    }
    private func answerMessage(_ revision: Revision, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.task.tool.id == "translate" ? "自然譯文" : "ChaiTools", systemImage: "sparkle").font(.caption.weight(.semibold)).foregroundStyle(InterfaceTheme.accent)
                Spacer()
                Button("第 \(index + 1) 版\(model.task.selected == index ? " · 目前" : "")") { model.select(index) }.font(.caption).frame(minHeight: 44).disabled(model.busy)
            }
            Text(revision.answer.text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if !revision.answer.details.isEmpty || !revision.answer.citations.isEmpty {
                DisclosureGroup(revision.answer.searched ? "網路來源（\(revision.answer.citations.count)）" : "翻譯與語境解析") { ResultDetails(answer: revision.answer) }
            }
            if model.task.selected == index {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("複製", systemImage: "doc.on.doc") { export(shareSheet: false) }.buttonStyle(QuietButtonStyle())
                        Button("分享", systemImage: "square.and.arrow.up") { export(shareSheet: true) }.buttonStyle(QuietButtonStyle())
                        Button("編輯") { do { editedText = try model.output(); editing = true } catch { model.error = SensitiveContentGuard.userMessage(error) } }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                        Button("重新生成") { _ = model.setInstruction(""); model.run(preferences: preferences, configuration: options.prompt) }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["更自然", "再短一些", "更正式"], id: \.self) { chip in
                            Button(chip) { composer = chip; submit() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }.disabled(model.busy)
            }
        }.padding(.vertical, 4)
    }
    private var inputDock: some View {
        VStack(spacing: 8) {
            if !model.error.isEmpty {
                HStack(alignment: .top) {
                    Text(model.error).font(.caption).foregroundStyle(.red)
                    Spacer(); Button("收起") { model.error = "" }.frame(minHeight: 44)
                }
            } else if showFeedback { Text(model.status).font(.caption).foregroundStyle(InterfaceTheme.secondaryText) }
            HStack {
                Text(model.task.revisions.isEmpty ? (model.task.tool.id == "generate" ? "描述你想寫的內容" : "輸入原文或問題") : "繼續修改第 \(model.task.selected + 1) 版…").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
                Spacer()
                if model.task.tool.id == "calculate" { Text("算式離線 · 文字題用 AI").font(.caption2).foregroundStyle(InterfaceTheme.secondaryText) }
            }
            SafeTextInput(text: $composer, label: "對話輸入", onBlocked: blocked).frame(height: 76).disabled(model.busy)
            HStack(spacing: 8) {
                PasteButton(payloadType: String.self) { values in
                    do { composer = try SensitiveContentGuard.checked(values.joined(separator: "\n")) }
                    catch { blocked() }
                }.disabled(model.busy)
                Button { showOptions = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("情境設定").disabled(model.busy)
                Spacer()
                Button { if model.busy { model.cancel() } else { submit() } } label: {
                    Label(model.busy ? "取消" : "送出", systemImage: model.busy ? "stop.fill" : "arrow.up")
                }.buttonStyle(QuietButtonStyle(prominent: true)).disabled(!model.busy && composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(12).background(CTBarSurface())
    }
    private var editSheet: some View {
        NavigationStack {
            SafeTextInput(text: $editedText, label: "編輯結果", onBlocked: blocked).padding().appSurface().navigationTitle("編輯結果")
                .safeAreaInset(edge: .bottom) { if !model.error.isEmpty { Text(model.error).font(.caption).padding() } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("儲存新版本") { model.saveEdit(editedText); if model.error.isEmpty { editing = false } } }
                }
        }
    }
    private var calculationTools: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("從", selection: $from) { ForEach(["m", "cm", "km", "in", "ft", "kg", "g", "lb", "°C", "°F"], id: \.self) { Text($0) } }
                Picker("至", selection: $to) { ForEach(["m", "cm", "km", "in", "ft", "kg", "g", "lb", "°C", "°F"], id: \.self) { Text($0) } }
                Button("換算") {
                    do {
                        let input = try SensitiveContentGuard.checked(composer)
                        let value = try Calculator.evaluate(input)
                        let converted = try Calculator.convert(value, from: from, to: to)
                        _ = model.setSource(input); model.accept(Answer(text: "\(value) \(from) = \(converted) \(to)（本機換算）"))
                    } catch { model.error = SensitiveContentGuard.userMessage(error) }
                }.buttonStyle(QuietButtonStyle())
            }
            Button("帶入圓面積算式") { composer = "3.141592653589793*(1*1)" }.buttonStyle(QuietButtonStyle())
        }
    }
    private func blocked() { model.error = SensitiveContentGuard.message }
    private func choose(_ tool: Tool) {
        guard tool.id != model.task.tool.id else { return }
        if !model.task.source.isEmpty || !model.task.revisions.isEmpty { pendingTool = tool }
        else { model.updateTool(tool); options = EditorOptions() }
    }
    private func reset(tool: Tool) { model.clear(); model.updateTool(tool); composer = ""; options = EditorOptions() }
    private func submit() {
        guard (try? SensitiveContentGuard.validate(composer)) != nil else { blocked(); return }
        if model.task.revisions.isEmpty { guard model.setSource(composer), model.setInstruction("") else { return } }
        else { guard model.setInstruction(composer) else { return } }
        model.run(preferences: preferences, revision: !model.task.revisions.isEmpty, configuration: options.prompt)
        AppHaptics.tap()
    }
    private func export(shareSheet: Bool) {
        do {
            let text = try model.output()
            if shareSheet { share = SharedText(text: text) }
            else { UIPasteboard.general.string = text; model.status = "已複製生成內容" }
        } catch { model.error = SensitiveContentGuard.userMessage(error) }
    }
}
private struct SharedText: Identifiable { let id = UUID(); let text: String }
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [(try? SensitiveContentGuard.checked(text)) ?? SensitiveContentGuard.message], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
