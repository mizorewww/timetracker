import Foundation
import OpenAI

/// Sends one chat completion for the user's configured connection. Services
/// hold one of these so tests can answer without a network.
typealias LLMChatSender = @Sendable (ChatQuery, LLMRequestConfiguration) async throws -> ChatResult

/// The user-configured OpenAI-compatible endpoint, reached through MacPaw's
/// `OpenAI` client. Requests carry the API key, so the endpoint must be HTTPS
/// (plain HTTP only for loopback) and redirects are refused.
nonisolated enum LLMClient {
    /// Longest silence tolerated while waiting for the server.
    static let timeoutInterval: TimeInterval = 90
    /// Longest a whole request may take; reasoning models can think for
    /// minutes before answering one tool round.
    static let resourceTimeoutInterval: TimeInterval = 600

    static func isValidEndpoint(_ endpoint: String) -> Bool {
        configuration(endpoint: endpoint, apiKey: "") != nil
    }

    static func chat(
        _ query: ChatQuery,
        configuration: LLMRequestConfiguration
    ) async throws -> ChatResult {
        let client = try client(endpoint: configuration.endpoint, apiKey: configuration.apiKey)
        return try await mappingErrors { try await client.chats(query: query) }
    }

    static func modelIDs(endpoint: String, apiKey: String) async throws -> [String] {
        let client = try client(endpoint: endpoint, apiKey: apiKey)
        let result = try await mappingErrors { try await client.models() }
        return AppPreferenceValueSanitizer.llmModelIDs(result.data.map(\.id))
    }

    private static func client(endpoint: String, apiKey: String) throws -> OpenAI {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw LLMClientError.missingEndpoint
        }
        guard trimmedAPIKey.isEmpty == false else { throw LLMClientError.missingAPIKey }
        guard let configuration = configuration(endpoint: endpoint, apiKey: trimmedAPIKey) else {
            throw LLMClientError.invalidEndpoint
        }
        return OpenAI(configuration: configuration, session: session)
    }

    /// Accepts a base URL with or without a trailing `/models` or
    /// `/chat/completions`, since users paste either.
    static func configuration(endpoint: String, apiKey: String) -> OpenAI.Configuration? {
        guard let components = URLComponents(
            string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased(),
            host.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            scheme == "https" || (scheme == "http" && loopbackHosts.contains(host))
        else {
            return nil
        }

        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        for suffix in ["/chat/completions", "/models"] where basePath.hasSuffix(suffix) {
            basePath.removeLast(suffix.count)
        }
        return OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: components.port ?? (scheme == "https" ? 443 : 80),
            scheme: scheme,
            basePath: basePath,
            timeoutInterval: timeoutInterval,
            parsingOptions: .relaxed
        )
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// The request timeout only covers idle gaps; the resource timeout caps a
    /// server that keeps the connection open without finishing.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = resourceTimeoutInterval
        return URLSession(configuration: configuration, delegate: RedirectRefusingDelegate(), delegateQueue: nil)
    }()

    private static func mappingErrors<Result>(
        _ operation: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation()
        } catch is DecodingError {
            throw LLMClientError.invalidResponse
        } catch let error as URLError where error.code == .timedOut {
            throw LLMClientError.timeout
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }
}

/// A redirect could forward the API key to another origin; providers do not
/// redirect API calls, so none is followed.
private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension LLMReasoningEffort {
    /// `automatic` omits `reasoning_effort`, which models without reasoning
    /// controls reject. `max` is sent verbatim for endpoints that accept a
    /// level above `high`; Settings warns that others may reject it.
    nonisolated var chatQueryValue: ChatQuery.ReasoningEffort? {
        switch self {
        case .automatic: nil
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .max: .customValue("max")
        }
    }
}

enum LLMClientError: LocalizedError, Equatable {
    case missingEndpoint
    case invalidEndpoint
    case missingAPIKey
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            AppStrings.localized("settings.llm.error.missingEndpoint")
        case .invalidEndpoint:
            AppStrings.localized("settings.llm.error.invalidEndpoint")
        case .missingAPIKey:
            AppStrings.localized("settings.llm.error.missingAPIKey")
        case .timeout:
            AppStrings.localized("settings.llm.error.timeout")
        case .invalidResponse:
            AppStrings.localized("settings.llm.error.invalidResponse")
        }
    }
}
