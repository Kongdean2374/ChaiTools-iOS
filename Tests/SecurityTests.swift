import XCTest
import Combine
@testable import ChaiToolsCore

/// Synthetic fixtures only. No real API credentials or outbound connections.
final class SecurityTests: XCTestCase {
    private var fake: String { "sk-" + "proj-" + String(repeating: "Synthetic9", count: 5) }
    private func response(text: String, title: String = "來源", url: String = "https://example.com") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status":"completed", "output":[["content":[["text":text, "annotations":[["type":"url_citation", "title":title, "url":url]]]]]]])
    }
    func testS01S02S03CommonEntryBoundaryAndVariants() throws {
        let variants = [fake, "前文 \(fake) 後文", fake.map(String.init).joined(separator: " "), fake.map(String.init).joined(separator: "\u{200B}"), fake.map(String.init).joined(separator: "\n"), fake.map(String.init).joined(separator: "\0")]
        for value in variants {
            XCTAssertThrowsError(try SensitiveContentGuard.checked(value)) { error in
                XCTAssertEqual(SensitiveContentGuard.userMessage(error), SensitiveContentGuard.message)
            }
        }
        for safe in ["sk-...", "sk-short", "let apiKey = ProcessInfo.processInfo.environment[\"OPENAI_API_KEY\"]", "幫我寫一封 Email"] {
            XCTAssertNoThrow(try SensitiveContentGuard.checked(safe))
        }
    }
    func testCurrentAndDeletedKeyFingerprintBlocksNonstandardCredential() throws {
        let key = "synthetic-unusual-credential-8u4PL2"
        SensitiveContentGuard.remember([.init(key: key)])
        XCTAssertThrowsError(try SensitiveContentGuard.checked("prefix " + key + " suffix"))
        XCTAssertThrowsError(try SensitiveContentGuard.checked(key.map(String.init).joined(separator: "\t")))
        // Registry deliberately survives key deletion; it contains hashes only.
        let data = try JSONEncoder().encode(SensitiveContentGuard.Fingerprint(key: key))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(key))
    }
    func testS04ParseRejectsMainDetailsCitationAndEscapedJSON() throws {
        let detail = String(decoding: try JSONSerialization.data(withJSONObject: ["natural":"安全答案", "context":fake]), as: UTF8.self)
        for data in [try response(text: fake), try response(text: detail), try response(text: "正常", title: fake), try response(text: "正常", url: "https://example.com/?q=" + fake)] {
            XCTAssertThrowsError(try AIClient.parse(data))
        }
        let escaped = String(decoding: try response(text: fake), as: UTF8.self).replacingOccurrences(of: "sk-", with: #"\u0073\u006b-"#)
        XCTAssertThrowsError(try AIClient.parse(Data(escaped.utf8)))
    }
    func testSelectionIdentityAndContextChangesRejectReplacement() {
        let doc = UUID()
        let snapshot = SelectionFingerprint(document: doc, selection: "原文", before: "前", after: "後")
        XCTAssertTrue(snapshot.matches(document: doc, selection: "原文", before: "前", after: "後"))
        XCTAssertFalse(snapshot.matches(document: UUID(), selection: "原文", before: "前", after: "後"))
        XCTAssertFalse(snapshot.matches(document: doc, selection: "其他", before: "前", after: "後"))
        XCTAssertFalse(snapshot.matches(document: doc, selection: "原文", before: "改變", after: "後"))
        XCTAssertFalse(snapshot.matches(document: doc, selection: nil, before: "前", after: "後"))
    }
    func testS05ErrorsNeverEchoServerCodeHeadersOrUnknownError() throws {
        let data = try JSONSerialization.data(withJSONObject: ["error":["code":fake, "message":"Authorization: Bearer " + fake]])
        for code in [400, 401, 403, 429, 500] {
            let error = AIClient.apiError(code, data: data)
            XCTAssertFalse(error.localizedDescription.contains(fake))
            XCTAssertFalse(error.localizedDescription.contains("Authorization"))
        }
        let error = NSError(domain: "untrusted", code: 7, userInfo: [NSLocalizedDescriptionKey: fake])
        XCTAssertFalse(SensitiveContentGuard.userMessage(error).contains(fake))
    }
    func testS06PersistenceRejectsAndPurgesContaminatedLegacyFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SharedStore(directory: root)
        try store.updatePreferences { $0.history = true }
        var task = WorkTask(tool: Tool.defaults[2], source: "正常主題")
        task.append(Answer(text: fake), instruction: "正常")
        XCTAssertThrowsError(try store.save(task))
        XCTAssertTrue(try store.history().isEmpty)
        let history = root.appendingPathComponent("history-v1.json")
        try JSONEncoder().encode([task]).write(to: history)
        XCTAssertThrowsError(try store.history())
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.path))
        XCTAssertTrue(try store.history().isEmpty)
        XCTAssertThrowsError(try store.updatePreferences { $0.tools[0].prompt = fake })
        XCTAssertFalse(try store.preferences().tools[0].prompt.contains(fake))
        var prefs = Preferences(); prefs.tools[0].fields = fake
        let prefFile = root.appendingPathComponent("preferences-v1.json")
        try JSONEncoder().encode(prefs).write(to: prefFile)
        XCTAssertThrowsError(try store.preferences())
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefFile.path))
        XCTAssertEqual(try store.preferences().model, Preferences().model)
    }
    @MainActor func testPublishedStateNeverReceivesBlockedPasteEditOrRestoredResult() throws {
        let model = WorkspaceModel(tool: Tool.defaults[2])
        var seen: [String] = []
        let a = model.$task.sink { seen.append($0.source); seen.append($0.answer?.text ?? "") }
        let b = model.$instruction.sink { seen.append($0) }
        let c = model.$result.sink { seen.append($0) }
        defer { a.cancel(); b.cancel(); c.cancel() }
        XCTAssertFalse(model.setSource(fake))
        XCTAssertFalse(model.setInstruction(fake))
        XCTAssertFalse(model.setResult(fake))
        model.saveEdit(fake)
        model.accept(Answer(text: "safe", details: ["context": fake]))
        XCTAssertTrue(model.task.revisions.isEmpty)
        XCTAssertTrue(seen.allSatisfy { !$0.contains(fake) })
        XCTAssertEqual(try model.output(), "")
        var legacy = WorkTask(tool: Tool.defaults[1], source: fake)
        legacy.append(Answer(text: fake), instruction: fake)
        let restored = WorkspaceModel(tool: Tool.defaults[1], task: legacy)
        XCTAssertEqual(restored.task.source, "")
        XCTAssertEqual(restored.result, "")
        XCTAssertEqual(restored.error, SensitiveContentGuard.message)
    }
    func testAssembledPayloadRejectsNestedUnknownAndObfuscatedKey() throws {
        for body: [String: Any] in [["model": fake], ["input": ["text":fake]], ["tools": [[fake: "value"]]], ["instructions": fake.map(String.init).joined(separator: " ")]] {
            XCTAssertThrowsError(try CredentialPayloadGuard.validate(body, key: "synthetic-auth-only"))
        }
    }
    func testMockTransportBlocksBeforeNetworkAndAfterResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SecurityProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = AIClient(session: session)
        SecurityProtocol.reset(payload: try response(text: "正常"))
        do { _ = try await client.run(tool: Tool.defaults[2], source: fake, instruction: "", preferences: Preferences(), key: "synthetic-auth-only"); XCTFail("Must block before network") } catch {}
        XCTAssertEqual(SecurityProtocol.calls, 0)
        SecurityProtocol.reset(payload: try response(text: fake))
        do { _ = try await client.run(tool: Tool.defaults[2], source: "正常", instruction: "", preferences: Preferences(), key: "synthetic-auth-only"); XCTFail("Must block response") } catch { XCTAssertEqual(SensitiveContentGuard.userMessage(error), SensitiveContentGuard.message) }
        XCTAssertEqual(SecurityProtocol.calls, 1)
        let unusual = "synthetic-response-echo-credential"
        SecurityProtocol.reset(payload: try response(text: unusual))
        do { _ = try await client.run(tool: Tool.defaults[2], source: "正常", instruction: "", preferences: Preferences(), key: unusual); XCTFail("Must block exact current key") } catch {}
    }
    @MainActor func testConversationGenerateReviseCancelAndSafeExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SharedStore(directory: root)
        try store.updatePreferences { $0.history = true }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SecurityProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let model = WorkspaceModel(tool: Tool.defaults[2], client: AIClient(session: session), keyLoader: { "synthetic-auth-only" }, storeProvider: { store })
        SecurityProtocol.reset(payload: try response(text: "第一版"))
        XCTAssertTrue(model.setSource("幫我寫一篇介紹"))
        model.run(preferences: Preferences())
        while model.busy { await Task.yield() }
        XCTAssertEqual(try model.output(), "第一版")
        XCTAssertEqual(model.task.revisions.count, 1)
        XCTAssertTrue(model.setInstruction("再短一些"))
        SecurityProtocol.reset(payload: try response(text: "精簡版"))
        model.run(preferences: Preferences(), revision: true)
        while model.busy { await Task.yield() }
        XCTAssertEqual(model.task.source, "幫我寫一篇介紹")
        XCTAssertEqual(model.task.revisions.last?.instruction, "再短一些")
        XCTAssertEqual(try model.output(), "精簡版")
        model.select(0); XCTAssertEqual(try model.output(), "第一版")
        SecurityProtocol.reset(payload: try response(text: fake))
        model.run(preferences: Preferences(), revision: true)
        while model.busy { await Task.yield() }
        XCTAssertEqual(model.task.revisions.count, 2)
        XCTAssertEqual(try model.output(), "第一版")
        XCTAssertFalse(String(decoding: try Data(contentsOf: root.appendingPathComponent("history-v1.json")), as: UTF8.self).contains(fake))
        model.run(preferences: Preferences()); model.cancel()
        XCTAssertFalse(model.busy); XCTAssertEqual(model.task.source, "幫我寫一篇介紹")
        try store.delete(); XCTAssertTrue(try store.history().isEmpty)
    }
}
private final class SecurityProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var payload = Data()
    private static var count = 0
    static var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset(payload: Data) { lock.lock(); defer { lock.unlock() }; self.payload = payload; count = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; let payload = Self.payload; Self.lock.unlock()
        XCTAssertTrue(request.url?.host == "api.openai.com")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
