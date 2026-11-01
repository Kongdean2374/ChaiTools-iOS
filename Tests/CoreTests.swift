import XCTest
@testable import ChaiToolsCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CoreTests: XCTestCase {
    func testKeyboardGeometryIsBoundedAcrossSupportedSizes() {
        for width in [CGFloat(320), 375, 390, 402, 430, 600] {
            let normal = KeyboardLayoutMetrics.contentHeight(width: width, landscape: false, accessibility: false)
            XCTAssertTrue((260...305).contains(normal))
            let largeText = KeyboardLayoutMetrics.contentHeight(width: width, landscape: false, accessibility: true)
            XCTAssertGreaterThan(largeText, normal)
            XCTAssertLessThanOrEqual(largeText, 330)
        }
        for width in [CGFloat(568), 667, 812, 874, 932] {
            let landscape = KeyboardLayoutMetrics.contentHeight(width: width, landscape: true, accessibility: false)
            XCTAssertTrue((190...230).contains(landscape))
        }
    }
    func testMissingGroupStillAllowsHostStorageButRejectsExtension() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("HostPrivate")
        let group = root.appendingPathComponent("Group")
        let fallback = try StorageLocation.resolve(shared: nil, local: local, isExtension: false)
        XCTAssertEqual(fallback.url, local)
        XCTAssertFalse(fallback.isShared)
        let first = try SharedStore(directory: fallback.url)
        try first.updatePreferences { $0.model = "saved-in-host"; $0.history = true }
        var task = WorkTask(tool: Tool.defaults[0], source: "local source")
        task.append(Answer(text: "local result"), instruction: "test")
        try first.save(task)
        let reopened = try SharedStore(directory: fallback.url)
        XCTAssertEqual(try reopened.preferences().model, "saved-in-host")
        XCTAssertEqual(try reopened.history().first?.answer?.text, "local result")
        XCTAssertThrowsError(try StorageLocation.resolve(shared: nil, local: local, isExtension: true))
        XCTAssertThrowsError(try StorageLocation.resolve(shared: nil, local: nil, isExtension: false))
        let host = try StorageLocation.resolve(shared: group, local: local, isExtension: false)
        let keyboard = try StorageLocation.resolve(shared: group, local: nil, isExtension: true)
        XCTAssertEqual(host, keyboard)
        XCTAssertTrue(host.isShared)
        XCTAssertEqual(host.url, group)
        // Location resolution must not create a fake, isolated extension container.
        XCTAssertFalse(FileManager.default.fileExists(atPath: group.path))
    }
    func testKeyInputPreservesValueAndRejectsInvalidPaste() throws {
        XCTAssertEqual(try APIKeyInput.normalize("  sample-credential-value\n"), "sample-credential-value")
        for input in ["", " \n", "two words", "a\nb", "a\0b", String(repeating: "x", count: 8193)] {
            XCTAssertThrowsError(try APIKeyInput.normalize(input))
        }
    }
    func testCredentialIsBlockedInEveryPayloadField() throws {
        let secret = "sample-secret-for-tests"
        try CredentialPayloadGuard.validate(["model": "model", "input": "ordinary text", "store": false], key: secret)
        let payloads: [[String: Any]] = [
            ["input": "prefix " + secret], ["instructions": secret], ["model": secret],
            ["tools": [["nested": secret]]], [secret: "value"]
        ]
        for payload in payloads {
            XCTAssertThrowsError(try CredentialPayloadGuard.validate(payload, key: secret)) { error in
                XCTAssertFalse(error.localizedDescription.contains(secret))
            }
        }
        XCTAssertThrowsError(try CredentialPayloadGuard.validate(["input": "normal"], key: ""))
    }
    func testArithmetic() throws {
        XCTAssertEqual(try Calculator.evaluate("(2+3)*4-6/2"), 17)
        XCTAssertEqual(try Calculator.evaluate("200*(1+10%)"), 220, accuracy: 0.00001)
        XCTAssertEqual(try Calculator.evaluate("-(-2)+.5"), 2.5)
        for invalid in ["", "1/0", "(1+2", "2abc", "1..2", "1**2", "nan"] { XCTAssertThrowsError(try Calculator.evaluate(invalid)) }
        XCTAssertEqual(try Calculator.convert(1, from: "in", to: "cm"), 2.54, accuracy: 0.00001)
        XCTAssertEqual(try Calculator.convert(0, from: "°C", to: "°F"), 32)
        XCTAssertThrowsError(try Calculator.convert(1, from: "kg", to: "cm"))
    }
    func testResponsesMultipleOutputsAndSources() throws {
        let json = #"{"status":"completed","output":[{"type":"web_search_call","status":"completed"},{"type":"message","content":[{"type":"output_text","text":"第一段","annotations":[{"type":"url_citation","title":"來源","url":"https://example.com"},{"type":"url_citation","url":"javascript:alert(1)"}]}]},{"type":"message","content":[{"type":"output_text","text":"第二段"}]}],"usage":{"input_tokens":12,"output_tokens":8}}"#
        let answer = try AIClient.parse(Data(json.utf8))
        XCTAssertEqual(answer.text, "第一段\n第二段"); XCTAssertTrue(answer.searched)
        XCTAssertEqual(answer.citations.count, 1); XCTAssertEqual(answer.inputTokens, 12)
    }
    func testStructuredAndFallback() throws {
        func response(_ text: String) throws -> Data { try JSONSerialization.data(withJSONObject: ["output": [["content": [["text": text]]]]]) }
        let answer = try AIClient.parse(response(#"{"natural":"好啊，來一場。","literal":"我向下","context":"遊戲邀約","alternatives":["可以啊"]}"#))
        XCTAssertEqual(answer.text, "好啊，來一場。"); XCTAssertEqual(answer.details["context"], "遊戲邀約")
        XCTAssertEqual(try AIClient.parse(response("## 自然譯文\n無法解析 JSON 仍保留全文")).text, "## 自然譯文\n無法解析 JSON 仍保留全文")
        XCTAssertThrowsError(try AIClient.parse(Data(#"{"status":"incomplete","output":[]}"#.utf8)))
        XCTAssertThrowsError(try AIClient.parse(Data(#"{"output":[{"content":[{"refusal":"拒絕"}]}]}"#.utf8)))
    }
    func testVersionsAndRetention() throws {
        var task = WorkTask(tool: Tool.defaults[0], source: "原文")
        task.append(Answer(text: "第一版"), instruction: "翻譯")
        task.append(Answer(text: "第二版"), instruction: "簡短")
        task.selected = 0; XCTAssertEqual(task.answer?.text, "第一版")
        task.append(Answer(text: "分支第三版"), instruction: "更正式")
        XCTAssertEqual(task.revisions.count, 3); XCTAssertEqual(task.selected, 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try SharedStore(directory: directory); let b = try SharedStore(directory: directory)
        try a.save(task); XCTAssertTrue(try b.history().isEmpty)
        try a.updatePreferences { $0.history = true; $0.tools[0].enabled = false }
        try b.updatePreferences { $0.model = "manual-model" }
        XCTAssertFalse(try a.preferences().tools[0].enabled)
        try a.save(task); XCTAssertEqual(try b.history().count, 1)
        task.date = Date(timeIntervalSinceNow: -8 * 86400); try a.save(task)
        XCTAssertTrue(try b.history().isEmpty)
        try b.updatePreferences { $0.history = false }; XCTAssertTrue(try a.history().isEmpty)
    }
    func testErrorCategories() {
        for code in [400,401,403,404,429,500,502,503] {
            XCTAssertTrue(AIClient.apiError(code, data: Data()).localizedDescription.contains("HTTP \(code)"))
        }
    }
    func testRealRequestShapeThroughMockTransport() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = AIClient(session: session)
        let answer = try await client.run(tool: Tool.defaults[1], source: "文字", instruction: "自然", preferences: Preferences(), key: "unit-test-placeholder")
        XCTAssertEqual(answer.text, "傳輸測試回應")
        let models = try await client.models(key: "unit-test-placeholder")
        XCTAssertEqual(models, ["available-model"])
        do { _ = try await client.models(key: "unauthorized"); XCTFail("Expected 401") }
        catch { XCTAssertTrue(error.localizedDescription.contains("401")) }
    }
}
final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let unauthorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer unauthorized"
        if request.url!.path.hasSuffix("responses") {
            XCTAssertEqual(request.httpMethod, "POST")
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096); var collected = Data()
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; collected.append(contentsOf: buffer.prefix(n)) }
                data = collected
            }
            let body = (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any]
            XCTAssertEqual(body?["store"] as? Bool, false)
            XCTAssertEqual(body?["model"] as? String, "gpt-6.1-terra")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: unauthorized ? 401 : 200, httpVersion: nil, headerFields: nil)!
        let payload = unauthorized ? #"{"error":{"code":"invalid_api_key"}}"# : request.url!.path.hasSuffix("models") ? #"{"data":[{"id":"available-model"}]}"# : #"{"status":"completed","output":[{"content":[{"text":"傳輸測試回應"}]}]}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
