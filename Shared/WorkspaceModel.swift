#if canImport(SwiftUI)
import SwiftUI

@MainActor final class WorkspaceModel: ObservableObject {
    @Published private(set) var task: WorkTask
    @Published private(set) var instruction = ""
    @Published var busy = false
    @Published var error = ""
    @Published private(set) var result = ""
    @Published var status = ""
    private var requestID: UUID?
    private var pending: Task<Void, Never>?
    private let client: AIClient
    private let keyLoader: () throws -> String
    private let storeProvider: () throws -> SharedStore
    init(tool: Tool, task: WorkTask? = nil, client: AIClient = AIClient(),
         keyLoader: (() throws -> String)? = nil, storeProvider: @escaping () throws -> SharedStore = { try SharedStore.live() }) {
        self.client = client
        self.storeProvider = storeProvider
        self.keyLoader = keyLoader ?? {
            #if os(iOS)
            return try CredentialStore.load()
            #else
            throw ChaiError.message("測試環境未設定憑證提供者")
            #endif
        }
        let proposed = task ?? WorkTask(tool: tool, source: "")
        if (try? SensitiveContentGuard.validate(value: proposed)) != nil {
            self.task = proposed; result = proposed.answer?.text ?? ""
        } else {
            self.task = WorkTask(tool: Tool.defaults[2], source: "")
            error = SensitiveContentGuard.message
        }
    }
    @discardableResult func setSource(_ text: String) -> Bool { guarded { try SensitiveContentGuard.validate(text); task.source = text } }
    @discardableResult func setInstruction(_ text: String) -> Bool { guarded { try SensitiveContentGuard.validate(text); instruction = text } }
    @discardableResult func setResult(_ text: String) -> Bool { guarded { try SensitiveContentGuard.validate(text); result = text } }
    func updateTool(_ tool: Tool) { _ = guarded { try SensitiveContentGuard.validate(value: tool); task.tool = tool } }
    func output() throws -> String {
        try SensitiveContentGuard.validate(value: task)
        return try SensitiveContentGuard.checked(result)
    }
    private func guarded(_ action: () throws -> Void) -> Bool {
        do { try action(); return true }
        catch { self.error = SensitiveContentGuard.userMessage(error); return false }
    }
    func run(preferences: Preferences, networkAllowed: Bool = true, revision: Bool = false, configuration: String = "") {
        guard !busy else { return }
        error = ""; status = ""
        guard guarded({
            try SensitiveContentGuard.validate(value: task)
            try SensitiveContentGuard.validate(instruction)
            try SensitiveContentGuard.validate(result)
            try SensitiveContentGuard.validate(configuration)
            try SensitiveContentGuard.validate(value: preferences)
        }) else { return }
        let input = revision ? result : task.source
        if task.tool.id == "calculate", let value = try? Calculator.evaluate(input) {
            accept(Answer(text: "\(input) = \(value)\n（本機計算；百分比代表除以 100）")); return
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !instruction.isEmpty else { error = "請貼上文字，或輸入主題／要求。"; return }
        guard networkAllowed else { error = "請在 iOS 設定 → 一般 → 鍵盤 → ChaiTools 允許完整取用。"; return }
        busy = true
        let id = UUID(); requestID = id
        let visibleInstruction = instruction
        let requestInstruction = instruction + "\n" + configuration
        let requestTool = task.tool
        pending = Task {
            defer { if requestID == id { busy = false; requestID = nil; pending = nil } }
            do {
                let key = try keyLoader()
                let answer = try await client.run(tool: requestTool, source: input, instruction: requestInstruction, preferences: preferences, key: key)
                try Task.checkCancellation()
                guard requestID == id else { return }
                try SensitiveContentGuard.validate(value: answer, key: key)
                status = "已產生新版本，可預覽、編輯或複製。"
                task.append(answer, instruction: visibleInstruction); result = answer.text; persist()
            } catch is CancellationError { if requestID == id { error = "已取消；保留原文與上一版結果。" } }
            catch { guard requestID == id else { return }; self.error = (error as NSError).code == NSURLErrorCancelled ? "已取消" : SensitiveContentGuard.userMessage(error) }
        }
    }
    func accept(_ answer: Answer) {
        guard guarded({ try SensitiveContentGuard.validate(value: answer); try SensitiveContentGuard.validate(instruction) }) else { return }
        error = ""; task.append(answer, instruction: instruction); result = answer.text; status = "已建立第 \(task.selected + 1) 版。"; persist()
    }
    func saveEdit(_ text: String) { accept(Answer(text: text)) }
    func select(_ index: Int) {
        guard task.revisions.indices.contains(index) else { return }
        guard guarded({ try SensitiveContentGuard.validate(value: task) }) else { return }
        task.selected = index; result = task.answer?.text ?? ""; status = "已切換至第 \(index + 1) 版。"; persist()
    }
    func persist(manual: Bool = false) {
        // A keyboard without sharing can still compute/copy locally. It cannot
        // save history, and must not turn a successful local calculation into an error.
        #if os(iOS)
        if Bundle.main.bundleURL.pathExtension == "appex", StorageLocation.sharedContainer == nil, !manual { return }
        #endif
        do {
            try SensitiveContentGuard.validate(value: task)
            let store = try storeProvider()
            guard try store.preferences().history else {
                if manual { error = "尚未開啟工作紀錄。請先至設定開啟，再儲存草稿。" }
                return
            }
            try store.save(task)
            if manual { error = ""; status = "草稿與版本已儲存，可在工作紀錄繼續編輯。" }
        } catch { self.error = "結果可用，但未能儲存紀錄：\(SensitiveContentGuard.userMessage(error))" }
    }
    func cancel() {
        guard busy else { return }
        requestID = nil; pending?.cancel(); pending = nil; busy = false
        status = "已取消，保留原文與上一版結果。"
    }
    func clear() {
        cancel(); task = WorkTask(tool: task.tool, source: ""); result = ""; instruction = ""; error = ""; status = "工作區已清空。"
    }
}
#endif
