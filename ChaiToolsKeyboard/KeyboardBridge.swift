import SwiftUI
import UIKit

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
    @Published var hasKey = false
    @Published var showingInformation = false
    @Published var connectionStatus = "尚未測試"
    @Published var needsGlobe = false
    @Published var model: WorkspaceModel?
    @Published var notice: KeyboardNotice?
    @Published var homeSource = ""
    @Published var detailed = false
    @Published var showingAllTools = false
    @Published var showResult = false
    @Published var haptics = true
    var snapshot: SelectionFingerprint?
    private var homePastePending = false
    private var cachedModels: [String: WorkspaceModel] = [:]
    private var refreshTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var refreshID = UUID()
    var canUseAI: Bool { !loadingPreferences && fullAccess && sharing && hasKey }
    var availableTools: [Tool] { canUseAI ? tools : tools.filter { $0.id == "calculate" } }
    var statusLabel: String { notice != nil ? (notice?.isError == true ? "操作已攔截" : "已完成") : loadingPreferences ? "讀取設定" : !fullAccess ? "本機模式" : !sharing ? "缺少共享授權" : !hasKey ? "尚未設金鑰" : "AI 已備妥" }
    var tools: [Tool] { preferences.tools.filter(\.enabled).sorted { $0.favorite && !$1.favorite } }

    func refresh() {
        fullAccess = controller?.hasFullAccess ?? false
        let id = UUID(); refreshID = id
        refreshTask?.cancel()
        guard fullAccess else { sharing = false; loadingPreferences = false; return }
        loadingPreferences = true
        refreshTask = Task {
            let loaded = await Task.detached(priority: .utility) { () -> (Preferences?, Bool, Bool, String) in
                guard StorageLocation.sharedContainer != nil else { return (nil, false, false, "") }
                do {
                    try CredentialStore.prepareGuard()
                    return (try SharedStore.live().preferences(), true, try CredentialStore.hasKey(), "")
                } catch { return (nil, true, false, SensitiveContentGuard.userMessage(error)) }
            }.value
            guard !Task.isCancelled, refreshID == id else { return }
            loadingPreferences = false
            sharing = loaded.1; hasKey = loaded.2
            if !loaded.3.isEmpty { notify(loaded.3, error: true) }
            if let p = loaded.0 { preferences = p }
        }
    }
    func select(_ tool: Tool) {
        guard tool.id == "calculate" || canUseAI else { explainAvailability(); return }
        guard (try? SensitiveContentGuard.validate(value: tool)) != nil else { notify(SensitiveContentGuard.message, error: true); return }
        model?.cancel(); snapshot = nil; notice = nil; showingAllTools = false; showingInformation = false
        if !homePastePending, let cached = cachedModels[tool.id] { model = cached; cached.updateTool(tool) }
        else {
            let next = WorkspaceModel(tool: tool)
            _ = next.setSource(homeSource)
            // Bound retained drafts/results; all tools remain selectable.
            if cachedModels.count >= 4 { cachedModels.removeAll() }
            cachedModels[tool.id] = next; model = next
        }
        homePastePending = false
        showResult = !(model?.result.isEmpty ?? true)
        AppHaptics.tap(enabled: haptics)
    }
    func resetContext() {
        model?.cancel(); model = nil; cachedModels.removeAll(); snapshot = nil; homeSource = ""; homePastePending = false; showResult = false
    }
    func home() { model?.cancel(); model = nil; snapshot = nil; showingAllTools = false; showingInformation = false; AppHaptics.tap(enabled: haptics) }
    func suspend() { model?.cancel(); refreshTask?.cancel(); refreshID = UUID(); noticeTask?.cancel() }
    func notify(_ text: String, error: Bool = false) {
        noticeTask?.cancel()
        let item = KeyboardNotice(text: (try? SensitiveContentGuard.checked(text)) ?? SensitiveContentGuard.message, isError: error); notice = item
        if !error {
            noticeTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, notice?.id == item.id else { return }; notice = nil
            }
        }
    }
    func explainAvailability() {
        showingInformation = true
        if loadingPreferences { notify("正在讀取設定，請稍候再試。"); return }
        if !fullAccess { notify("AI 需在 iOS 設定 → 一般 → 鍵盤 → ChaiTools 允許完整取用。本機計算仍可用。", error: true) }
        else if !sharing { notify("此安裝版本無法與主 App 共用金鑰。請在主 App 處理後複製使用；完整取用無法補上共享權限。", error: true) }
        else if !hasKey { notify("請先在主 App 儲存金鑰，再重新開啟鍵盤。", error: true) }
        else { notify("只在你點執行時送出文字。金鑰與模型在主 App 設定。") }
    }
    func captureSelection() {
        guard model?.busy != true else { return }
        guard let p = controller?.textDocumentProxy, let selected = p.selectedText, !selected.isEmpty else { snapshot = nil; notify("取不到選取文字，請先複製，再點貼上。", error: true); return }
        guard selected.count <= 8000 else { notify("超過 8,000 字，請使用主 App。", error: true); return }
        guard (try? SensitiveContentGuard.validate(selected)) != nil else { snapshot = nil; notify(SensitiveContentGuard.message, error: true); return }
        snapshot = SelectionFingerprint(document: p.documentIdentifier, selection: selected, before: p.documentContextBeforeInput, after: p.documentContextAfterInput)
        _ = model?.setSource(selected); showResult = false
        notify("已讀取選取文字")
    }
    func paste(_ target: String) {
        guard model?.busy != true else { return }
        guard controller?.hasFullAccess == true else { notify("貼上需要完整取用；也可在主 App 處理。", error: true); return }
        guard let text = UIPasteboard.general.string, !text.isEmpty else { notify("剪貼簿沒有文字，請先複製。", error: true); return }
        guard text.count <= 8000 else { notify("超過 8,000 字，請使用主 App。", error: true); return }
        guard (try? SensitiveContentGuard.validate(text)) != nil else { notify(SensitiveContentGuard.message, error: true); return }
        switch target {
        case "home": homeSource = text; homePastePending = true; notify("已貼上，請選擇工具")
        case "source": _ = model?.setSource(text); snapshot = nil; showResult = false; notify("已貼上原文")
        case "instruction": _ = model?.setInstruction(text); notify("已貼上追加指令／主題")
        default: model?.saveEdit(text); showResult = true; notify("已儲存貼上的新版本")
        }
    }
    func run(revision: Bool = false) {
        guard let model, !model.busy else { return }
        let input = revision ? model.result : model.task.source
        guard input.count <= 20000, model.task.source.count <= 8000 else { notify("內容過長，請使用主 App。", error: true); return }
        fullAccess = controller?.hasFullAccess ?? false
        if model.task.tool.id != "calculate" || (try? Calculator.evaluate(input)) == nil {
            guard canUseAI else { explainAvailability(); return }
        }
        let configuration = model.task.tool.id == "translate" ? (detailed ? "詳細模式。" : "快速模式。") : ""
        model.run(preferences: preferences, networkAllowed: fullAccess, revision: revision, configuration: configuration)
        if !model.error.isEmpty { notify(model.error, error: true) }
        AppHaptics.tap(enabled: haptics)
    }
    func copy() {
        guard let model, !model.result.isEmpty else { return }
        let result: String
        do { result = try model.output() } catch { notify(SensitiveContentGuard.userMessage(error), error: true); return }
        UIPasteboard.general.string = result; notify("已複製結果"); AppHaptics.tap(enabled: haptics)
    }
    func insert(replace: Bool) {
        guard let p = controller?.textDocumentProxy, let model, !model.result.isEmpty else { return }
        let result: String
        do { result = try model.output() } catch { notify(SensitiveContentGuard.userMessage(error), error: true); return }
        if replace {
            guard let s = snapshot, s.matches(document: p.documentIdentifier, selection: p.selectedText, before: p.documentContextBeforeInput, after: p.documentContextAfterInput) else {
                snapshot = nil; notify("選取或欄位已改變。請取消選取後插入，或複製結果。", error: true); return
            }
        } else if let selected = p.selectedText, !selected.isEmpty {
            notify("目前仍有選取文字，請取消選取或點『取代選取』。", error: true); return
        }
        p.insertText(result); snapshot = nil
        notify("已提交插入，未送出訊息"); AppHaptics.tap(enabled: haptics)
    }
}
