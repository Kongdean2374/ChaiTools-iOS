#if canImport(SwiftUI)
import SwiftUI

@MainActor final class WorkspaceModel: ObservableObject {
    @Published var task: WorkTask
    @Published var instruction = ""
    @Published var busy = false
    @Published var error = ""
    @Published var result = ""
    @Published var status = ""
    private var requestID: UUID?
    private var pending: Task<Void, Never>?
    init(tool: Tool, task: WorkTask? = nil) {
        self.task = task ?? WorkTask(tool: tool, source: "")
        result = task?.answer?.text ?? ""
    }
    func run(preferences: Preferences, networkAllowed: Bool = true, revision: Bool = false) {
        guard !busy else { return }
        error = ""; status = ""
        let input = revision ? result : task.source
        if task.tool.id == "calculate", let value = try? Calculator.evaluate(input) {
            accept(Answer(text: "\(input) = \(value)\n（本機計算；百分比代表除以 100）")); return
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !instruction.isEmpty else { error = "請貼上文字，或輸入主題／要求。"; return }
        guard networkAllowed else { error = "請在 iOS 設定 → 一般 → 鍵盤 → ChaiTools 允許完整取用。"; return }
        busy = true
        let id = UUID(); requestID = id
        let requestInstruction = instruction
        let requestTool = task.tool
        pending = Task {
            defer { if requestID == id { busy = false; requestID = nil; pending = nil } }
            do {
                let key = try CredentialStore.load()
                let answer = try await AIClient().run(tool: requestTool, source: input, instruction: requestInstruction, preferences: preferences, key: key)
                try Task.checkCancellation()
                guard requestID == id else { return }
                status = "已產生新版本，可預覽、編輯或複製。"
                task.append(answer, instruction: requestInstruction); result = answer.text; persist()
            } catch is CancellationError { if requestID == id { error = "已取消；保留原文與上一版結果。" } }
            catch { guard requestID == id else { return }; self.error = (error as NSError).code == NSURLErrorCancelled ? "已取消" : error.localizedDescription }
        }
    }
    func accept(_ answer: Answer) {
        error = ""; task.append(answer, instruction: instruction); result = answer.text; status = "已建立第 \(task.selected + 1) 版。"; persist()
    }
    func saveEdit(_ text: String) { accept(Answer(text: text)) }
    func select(_ index: Int) {
        guard task.revisions.indices.contains(index) else { return }
        task.selected = index; result = task.answer?.text ?? ""; status = "已切換至第 \(index + 1) 版。"; persist()
    }
    func persist(manual: Bool = false) {
        // A keyboard without sharing can still compute/copy locally. It cannot
        // save history, and must not turn a successful local calculation into an error.
        if Bundle.main.bundleURL.pathExtension == "appex", StorageLocation.sharedContainer == nil, !manual { return }
        do {
            let store = try SharedStore.live()
            guard try store.preferences().history else {
                if manual { error = "尚未開啟工作紀錄。請先至設定開啟，再儲存草稿。" }
                return
            }
            try store.save(task)
            if manual { error = ""; status = "草稿與版本已儲存，可在工作紀錄繼續編輯。" }
        } catch { self.error = "結果可用，但未能儲存紀錄：\(error.localizedDescription)" }
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
