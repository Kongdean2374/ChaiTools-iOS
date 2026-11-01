import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class SharedStore {
    let directory: URL
    static func live() throws -> SharedStore {
        #if os(iOS)
        return try SharedStore(directory: StorageLocation.current().url)
        #else
        throw ChaiError.message("此環境沒有 App Group")
        #endif
    }
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let fd = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw ChaiError.message("無法鎖定共享資料") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ChaiError.message("共享資料正在更新，請稍後再試。") }
        defer { flock(fd, LOCK_UN) }
        return try operation()
    }
    private func read<T: Codable>(_ name: String, default value: T) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return value }
        let data = try Data(contentsOf: url)
        do {
            try SensitiveContentGuard.validate(String(decoding: data, as: UTF8.self))
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            try SensitiveContentGuard.validateJSON(object)
        }
        catch {
            // Purge a contaminated legacy file before any state is restored. Do not quarantine secrets.
            try FileManager.default.removeItem(at: url)
            throw ChaiError.message("已移除無法安全載入的舊資料（格式無效或含敏感憑證），請重新建立內容。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try SensitiveContentGuard.validate(value: value)
        let data = try JSONEncoder().encode(value)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutableURL = url; try mutableURL.setResourceValues(values)
        #endif
    }
    func preferences() throws -> Preferences { try locked { try read("preferences-v1.json", default: Preferences()) } }
    func updatePreferences(_ edit: (inout Preferences) -> Void) throws {
        try locked {
            var p = try read("preferences-v1.json", default: Preferences()); edit(&p)
            try write(p, name: "preferences-v1.json")
            if !p.history { try write([WorkTask](), name: "history-v1.json") }
        }
    }
    func history() throws -> [WorkTask] {
        try locked {
            let all = try read("history-v1.json", default: [WorkTask]())
            let fresh = all.filter { Date().timeIntervalSince($0.date) < 7 * 86400 }
            if fresh.count != all.count { try write(fresh, name: "history-v1.json") }
            return fresh
        }
    }
    func save(_ task: WorkTask) throws {
        try SensitiveContentGuard.validate(value: task)
        try locked {
            let p = try read("preferences-v1.json", default: Preferences())
            guard p.history else { return }
            var all = try read("history-v1.json", default: [WorkTask]()).filter { $0.id != task.id && Date().timeIntervalSince($0.date) < 7 * 86400 }
            all.insert(task, at: 0); all = Array(all.prefix(50))
            try write(all, name: "history-v1.json")
        }
    }
    func delete(_ id: UUID? = nil) throws {
        try locked {
            if id == nil { try write([WorkTask](), name: "history-v1.json"); return }
            var all = try read("history-v1.json", default: [WorkTask]())
            if let id { all.removeAll { $0.id == id } } else { all.removeAll() }
            try write(all, name: "history-v1.json")
        }
    }
}
