import Foundation

/// Resolve one root for both ordinary data and credentials, so the app does not
/// accidentally save settings locally while still requiring a group for its key.
struct StorageLocation: Equatable {
    let url: URL
    let isShared: Bool

    static func resolve(shared: URL?, local: URL?, isExtension: Bool) throws -> StorageLocation {
        if let shared { return StorageLocation(url: shared, isShared: true) }
        guard !isExtension else {
            throw ChaiError.message("此鍵盤無法與主 App 共用資料，AI 功能目前不可用。請到主 App 處理文字後複製使用；開啟完整取用無法補上缺少的共享權限。本機計算仍可使用。")
        }
        guard let local else { throw ChaiError.message("無法取得 App 本機儲存空間，請重新開啟 App 後再試。") }
        return StorageLocation(url: local, isShared: false)
    }

    #if os(iOS)
    static var sharedContainer: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    static func current() throws -> StorageLocation {
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        let shared = sharedContainer
        // Never use an extension-private fallback: it would be isolated from the host app.
        let local = isExtension ? nil : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("ChaiToolsPrivate", isDirectory: true)
        let location = try resolve(shared: shared, local: local, isExtension: isExtension)
        if !location.isShared {
            try FileManager.default.createDirectory(at: location.url, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var root = location.url
            var flags = URLResourceValues(); flags.isExcludedFromBackup = true
            try root.setResourceValues(flags)
        }
        return location
    }
    #endif
}
