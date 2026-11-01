import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {
    private var host: UIHostingController<KeyboardPanel>?
    private let bridge = KeyboardBridge()
    private let globe = UIButton(type: .system)
    private var lastDocument: UUID?
    override func viewDidLoad() {
        super.viewDidLoad()
        bridge.controller = self
        view.backgroundColor = .systemBackground
        let host = UIHostingController(rootView: KeyboardPanel(bridge: bridge))
        self.host = host
        addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        globe.setTitle("🌐 下一個鍵盤", for: .normal)
        globe.accessibilityLabel = "切換下一個鍵盤；長按選擇鍵盤"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        view.addSubview(globe); globe.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), host.view.bottomAnchor.constraint(equalTo: globe.topAnchor),
            globe.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), globe.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), globe.bottomAnchor.constraint(equalTo: view.bottomAnchor), globe.heightAnchor.constraint(equalToConstant: 44)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: 360); height.priority = .defaultHigh; height.isActive = true
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        globe.isHidden = !needsInputModeSwitchKey
        bridge.refresh(); lastDocument = textDocumentProxy.documentIdentifier
    }
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if lastDocument != textDocumentProxy.documentIdentifier { bridge.model?.cancel(); bridge.snapshot = nil }
        lastDocument = textDocumentProxy.documentIdentifier
    }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); bridge.model?.cancel() }
}
struct SelectionSnapshot {
    let document: UUID
    let selection: String
    let before: String?
    let after: String?
}
@MainActor final class KeyboardBridge: ObservableObject {
    weak var controller: KeyboardViewController?
    @Published var preferences = Preferences()
    @Published var status = ""
    @Published var fullAccess = false
    @Published var model: WorkspaceModel?
    var snapshot: SelectionSnapshot?
    func refresh() {
        fullAccess = controller?.hasFullAccess ?? false
        guard fullAccess else { status = "AI 需允許完整取用；本機計算仍可使用。"; return }
        do { preferences = try SharedStore.live().preferences(); status = "只有按下執行才送出文字。" } catch { status = error.localizedDescription }
    }
    func captureSelection() {
        guard let p = controller?.textDocumentProxy, let selected = p.selectedText, !selected.isEmpty else { status = "無法取得選取文字，請先複製再點貼上。"; snapshot = nil; return }
        snapshot = SelectionSnapshot(document: p.documentIdentifier, selection: selected, before: p.documentContextBeforeInput, after: p.documentContextAfterInput)
        model?.task.source = String(selected.prefix(8000)); status = "已讀取選取內容；最多 8,000 字。"
    }
    func paste(_ target: String) {
        guard controller?.hasFullAccess == true else { status = "讀取剪貼簿需要完整取用，亦可使用主 App。"; return }
        // Explicit tap only; never inspect clipboard on appearance.
        guard let text = UIPasteboard.general.string else { status = "剪貼簿沒有文字"; return }
        guard text.count <= 8000 else { status = "超過 8,000 字，請至主 App 分段處理。"; return }
        switch target {
        case "source": model?.task.source = text; snapshot = nil
        case "instruction": model?.instruction = text
        default: model?.saveEdit(text)
        }
    }
    func insert(replace: Bool) {
        guard let p = controller?.textDocumentProxy, let result = model?.result, !result.isEmpty else { return }
        if replace {
            guard let s = snapshot, p.documentIdentifier == s.document, p.selectedText == s.selection, p.documentContextBeforeInput == s.before, p.documentContextAfterInput == s.after else {
                status = "選取或輸入欄位已變更。請取消選取後插入，或複製結果。"; snapshot = nil; return
            }
        } else if let selection = p.selectedText, !selection.isEmpty {
            status = "目前仍有選取文字。請先取消選取，或使用經核對的『取代選取』。"; return
        }
        p.insertText(result); snapshot = nil
        status = "已向目前輸入框提交插入，沒有送出訊息。"
    }
}
struct KeyboardPanel: View {
    @ObservedObject var bridge: KeyboardBridge
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if bridge.model != nil { Button("返回") { bridge.model?.cancel(); bridge.model = nil; bridge.snapshot = nil } }
                Text(bridge.model?.task.tool.name ?? "ChaiTools").font(.headline)
                Spacer()
                Button("更多") { bridge.status = "完整編輯、金鑰與工具管理請開啟主 App。中文可先在其他鍵盤輸入並複製，再切回貼上。" }
            }.padding(.horizontal)
            if let model = bridge.model { KeyboardWorkspace(bridge: bridge, model: model) }
            else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(bridge.preferences.tools.filter(\.enabled).sorted { $0.favorite && !$1.favorite }) { tool in
                            Button { bridge.model = WorkspaceModel(tool: tool) } label: {
                                VStack(spacing: 5) { Image(systemName: tool.icon); Text(tool.name).font(.caption) }.frame(maxWidth: .infinity, minHeight: 52).background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }.padding(8)
                }
            }
            Text(bridge.status).font(.caption2).foregroundStyle(.secondary).lineLimit(3).padding(.horizontal)
        }.tint(.teal)
    }
}
struct KeyboardWorkspace: View {
    @ObservedObject var bridge: KeyboardBridge
    @ObservedObject var model: WorkspaceModel
    @State private var detailed = false
    var body: some View {
        VStack(spacing: 4) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("讀取選取") { bridge.captureSelection() }
                        Button("貼上原文") { bridge.paste("source") }
                        Button("清空") { model.clear(); bridge.snapshot = nil }
                    }
                    Text("原文 \(model.task.source.count) 字：\(String(model.task.source.prefix(600)))").font(.caption)
                    if model.task.tool.id == "calculate" {
                        Text("本機算式鍵位（% 代表 ÷100）").font(.caption)
                        ForEach([Array("789+()"),Array("456-%."),Array("123*/0")], id: \.self) { row in
                            HStack { ForEach(row, id: \.self) { c in Button(String(c)) { model.task.source.append(c) }.frame(maxWidth: .infinity, minHeight: 32) } }
                        }
                        Button("刪除一字") { if !model.task.source.isEmpty { model.task.source.removeLast() } }
                    }
                    if model.task.tool.id == "translate" {
                        Picker("目標", selection: $bridge.preferences.language) { ForEach(["繁體中文（臺灣）","English","日本語","简体中文"], id: \.self) { Text($0) } }
                        Toggle("詳細解析", isOn: $detailed)
                    }
                    Button("貼上追加指令／主題") { bridge.paste("instruction") }
                    Text(model.instruction.isEmpty ? "可貼上中文指令，或使用下方快捷修改。" : String(model.instruction.prefix(500))).font(.caption)
                    if !model.result.isEmpty {
                        Divider()
                        Text(String(model.result.prefix(4000))).font(.body)
                        if model.result.count > 4000 { Text("僅預覽前 4,000 字；複製／插入包含完整結果。長篇請使用主 App。").font(.caption) }
                        ResultDetailsKeyboard(answer: model.task.answer)
                        Button("貼上替換結果並保留版本") { bridge.paste("result") }
                        ScrollView(.horizontal) {
                            HStack { ForEach(["更自然","更精簡","更正式","口語化","補充細節","保留原意"], id: \.self) { chip in
                                Button(chip) { model.instruction = chip; run(revision: true) }.buttonStyle(.bordered)
                            } }
                        }
                        Button("依追加指令修訂") { run(revision: true) }
                        HStack {
                            Button("上一版") { model.select(model.task.selected - 1) }.disabled(model.task.selected <= 0)
                            Text("\(model.task.selected + 1)/\(model.task.revisions.count)")
                            Button("下一版") { model.select(model.task.selected + 1) }.disabled(model.task.selected >= model.task.revisions.count - 1)
                        }
                    }
                    if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).font(.caption) }
                }.padding(.horizontal, 10)
            }
            HStack {
                if model.busy { ProgressView(); Button("取消") { model.cancel() } }
                else { Button("執行") { run(revision: false) } }
                Button("複製") { UIPasteboard.general.string = model.result; bridge.status = "已複製結果" }.disabled(model.result.isEmpty)
                Button("插入") { bridge.insert(replace: false) }.disabled(model.result.isEmpty)
                Button("取代選取") { bridge.insert(replace: true) }.disabled(model.result.isEmpty || bridge.snapshot == nil)
            }.font(.callout).buttonStyle(.bordered).padding(.horizontal, 4)
        }
    }
    private func run(revision: Bool) {
        guard model.task.source.count <= 8000, model.result.count <= 20000 else { model.error = "內容過長，請改用主 App。"; return }
        let custom = model.instruction
        if model.task.tool.id == "translate" { model.instruction = (detailed ? "詳細模式。" : "快速模式。") + custom }
        bridge.fullAccess = bridge.controller?.hasFullAccess ?? false
        model.run(preferences: bridge.preferences, networkAllowed: bridge.fullAccess, revision: revision)
        model.instruction = custom
    }
}
struct ResultDetailsKeyboard: View {
    let answer: Answer?
    var body: some View {
        ForEach((answer?.details ?? [:]).keys.sorted(), id: \.self) { key in
            Text("\(["literal":"直譯","context":"語境","native":"母語說法","slang":"縮寫俚語","grammar":"文法","tone":"語氣","alternatives":"其他說法"][key] ?? key)：\(String((answer?.details[key] ?? "").prefix(800)))").font(.caption)
        }
        ForEach(answer?.citations ?? []) { citation in
            if let url = URL(string: citation.url) { Link(citation.title, destination: url).font(.caption) }
        }
    }
}
