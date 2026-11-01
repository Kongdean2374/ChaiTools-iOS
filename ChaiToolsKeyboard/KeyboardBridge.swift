import SwiftUI
import UIKit

struct SelectionSnapshot {
    let document: UUID
    let selection: String
    let before: String?
    let after: String?
}
struct KeyboardNotice: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}
@MainActor final class KeyboardBridge: ObservableObject {
    weak var controller: KeyboardViewController?
    @Published var preferences = Preferences()
    @Published var fullAccess = false
    @Published var sharing = false
    @Published var loadingPreferences = false
    @Published var needsGlobe = false
    @Published var model: WorkspaceModel?
    @Published var notice: KeyboardNotice?
    @Published var homeSource = ""
    @Published var detailed = false
    @Published var showingAllTools = false
    @Published var showResult = false
    @Published var haptics = true
    var snapshot: SelectionSnapshot?
    private var homePastePending = false
    private var cachedModels: [String: WorkspaceModel] = [:]
    private var refreshTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var refreshID = UUID()
    var statusLabel: String { loadingPreferences ? "讀取設定" : !fullAccess ? "本機模式" : !sharing ? "僅主 App AI" : "AI 工具" }
    var tools: [Tool] { preferences.tools.filter(\.enabled).sorted { $0.favorite && !$1.favorite } }

    func refresh() {
        fullAccess = controller?.hasFullAccess ?? false
        let id = UUID(); refreshID = id
        refreshTask?.cancel()
        guard fullAccess else { sharing = false; loadingPreferences = false; return }
        loadingPreferences = true
        refreshTask = Task {
            let loaded = await Task.detached(priority: .utility) { () -> (Preferences?, Bool) in
                guard StorageLocation.sharedContainer != nil else { return (nil, false) }
                return (try? SharedStore.live().preferences(), true)
            }.value
            guard !Task.isCancelled, refreshID == id else { return }
            loadingPreferences = false
            sharing = loaded.1
            if let p = loaded.0 { preferences = p }
        }
    }
    func select(_ tool: Tool) {
        model?.cancel(); snapshot = nil; notice = nil; showingAllTools = false
        if !homePastePending, let cached = cachedModels[tool.id] { model = cached; cached.task.tool = tool }
        else {
            let next = WorkspaceModel(tool: tool)
            next.task.source = homeSource
            // Bound retained drafts/results; all tools remain selectable.
            if cachedModels.count >= 4 { cachedModels.removeAll() }
            cachedModels[tool.id] = next; model = next
        }
        homePastePending = false
        showResult = !(model?.result.isEmpty ?? true)
        AppHaptics.tap(enabled: haptics)
    }
    func home() { model?.cancel(); model = nil; snapshot = nil; showingAllTools = false; AppHaptics.tap(enabled: haptics) }
    func suspend() { model?.cancel(); refreshTask?.cancel(); refreshID = UUID(); noticeTask?.cancel() }
    func notify(_ text: String, error: Bool = false) {
        noticeTask?.cancel()
        let item = KeyboardNotice(text: text, isError: error); notice = item
        if !error {
            noticeTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, notice?.id == item.id else { return }; notice = nil
            }
        }
    }
    func explainAvailability() {
        if loadingPreferences { notify("正在讀取設定，請稍候再試。"); return }
        if !fullAccess { notify("AI 需在 iOS 設定 → 一般 → 鍵盤 → ChaiTools 允許完整取用。本機計算仍可用。", error: true) }
        else if !sharing { notify("此安裝版本無法與主 App 共用金鑰。請在主 App 處理後複製使用；完整取用無法補上共享權限。", error: true) }
        else { notify("只在你點執行時送出文字。金鑰與模型在主 App 設定。") }
    }
    func captureSelection() {
        guard model?.busy != true else { return }
        guard let p = controller?.textDocumentProxy, let selected = p.selectedText, !selected.isEmpty else { snapshot = nil; notify("取不到選取文字，請先複製，再點貼上。", error: true); return }
        guard selected.count <= 8000 else { notify("超過 8,000 字，請使用主 App。", error: true); return }
        snapshot = SelectionSnapshot(document: p.documentIdentifier, selection: selected, before: p.documentContextBeforeInput, after: p.documentContextAfterInput)
        model?.task.source = selected; showResult = false
        notify("已讀取選取文字")
    }
    func paste(_ target: String) {
        guard model?.busy != true else { return }
        guard controller?.hasFullAccess == true else { notify("貼上需要完整取用；也可在主 App 處理。", error: true); return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else { notify("剪貼簿沒有文字，請先複製。", error: true); return }
        guard text.count <= 8000 else { notify("超過 8,000 字，請使用主 App。", error: true); return }
        switch target {
        case "home": homeSource = text; homePastePending = true; notify("已貼上，請選擇工具")
        case "source": model?.task.source = text; snapshot = nil; showResult = false; notify("已貼上原文")
        case "instruction": model?.instruction = text; notify("已貼上追加指令／主題")
        default: model?.saveEdit(text); showResult = true; notify("已儲存貼上的新版本")
        }
    }
    func run(revision: Bool = false) {
        guard let model, !model.busy else { return }
        let input = revision ? model.result : model.task.source
        guard input.count <= 20000, model.task.source.count <= 8000 else { notify("內容過長，請使用主 App。", error: true); return }
        fullAccess = controller?.hasFullAccess ?? false
        if model.task.tool.id != "calculate" || (try? Calculator.evaluate(input)) == nil {
            guard !loadingPreferences && fullAccess && sharing else { explainAvailability(); return }
        }
        let configuration = model.task.tool.id == "translate" ? (detailed ? "詳細模式。" : "快速模式。") : ""
        model.run(preferences: preferences, networkAllowed: fullAccess, revision: revision, configuration: configuration)
        if !model.error.isEmpty { notify(model.error, error: true) }
        AppHaptics.tap(enabled: haptics)
    }
    func copy() {
        guard let result = model?.result, !result.isEmpty else { return }
        UIPasteboard.general.string = result; notify("已複製結果"); AppHaptics.tap(enabled: haptics)
    }
    func insert(replace: Bool) {
        guard let p = controller?.textDocumentProxy, let result = model?.result, !result.isEmpty else { return }
        if replace {
            guard let s = snapshot, p.documentIdentifier == s.document, p.selectedText == s.selection,
                p.documentContextBeforeInput == s.before, p.documentContextAfterInput == s.after else {
                snapshot = nil; notify("選取或欄位已改變。請取消選取後插入，或複製結果。", error: true); return
            }
        } else if let selected = p.selectedText, !selected.isEmpty {
            notify("目前仍有選取文字，請取消選取或點『取代選取』。", error: true); return
        }
        p.insertText(result); snapshot = nil
        notify("已提交插入，未送出訊息"); AppHaptics.tap(enabled: haptics)
    }
}
