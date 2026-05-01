import Foundation

enum LLMModelServiceError: LocalizedError, Equatable {
    case missingEndpoint
    case invalidEndpoint
    case missingAPIKey
    case responseStatus(Int)
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
        case .invalidResponse:
            return AppStrings.localized("settings.llm.error.invalidResponse")
        }
    }
}

struct LLMModelService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await URLSession.shared.data(for: request)
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
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
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
}

struct LLMModelListResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]

    var modelIDs: [String] {
        Array(Set(data.map(\.id).filter { !$0.isEmpty })).sorted()
    }
}
