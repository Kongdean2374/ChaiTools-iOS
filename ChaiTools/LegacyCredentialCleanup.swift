import Foundation
import Security

/// Delete-only cleanup for versions <= 1.1.0. Never reads or writes a Keychain secret.
/// New credentials are exclusively handled by CredentialStore.
enum LegacyCredentialCleanup {
    static func runOnce() throws {
        let marker = "legacyKeychainRemoved111"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String else {
            throw ChaiError.message("無法確認舊版金鑰範圍。")
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "cc.chaihome.ChaiTools.openai",
            kSecAttrAccount as String: "user-api-key",
            kSecAttrAccessGroup as String: group
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ChaiError.message("舊版鑰匙圈金鑰清除失敗（\(status)）。新版不會讀取它；請確認共享權限後重新開啟 App 以重試清除。")
        }
        UserDefaults.standard.set(true, forKey: marker)
    }
}
