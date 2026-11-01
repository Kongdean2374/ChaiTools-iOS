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
        let group = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String ?? "group.cc.chaihome.ChaiTools"
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw ChaiError.message("無法存取 App Group，請確認 App 與鍵盤的共享權限一致。") }
        return try SharedStore(directory: url)
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
    private func read<T: Decodable>(_ name: String, default value: T) throws -> T {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return value }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
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
            var all = try read("history-v1.json", default: [WorkTask]())
            if let id { all.removeAll { $0.id == id } } else { all.removeAll() }
            try write(all, name: "history-v1.json")
        }
    }
}
