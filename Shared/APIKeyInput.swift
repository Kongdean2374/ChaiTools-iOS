import Foundation

/// Validate only transport-safe input; API authorization remains a real server test.
/// Do not assume a particular key prefix or print the submitted value in an error.
enum APIKeyInput {
    static func normalize(_ value: String) throws -> String {
        guard value.utf8.count <= 8192 else { throw ChaiError.message("內容過長，請只複製 API 金鑰本身。") }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ChaiError.message("沒有可貼上的金鑰文字。") }
        guard !clean.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else {
            throw ChaiError.message("內容中含有空白、換行或控制字元。請只複製金鑰，不要連同說明或指令一起複製。")
        }
        return clean
    }
}
