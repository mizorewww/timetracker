import Foundation
import Security

protocol LLMCredentialStoring {
    func readAPIKey() throws -> String?
    func writeAPIKey(_ apiKey: String) throws
}

#if DEBUG
final class UITestLLMCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.apiKey = normalized.isEmpty ? nil : normalized
    }
}
#endif

struct KeychainLLMCredentialStore: LLMCredentialStoring {
    static let credentialAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    private let service: String
    private let account: String

    init(
        service: String = "me.mezorewww.timetracker.credentials",
        account: String = "llm-api-key"
    ) {
        self.service = service
        self.account = account
    }

    func readAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialError(status: status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainCredentialError.invalidData
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainCredentialError(status: status)
            }
            return
        }

        let data = Data(normalized.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [
                kSecValueData as String: data,
                kSecAttrAccessible as String: Self.credentialAccessibility,
            ] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainCredentialError(status: updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = Self.credentialAccessibility
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainCredentialError(status: addStatus)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

enum KeychainCredentialError: LocalizedError {
    case invalidData
    case operationFailed(OSStatus)

    init(status: OSStatus) {
        self = .operationFailed(status)
    }

    var errorDescription: String? {
        switch self {
        case .invalidData:
            return String(localized: "error.keychain.invalidData")
        case let .operationFailed(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ??
                String(localized: "error.keychain.unknownFailure")
            return String(
                format: String(localized: "error.keychain.operationFailedFormat"),
                Int64(status),
                message
            )
        }
    }
}
