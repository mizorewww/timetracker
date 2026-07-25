import CryptoKit
import Foundation

enum ExternalCommandKeyError: LocalizedError, Equatable {
    case invalidOrigin

    var errorDescription: String? {
        "An external command key must include a non-empty, single-line origin."
    }
}

/// A caller-owned identity which must remain unchanged when that caller retries
/// one capture. It is never inferred from user text, time, or persistence IDs.
struct ExternalCommandKey: Equatable, Hashable, Sendable {
    let origin: String
    let id: UUID

    init(origin: String, id: UUID) throws {
        let normalizedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedOrigin.isEmpty,
              normalizedOrigin.utf8.count <= 128,
              !normalizedOrigin.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ExternalCommandKeyError.invalidOrigin
        }
        self.origin = normalizedOrigin
        self.id = id
    }

    var storageValue: String {
        "\(origin)\u{1F}\(id.uuidString.lowercased())"
    }
}

struct InboxCaptureCommand: Equatable, Sendable {
    let title: String
    let externalCommandKey: ExternalCommandKey?

    init(title: String, externalCommandKey: ExternalCommandKey? = nil) {
        self.title = title
        self.externalCommandKey = externalCommandKey
    }

    func payloadFingerprint() throws -> String {
        let canonicalTitle = try InboxPersistencePolicy.prepareItem(
            title: title,
            notes: nil,
            suggestionReason: nil
        ).title
        let digest = SHA256.hash(data: Data("inbox-capture-v1\u{0}\(canonicalTitle)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
