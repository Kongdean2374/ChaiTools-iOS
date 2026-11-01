import SwiftUI
import UIKit

@MainActor final class SettingsModel: ObservableObject {
    @Published var preferences = Preferences()
    @Published var key = "" { didSet { pasteNotice = nil } }
    @Published var pasteNotice: OperationNotice?
    @Published var hasKey = false
    @Published var sharingAvailable = false
    @Published var legacyCleanupMessage: String?
    @Published var models: [String] = []
    @Published var notice: OperationNotice?
    @Published var alert: OperationNotice?
    @Published var activity: String?
    @Published var started = Date()
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    var busy: Bool { activity != nil }

    func load() {
        legacyCleanupMessage = LegacyCredentialCleanup.runOnce()
        do { sharingAvailable = try StorageLocation.current().isShared }
        catch { finish("無法存取儲存空間", error.localizedDescription, kind: .failure, showAlert: false) }
        do { preferences = try SharedStore.live().preferences() }
        catch { finish("無法讀取偏好", error.localizedDescription, kind: .failure, showAlert: false) }
        do { hasKey = try CredentialStore.hasKey() }
        catch { finish("無法讀取金鑰", error.localizedDescription, kind: .failure, showAlert: false) }
    }
    func pasteKey() {
        guard !busy else { return }
        // Read only in response to this explicit button tap. Never on appearance.
        guard let clipboard = UIPasteboard.general.string else {
            pasteNotice = OperationNotice(title: "尚未取得文字", message: "請先複製純文字金鑰，再點貼上。若 iOS 詢問是否允許貼上，請允許；若曾拒絕，可在 iOS 的 ChaiTools 設定中檢查『從其他 App 貼上』權限。原輸入已保留。", kind: .failure)
            return
        }
        do {
            let clean = try APIKeyInput.normalize(clipboard)
            key = clean
            pasteNotice = OperationNotice(title: "金鑰已貼入", message: "已填入 \(clean.count) 個字元並保持遮罩。請接著點『儲存金鑰』；尚未儲存或測試連線。", kind: .success)
            AppHaptics.result(success: true)
        } catch {
            pasteNotice = OperationNotice(title: "未貼上金鑰", message: error.localizedDescription + " 原輸入已保留。", kind: .failure)
        }
    }
    func clearKeyInput() {
        guard !busy else { return }
        key = ""
        pasteNotice = OperationNotice(title: "輸入欄已清空", message: "沒有刪除 App 中已儲存的金鑰。")
    }
    func saveKey() {
        guard !busy else { return }
        do {
            let clean = try APIKeyInput.normalize(key)
            try CredentialStore.save(clean)
            hasKey = true; key = ""
            finish("金鑰已安全儲存", "已存入 App 的加密保護檔案並完成讀回驗證。接著點『測試 API 連線』確認模型是否可用。", kind: .success)
        } catch { finish("儲存失敗", error.localizedDescription, kind: .failure) }
    }
    func deleteKey() {
        guard !busy else { return }
        do {
            try CredentialStore.delete(); hasKey = false; key = ""; models = []
            legacyCleanupMessage = LegacyCredentialCleanup.runOnce()
            finish("金鑰已刪除", "之後的 AI 請求需要重新設定金鑰。本機計算仍可使用。", kind: .success)
        } catch { finish("無法刪除金鑰", error.localizedDescription, kind: .failure) }
    }
    private func savedKey() throws -> String {
        guard key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChaiError.message("輸入欄中有尚未儲存的金鑰。請先點『儲存金鑰』，避免測試到舊金鑰。")
        }
        let saved = try CredentialStore.load()
        guard !saved.isEmpty else { throw ChaiError.message("尚未儲存 API 金鑰。請在上方輸入後點『儲存金鑰』。") }
        return saved
    }
    func testConnection() {
        guard !busy else { return }
        do {
            let saved = try savedKey()
            let p = preferences
            guard !p.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChaiError.message("請先填入模型 ID。") }
            start("正在測試 \(p.model)") {
                let answer = try await AIClient().run(tool: Tool(id: "test", name: "連線測試", icon: "checkmark", prompt: "只回覆 OK。"), source: "連線測試", instruction: "簡短回覆", preferences: p, key: saved, maxOutputTokens: 1024)
                return ("API 連線成功", "已收到 \(p.model) 的真實回應。輸入 \(answer.inputTokens)、輸出 \(answer.outputTokens) tokens。這次測試不代表所有工具都受模型支援。")
            }
        } catch { finish("無法開始測試", error.localizedDescription, kind: .failure) }
    }
    func scanModels() {
        guard !busy else { return }
        do {
            let saved = try savedKey()
            start("正在取得可用模型") {
                let list = try await AIClient().models(key: saved)
                try Task.checkCancellation()
                self.models = list
                return ("模型清單已更新", "取得 \(list.count) 個模型。選擇後請儲存偏好，並測試 API 連線。")
            }
        } catch { finish("無法掃描模型", error.localizedDescription, kind: .failure) }
    }
    func savePreferences() {
        do {
            let model = preferences.model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { throw ChaiError.message("模型 ID 不能空白") }
            try SharedStore.live().updatePreferences { $0.model = model; $0.language = preferences.language; $0.context = preferences.context }
            preferences.model = model
            finish("偏好已儲存", sharingAvailable ? "模型、語言與語境已更新；重新開啟鍵盤後會讀取這些設定。" : "模型、語言與語境已儲存在主 App。此安裝版本無法與鍵盤共用資料。", kind: .success)
        } catch { finish("偏好儲存失敗", error.localizedDescription, kind: .failure) }
    }
    func setHistory(_ enabled: Bool) {
        do {
            try SharedStore.live().updatePreferences { $0.history = enabled }; preferences.history = enabled
            finish(enabled ? "已開啟工作紀錄" : "已關閉並清除工作紀錄", enabled ? "最多保留 7 天／50 筆，可隨時關閉。" : "之後的原文與結果不會永久儲存。", kind: .success)
        } catch { finish("紀錄設定失敗", error.localizedDescription, kind: .failure) }
    }
    private func start(_ title: String, action: @escaping @MainActor () async throws -> (String, String)) {
        let id = UUID(); operationID = id; activity = title; started = Date()
        notice = OperationNotice(title: title, message: "正在等待 OpenAI 回應，最長約 60 秒。你可以隨時取消。")
        operation = Task { @MainActor in
            do {
                let result = try await action()
                try Task.checkCancellation()
                guard operationID == id else { return }
                activity = nil; operationID = nil; operation = nil
                finish(result.0, result.1, kind: .success)
            } catch {
                guard operationID == id else { return }
                activity = nil; operationID = nil; operation = nil
                finish("請求未完成", Self.errorMessage(error), kind: .failure)
            }
        }
    }
    func cancel() {
        guard busy else { return }
        operationID = nil; operation?.cancel(); operation = nil; activity = nil
        finish("已取消請求", "沒有修改已儲存的金鑰與偏好。", kind: .info, showAlert: false)
    }
    private func finish(_ title: String, _ message: String, kind: OperationNotice.Kind, showAlert: Bool = true) {
        let update = OperationNotice(title: title, message: message, kind: kind)
        notice = update
        if showAlert { alert = update }
        AppHaptics.result(success: kind != .failure)
    }
    static func errorMessage(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .timedOut: return "連線逾時。請檢查網路，或改用可存取的模型後重試。"
            case .notConnectedToInternet, .networkConnectionLost: return "網路未連線或已中斷。請確認 Wi-Fi／行動網路後重試。"
            case .cancelled: return "請求已取消。"
            default: return "網路連線失敗（\(e.code.rawValue)），請確認網路後重試。"
            }
        }
        return error.localizedDescription
    }
}
