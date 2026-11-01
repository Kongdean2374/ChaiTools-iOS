import Foundation
import CryptoKit

/// Ordinary text only. The credential editor/storage and Authorization header are separate.
/// Detection is deliberately conservative; placeholders such as `sk-...` remain valid prose.
enum SensitiveContentGuard {
    static let message = "偵測到敏感憑證，已阻止顯示與複製。請移除憑證後再試。"
    struct Fingerprint: Codable, Equatable {
        let length: Int
        let digest: Data
        init(key: String) {
            let bytes = Data(normalized(key).utf8)
            length = bytes.count
            digest = Data(SHA256.hash(data: bytes))
        }
    }
    private static let lock = NSLock()
    private static var fingerprints: [Fingerprint] = []
    static func remember(_ values: [Fingerprint]) {
        lock.lock(); defer { lock.unlock() }
        for value in values where !fingerprints.contains(value) { fingerprints.append(value) }
    }
    static func normalized(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format
        }))
    }
    static func validate(_ text: String, key: String? = nil) throws {
        let compact = normalized(text)
        // A prefix alone or short documentation placeholder is not a credential.
        if compact.range(of: #"(?i)sk-(?:proj-|svcacct-)?[a-z0-9_-]{16,}"#, options: .regularExpression) != nil {
            throw ChaiError.message(message)
        }
        if let key, !key.isEmpty, compact.contains(normalized(key)) { throw ChaiError.message(message) }
        lock.lock(); let known = fingerprints; lock.unlock()
        let bytes = Array(compact.utf8)
        for value in known where value.length > 0 && bytes.count >= value.length {
            for offset in 0...(bytes.count - value.length) {
                let digest = Data(SHA256.hash(data: Data(bytes[offset..<(offset + value.length)])))
                if digest == value.digest { throw ChaiError.message(message) }
            }
        }
    }
    static func validateJSON(_ object: Any, key: String? = nil) throws {
        if let text = object as? String { try validate(text, key: key) }
        else if let list = object as? [Any] { for value in list { try validateJSON(value, key: key) } }
        else if let map = object as? [String: Any] {
            for (name, value) in map { try validate(name, key: key); try validateJSON(value, key: key) }
        }
    }
    static func validate<T: Encodable>(value: T, key: String? = nil) throws {
        let data = try JSONEncoder().encode(value)
        try validateJSON(JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]), key: key)
    }
    static func checked(_ text: String) throws -> String { try validate(text); return text }
    /// Error text is never allowed to echo arbitrary server bodies, headers or decoder context.
    static func userMessage(_ error: Error) -> String {
        if let e = error as? ChaiError { return (try? checked(e.localizedDescription)) ?? message }
        if let e = error as? URLError {
            return e.code == .cancelled ? "請求已取消。" : "網路連線未完成（\(e.code.rawValue)），請確認網路後重試。"
        }
        return "無法完成操作，請解鎖裝置並稍後重試。原稿已保留。"
    }
}
