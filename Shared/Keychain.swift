#if canImport(Security)
import Foundation
import Security

enum Keychain {
    private static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"cc.chaihome.ChaiTools.openai",kSecAttrAccount as String:"user-api-key"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    private static func failure(_ status: OSStatus, action: String) -> ChaiError {
        if status == errSecMissingEntitlement {
            return .message("無法\(action)金鑰：此 App 的共享 Keychain 權限不可用（\(status)）。這不是 API 金鑰錯誤；App 與鍵盤需要一致、有效的 App Group 權限。")
        }
        if status == errSecInteractionNotAllowed {
            return .message("無法\(action)金鑰：裝置目前不允許存取 Keychain。請解鎖裝置後重試（\(status)）。")
        }
        return .message("Keychain \(action)失敗（\(status)）。未確認成功，請重試。")
    }
    static func load() throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw failure(status, action: "讀取") }
        return key
    }
    static func save(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ChaiError.message("請輸入金鑰") }
        let attributes: [String: Any] = [kSecValueData as String:Data(clean.utf8),kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; attributes.forEach { q[$0.key] = $0.value }; status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status, action: "儲存") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status, action: "刪除") }
    }
}
#endif
