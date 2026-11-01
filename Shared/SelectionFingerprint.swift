import Foundation
import CryptoKit

/// Store only hashes of host context, never unrelated host text or credentials.
struct SelectionFingerprint {
    private let document: UUID
    private let selected: Data
    private let before: Data?
    private let after: Data?
    init(document: UUID, selection: String, before: String?, after: String?) {
        self.document = document; selected = Self.digest(selection)
        self.before = before.map(Self.digest); self.after = after.map(Self.digest)
    }
    func matches(document: UUID, selection: String?, before: String?, after: String?) -> Bool {
        guard let selection, !selection.isEmpty else { return false }
        return self.document == document && selected == Self.digest(selection) && self.before == before.map(Self.digest) && self.after == after.map(Self.digest)
    }
    private static func digest(_ value: String) -> Data { Data(SHA256.hash(data: Data(value.utf8))) }
}
