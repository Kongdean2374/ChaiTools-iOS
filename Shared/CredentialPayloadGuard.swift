import Foundation

enum CredentialPayloadGuard {
    static func validate(_ body: [String: Any], key: String) throws {
        guard !key.isEmpty else { throw ChaiError.message("尚未設定 API 金鑰，請先儲存金鑰。") }
        try SensitiveContentGuard.validateJSON(body, key: key)
    }
}
