import Foundation
import Security

/// Best-effort, delete-only cleanup of old releases. It never blocks current
/// file storage, and lack of entitlement is not proof that an old key exists.
enum LegacyCredentialCleanup {
    static func runOnce() -> String? {
        let marker = "legacyKeychainRemoved111"
        guard !UserDefaults.standard.bool(forKey: marker) else { return nil }
        guard StorageLocation.sharedContainer != nil,
              let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String else {
            return "目前無法檢查或清除舊版鑰匙圈範圍；不代表存在舊金鑰。新版不讀取它，也不影響主 App 的本機儲存。恢復共享權限後會再嘗試清理。"
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "cc.chaihome.ChaiTools.openai",
            kSecAttrAccount as String: "user-api-key",
            kSecAttrAccessGroup as String: group
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return "舊版資料暫時無法清理（\(status)）；新版不會讀取它，也不影響新金鑰的儲存、使用或刪除。"
        }
        UserDefaults.standard.set(true, forKey: marker)
        return nil
    }
}
