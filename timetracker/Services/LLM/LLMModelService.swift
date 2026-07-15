import Darwin
import Foundation

enum LLMModelServiceError: LocalizedError, Equatable {
    case missingEndpoint
    case invalidEndpoint
    case missingAPIKey
    case responseStatus(Int)
    case responseTooLarge
    case timeout
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return AppStrings.localized("settings.llm.error.missingEndpoint")
        case .invalidEndpoint:
            return AppStrings.localized("settings.llm.error.invalidEndpoint")
        case .missingAPIKey:
            return AppStrings.localized("settings.llm.error.missingAPIKey")
        case let .responseStatus(status):
            return String(format: AppStrings.localized("settings.llm.error.responseStatus"), status)
        case .responseTooLarge:
            return AppStrings.localized("settings.llm.error.responseTooLarge")
        case .timeout:
            return AppStrings.localized("settings.llm.error.timeout")
        case .invalidResponse:
            return AppStrings.localized("settings.llm.error.invalidResponse")
        }
    }
}

struct LLMModelService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await LLMSecureHTTPTransport.data(for: request)
    }

    func fetchModels(endpoint: String, apiKey: String) async throws -> [String] {
        let request = try modelListRequest(endpoint: endpoint, apiKey: apiKey)
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMModelServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }
        try LLMSecureHTTPTransport.validateBufferedResponse(data)

        let decoded = try JSONDecoder().decode(LLMModelListResponse.self, from: data)
        return decoded.modelIDs
    }

    func modelListRequest(endpoint: String, apiKey: String) throws -> URLRequest {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEndpoint.isEmpty else {
            throw LLMModelServiceError.missingEndpoint
        }
        guard !trimmedAPIKey.isEmpty else {
            throw LLMModelServiceError.missingAPIKey
        }
        guard let url = Self.modelsURL(endpoint: trimmedEndpoint) else {
            throw LLMModelServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func modelsURL(endpoint: String) -> URL? {
        guard var components = validatedEndpointComponents(endpoint) else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if !path.hasSuffix("/models") {
            path += "/models"
        }
        components.path = path
        return components.url
    }

    nonisolated static func validatedEndpointComponents(_ endpoint: String) -> URLComponents? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }

        guard scheme == "https" || (scheme == "http" && isLoopbackHost(host)) else {
            return nil
        }
        return components
    }

    nonisolated static func isSafeRedirect(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard let source = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
              let destination = validatedEndpointComponents(destinationURL.absoluteString),
              let sourceScheme = source.scheme?.lowercased(),
              let destinationScheme = destination.scheme?.lowercased(),
              let sourceHost = source.host?.lowercased(),
              let destinationHost = destination.host?.lowercased() else {
            return false
        }

        return sourceScheme == destinationScheme &&
            sourceHost == destinationHost &&
            effectivePort(for: source) == effectivePort(for: destination)
    }

    nonisolated private static func effectivePort(for components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    nonisolated private static func isLoopbackHost(_ host: String) -> Bool {
        let address = if host.hasPrefix("[") && host.hasSuffix("]") {
            String(host.dropFirst().dropLast())
        } else {
            host
        }

        if address == "localhost" || address.hasSuffix(".localhost") {
            return true
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, address, &ipv4) == 1 {
            return withUnsafeBytes(of: &ipv4) { bytes in
                bytes.first == 127
            }
        }

        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, address, &ipv6) == 1 {
            return withUnsafeBytes(of: &ipv6) { bytes in
                bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            }
        }

        return false
    }
}

struct LLMModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]

    var modelIDs: [String] {
        Array(Set(data.map {
            $0.id.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }
}
