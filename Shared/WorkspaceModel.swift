#if canImport(SwiftUI)
import SwiftUI

@MainActor final class WorkspaceModel: ObservableObject {
    @Published var task: WorkTask
    @Published var instruction = ""
    @Published var busy = false
    @Published var error = ""
    @Published var result = ""
    private var pending: Task<Void, Never>?
    init(tool: Tool, task: WorkTask? = nil) {
        self.task = task ?? WorkTask(tool: tool, source: "")
        result = task?.answer?.text ?? ""
    }
    func run(preferences: Preferences, networkAllowed: Bool = true, revision: Bool = false) {
        guard !busy else { return }
        error = ""
        let input = revision ? result : task.source
        if task.tool.id == "calculate", let value = try? Calculator.evaluate(input) {
            accept(Answer(text: "\(input) = \(value)\n（本機計算；百分比代表除以 100）")); return
        }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !instruction.isEmpty else { error = "請貼上文字，或輸入主題／要求。"; return }
        guard networkAllowed else { error = "請在 iOS 設定 → 一般 → 鍵盤 → ChaiTools 允許完整取用。"; return }
        busy = true
        let requestInstruction = instruction
        let requestTool = task.tool
        pending = Task {
            defer { busy = false }
            do {
                let key = try Keychain.load()
                let answer = try await AIClient().run(tool: requestTool, source: input, instruction: requestInstruction, preferences: preferences, key: key)
                try Task.checkCancellation()
                task.append(answer, instruction: requestInstruction); result = answer.text; persist()
            } catch is CancellationError { error = "已取消；保留原文與上一版結果。" }
            catch { self.error = (error as NSError).code == NSURLErrorCancelled ? "已取消" : error.localizedDescription }
        }
    }
    func accept(_ answer: Answer) {
        task.append(answer, instruction: instruction); result = answer.text; persist()
    }
    func saveEdit(_ text: String) { accept(Answer(text: text)) }
    func select(_ index: Int) {
        guard task.revisions.indices.contains(index) else { return }
        task.selected = index; result = task.answer?.text ?? ""; persist()
    }
    func persist() { do { try SharedStore.live().save(task) } catch { self.error = "結果可用，但未能儲存紀錄：\(error.localizedDescription)" } }
    func cancel() { pending?.cancel() }
    func clear() { cancel(); task = WorkTask(tool: task.tool, source: ""); result = ""; instruction = "" }
}
#endif
