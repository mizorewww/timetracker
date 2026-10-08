import Foundation

/// Shared chat-completion plumbing for the two LLM suggestion services (inbox
/// routing + checklist visual). The per-kind prompt, response contract and
/// payload sanitization stay in each service; only the request/response shape
/// lives here.
nonisolated enum LLMSuggestionChatSupport {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static func request(
        modelID: String,
        responseContract: String,
        configuration: LLMRequestConfiguration,
        promptJSON: () throws -> String
    ) throws -> URLRequest {
        let credentials = try configuration.validated(
            requestTooLarge: LLMInboxSuggestionServiceError.requestTooLarge
        )
        let promptJSON = try promptJSON()

        var request = URLRequest(url: credentials.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: modelID,
                messages: [
                    .init(
                        role: "system",
                        content: responseContract
                    ),
                    .init(
                        role: "user",
                        content: promptJSON
                    ),
                ],
                temperature: LLMChatRequestPolicy.temperature(
                    modelID: modelID,
                    fallback: LLMChatRequestPolicy.suggestionTemperature
                ),
                responseFormat: .init(type: "json_object"),
                thinking: LLMChatRequestPolicy.thinkingConfiguration(
                    modelID: modelID
                ),
                reasoningEffort: LLMChatRequestPolicy.reasoningEffort(
                    modelID: modelID,
                    selected: configuration.reasoningEffort
                )
            )
        )
        request.httpBody = body
        return request
    }

    static func contentData(
        for request: URLRequest,
        transport: Transport
    ) async throws -> Data {
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }
        try LLMSecureHTTPTransport.validateBufferedResponse(data)

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8)
        else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        return contentData
    }
}
