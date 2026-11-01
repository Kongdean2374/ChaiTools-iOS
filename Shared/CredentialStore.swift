#if os(iOS)
import Foundation
import Darwin

/// Private App Group storage for the host app and its keyboard only.
/// iOS Data Protection encrypts the file at rest; no Keychain or embedded crypto key.
enum CredentialStore {
    private static func directory() throws -> URL {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw ChaiError.message("無法存取 App 私有共享空間，請確認 App 與鍵盤具有一致的 App Group 權限。")
        }
        return container.appendingPathComponent("PrivateCredentials", isDirectory: true)
    }
    private static func prepare(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700], ofItemAtPath: folder.path)
        var url = folder
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try url.setResourceValues(flags)
    }
    private static func locked<T>(_ action: (URL) throws -> T) throws -> T {
        let folder = try directory()
        try prepare(folder)
        let fd = open(folder.appendingPathComponent("credential.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw ChaiError.message("無法存取金鑰儲存空間。請解鎖裝置後重試。") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ChaiError.message("金鑰正在更新，請稍後重試。") }
        defer { flock(fd, LOCK_UN) }
        return try action(folder.appendingPathComponent("openai.credential"))
    }
    /// Check existence only; never load the secret merely to render a screen.
    static func hasKey() throws -> Bool {
        try locked { FileManager.default.fileExists(atPath: $0.path) }
    }
    static func load() throws -> String {
        try locked { file in
            guard FileManager.default.fileExists(atPath: file.path) else { return "" }
            guard let key = String(data: try Data(contentsOf: file), encoding: .utf8), !key.isEmpty else {
                throw ChaiError.message("App 內的金鑰資料無效，請重新輸入並儲存。")
            }
            return key
        }
    }
    static func save(_ key: String) throws {
        let clean = try APIKeyInput.normalize(key)
        try locked { file in
            try Data(clean.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o600], ofItemAtPath: file.path)
            var url = file
            var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try url.setResourceValues(flags)
            guard try Data(contentsOf: file) == Data(clean.utf8) else {
                throw ChaiError.message("金鑰寫入驗證失敗，請重試。")
            }
        }
    }
    static func delete() throws {
        try locked { file in
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
}
#endif
