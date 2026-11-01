import SwiftUI

struct KeyboardPanel: View {
    @ObservedObject var bridge: KeyboardBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.25)
            Group {
                if bridge.showingInformation { information }
                else if let model = bridge.model { KeyboardWorkspace(bridge: bridge, model: model) }
                else { home }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }.background(InterfaceTheme.background).foregroundStyle(InterfaceTheme.text).tint(InterfaceTheme.accent)

    }
    private var toolbar: some View {
        HStack(spacing: 4) {
            if bridge.needsGlobe { KeyboardGlobe(bridge: bridge).frame(width: 44, height: 44) }
            if bridge.model != nil || bridge.showingAllTools {
                Button { bridge.home() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("返回工具首頁")
            }
            Text(bridge.model?.task.tool.name ?? (bridge.showingAllTools ? "全部工具" : "ChaiTools")).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 2)
            Button { bridge.showingInformation.toggle() } label: {
                CTStatusPill(text: bridge.statusLabel).frame(minHeight: 44)
            }.accessibilityLabel("功能狀態：\(bridge.statusLabel)")
            Menu {
                ForEach(bridge.availableTools) { tool in Button(tool.name, systemImage: tool.icon) { bridge.select(tool) } }
                Divider()
                Toggle("觸覺回饋", isOn: $bridge.haptics)
                Button("中文輸入與長文編輯") { bridge.notify("中文請先用原生鍵盤輸入並複製，再切回貼上。完整長文編輯請使用主 App。", error: true) }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("切換工具與更多操作")
        }.padding(.horizontal, 6).frame(height: 44)
    }
    private var information: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let notice = bridge.notice { Text(notice.text).font(.callout) }
                    LabeledContent("完整取用", value: bridge.fullAccess ? "已允許" : "未允許")
                    LabeledContent("主 App 群組", value: "請在主 App 設定確認")
                    LabeledContent("鍵盤群組", value: bridge.sharing ? "可取得" : "缺少共享授權")
                    LabeledContent("金鑰檔案", value: bridge.sharing ? (bridge.hasKey ? "存在" : "未取得") : "無法查詢")
                    LabeledContent("模型連線", value: bridge.connectionStatus)
                    Text("完整取用與 App Group 是不同條件。缺少共享授權時，請用主 App 生成再複製；本機計算仍可用。").foregroundStyle(InterfaceTheme.secondaryText)
                    Text("中文請先用原生鍵盤輸入，再選取或複製、切回 ChaiTools。系統不會在此面板內再開啟注音鍵盤。").foregroundStyle(InterfaceTheme.secondaryText)
                }.font(.caption).padding(12)
            }
            Button("返回工作") { bridge.showingInformation = false; bridge.notice = nil }.frame(maxWidth: .infinity).buttonStyle(QuietButtonStyle()).padding(6)
        }
    }
    private var home: some View {
        VStack(spacing: 6) {
            if !bridge.canUseAI {
                Button { bridge.showingInformation = true } label: {
                    Text("鍵盤 AI 暫不可用 · 點此查看狀態").font(.caption).frame(minHeight: 44)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 6) {
                    ForEach(bridge.showingAllTools ? bridge.availableTools : Array(bridge.availableTools.prefix(6))) { tool in
                        Button { bridge.select(tool) } label: {
                            CTToolTile(tool: tool, compact: true)
                        }.buttonStyle(CTPressStyle()).accessibilityLabel(tool.name)
                    }
                }.padding(8)
            }
            HStack(spacing: 6) {
                Button { bridge.paste("home") } label: {
                    Label(bridge.homeSource.isEmpty ? "貼上文字" : "已備妥 \(bridge.homeSource.count) 字", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }.buttonStyle(QuietButtonStyle())
                if bridge.availableTools.count > 6 && !bridge.showingAllTools {
                    Button("全部工具") { bridge.showingAllTools = true }.buttonStyle(QuietButtonStyle())
                }
            }.padding(.horizontal, 8).padding(.bottom, 6)
        }
    }
}

