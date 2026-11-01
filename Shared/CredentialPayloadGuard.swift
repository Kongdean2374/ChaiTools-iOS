import Foundation

enum CredentialPayloadGuard {
    static func validate(_ body: [String: Any], key: String) throws {
        guard !key.isEmpty else { throw ChaiError.message("尚未設定 API 金鑰，請先儲存金鑰。") }
        func containsKey(_ value: Any) -> Bool {
            if let text = value as? String { return text.contains(key) }
            if let list = value as? [Any] { return list.contains(where: containsKey) }
            if let map = value as? [String: Any] { return map.keys.contains(where: { $0.contains(key) }) || map.values.contains(where: containsKey) }
            return false
        }
        guard !containsKey(body) else {
            throw ChaiError.message("已阻止送出：文字或工具設定包含目前的 API 金鑰。請移除金鑰後再試。")
        }
    }
}
