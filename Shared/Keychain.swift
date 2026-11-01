#if canImport(Security)
import Foundation
import Security

enum Keychain {
    private static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"cc.chaihome.ChaiTools.openai",kSecAttrAccount as String:"user-api-key"]
        if let group = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String { q[kSecAttrAccessGroup as String] = group }
        return q
    }
    static func load() throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw ChaiError.message("無法讀取 Keychain（\(status)），請檢查共享權限。") }
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
        guard status == errSecSuccess else { throw ChaiError.message("金鑰儲存失敗（\(status)）") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ChaiError.message("刪除金鑰失敗（\(status)）") }
    }
}
#endif