struct KeyboardWorkspace: View {
    @ObservedObject var bridge: KeyboardBridge
    @ObservedObject var model: WorkspaceModel
    @State private var details = false
    var body: some View {
        VStack(spacing: 0) {
            controls
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.busy { HStack { ProgressView(); Text("正在\(model.task.tool.actionTitle)⋯").font(.caption).foregroundStyle(InterfaceTheme.secondaryText) } }
                    if bridge.showResult && !model.result.isEmpty { result }
                    else { source }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            Divider().opacity(0.25)
            actions
        }
        .onChange(of: model.task.revisions.last?.id) { _, _ in bridge.showResult = true; if model.task.tool.id != "calculate" { bridge.connectionStatus = "最近請求成功" } }
        .onChange(of: model.error) { _, text in if !text.isEmpty { bridge.notify(text, error: true) } }
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { bridge.showResult = false } label: { Text(model.task.tool.id == "generate" ? "主題" : "原文").font(.caption.weight(bridge.showResult ? .regular : .bold)).frame(minWidth: 44, minHeight: 44) }
            Button { bridge.showResult = true } label: { Text("結果").font(.caption.weight(bridge.showResult ? .bold : .regular)).frame(minWidth: 44, minHeight: 44) }.disabled(model.result.isEmpty)
            Spacer(minLength: 0)
            if model.task.tool.id == "translate" {
                Menu {
                    Picker("目標語言", selection: $bridge.preferences.language) { ForEach(["繁體中文（臺灣）", "English", "日本語", "简体中文"], id: \.self) { Text($0) } }
                    Toggle("詳細解析", isOn: $bridge.detailed)
                } label: { Label("語言／解析", systemImage: "slider.horizontal.3").font(.caption).frame(minHeight: 44) }
            } else {
                Menu {
                    Button("貼上追加指令") { bridge.paste("instruction") }
                    Button("自然語氣") { _ = model.setInstruction("自然語氣，保留原意") }
                    Button("正式語氣") { _ = model.setInstruction("正式語氣，保留原意") }
                    Button("精簡輸出") { _ = model.setInstruction("精簡輸出，保留重點") }
                } label: { Label("要求", systemImage: "slider.horizontal.3").font(.caption).frame(minHeight: 44) }
            }
        }.padding(.horizontal, 10).disabled(model.busy)
    }
    private var source: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.task.source.isEmpty {
                Text(model.task.tool.id == "generate" ? "從一個主題開始" : "選取或貼上想處理的文字").font(.subheadline.weight(.medium))
            } else {
                Text(String(model.task.source.prefix(1200))).font(.callout).textSelection(.enabled)
                Text("\(model.task.source.count) 字\(model.task.source.count > 1200 ? " · 預覽已截短" : "")").font(.caption2).foregroundStyle(InterfaceTheme.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack { inputButtons }
                VStack(alignment: .leading) { inputButtons }
            }
            if !model.instruction.isEmpty {
                Text("要求：\(String(model.instruction.prefix(500)))").font(.caption).foregroundStyle(InterfaceTheme.secondaryText)
            }
            if model.task.tool.id == "calculate" { calculator }
            Menu("編輯與清空") {
                Button("貼上原文／主題") { bridge.paste("source") }
                Button("貼上追加指令") { bridge.paste("instruction") }
                Button("清空目前工作", role: .destructive) { model.clear(); bridge.snapshot = nil }
            }.font(.caption).frame(minHeight: 44)
        }.disabled(model.busy)
    }
    @ViewBuilder private var inputButtons: some View {
        Button("讀取選取") { bridge.captureSelection() }.buttonStyle(QuietButtonStyle())
        Button("貼上文字") { bridge.paste("source") }.buttonStyle(QuietButtonStyle())
        Button(model.task.tool.id == "generate" ? "貼上主題" : "寫新內容") {
            if model.task.tool.id == "generate" { bridge.paste("instruction") }
            else if let tool = bridge.tools.first(where: { $0.id == "generate" }) { bridge.select(tool) }
            else { bridge.notify("請在主 App 啟用文章生成工具，或貼上自訂指令。", error: true) }
        }.buttonStyle(QuietButtonStyle())
    }
    private var calculator: some View {
        VStack(spacing: 4) {
            Text("本機算式鍵位 · % 表示 ÷100").font(.caption2)
            ForEach([Array("789+()"), Array("456-%."), Array("123*/0")], id: \.self) { row in
                HStack(spacing: 4) { ForEach(row, id: \.self) { c in
                    Button(String(c)) { _ = model.setSource(model.task.source + String(c)); bridge.snapshot = nil }.frame(maxWidth: .infinity).buttonStyle(QuietButtonStyle())
                } }
            }
            Button("刪除一字") { if !model.task.source.isEmpty { _ = model.setSource(String(model.task.source.dropLast())); bridge.snapshot = nil } }.buttonStyle(QuietButtonStyle())
        }
    }
    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.task.tool.id == "translate" { Text("自然譯文").font(.caption.weight(.semibold)).foregroundStyle(InterfaceTheme.accent) }
            Text(String(model.result.prefix(4000))).font(.callout).textSelection(.enabled)
            if model.result.count > 4000 { Text("預覽前 4,000 字；複製與插入仍使用完整結果。").font(.caption2) }
            if let answer = model.task.answer, !answer.details.isEmpty || !answer.citations.isEmpty {
                DisclosureGroup(answer.searched ? "查看 \(answer.citations.count) 個來源" : "展開詳細解析", isExpanded: $details) { ResultDetailsKeyboard(answer: answer) }
                    .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(["更自然", "更精簡", "更正式", "口語化", "保留原意"], id: \.self) { chip in
                    Button(chip) { _ = model.setInstruction(chip); bridge.run(revision: true) }.buttonStyle(QuietButtonStyle())
                } }
            }.disabled(model.busy)
            HStack {
                Button { model.select(model.task.selected - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.disabled(model.task.selected <= 0).accessibilityLabel("上一版")
                Text("第 \(model.task.selected + 1)／\(model.task.revisions.count) 版").font(.caption)
                Button { model.select(model.task.selected + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(model.task.selected >= model.task.revisions.count - 1).accessibilityLabel("下一版")
                Spacer()
                Menu("修訂") {
                    Button("貼上替換結果並保留版本") { bridge.paste("result") }
                    Button("貼上追加指令") { bridge.paste("instruction") }
                    Button("依追加指令修改") { bridge.run(revision: true) }
                }.frame(minHeight: 44)
            }.disabled(model.busy)
            if !model.instruction.isEmpty { Text("追加指令：\(String(model.instruction.prefix(300)))").font(.caption2) }
        }
    }
    private var actions: some View {
        HStack(spacing: 4) {
            if model.busy || !bridge.showResult || model.result.isEmpty {
                Button { if model.busy { model.cancel() } else { bridge.run() } } label: {
                    HStack(spacing: 4) { if model.busy { ProgressView().tint(.white) }; Text(model.busy ? "取消" : model.task.tool.actionTitle) }.frame(maxWidth: .infinity)
                }.buttonStyle(QuietButtonStyle(prominent: true))
                Button("貼上") { bridge.paste("source") }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
            } else {
                Button("複製") { bridge.copy() }.frame(maxWidth: .infinity).buttonStyle(QuietButtonStyle())
                Button("插入游標") { bridge.insert(replace: false) }.frame(maxWidth: .infinity).buttonStyle(QuietButtonStyle(prominent: true))
            }
            Menu {
                Button("取代選取內容") { bridge.insert(replace: true) }.disabled(bridge.snapshot == nil || model.result.isEmpty)
                Button("貼上追加指令") { bridge.paste("instruction") }
                Button("回到工具首頁") { bridge.home() }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("取代選取與更多操作")
        }.padding(.horizontal, 8).padding(.vertical, 5)
    }
}
struct ResultDetailsKeyboard: View {
    let answer: Answer
    var body: some View {
        ForEach(answer.details.keys.sorted(), id: \.self) { key in
            Text("\(["literal":"直譯", "context":"語境", "native":"母語說法", "slang":"縮寫俚語", "grammar":"文法", "tone":"語氣", "alternatives":"其他說法"][key] ?? key)：\(String((answer.details[key] ?? "").prefix(800)))").font(.caption)
        }
        ForEach(answer.citations) { citation in
            if let url = URL(string: citation.url) { Link(citation.title, destination: url).font(.caption).frame(minHeight: 44) }
        }
    }
}
