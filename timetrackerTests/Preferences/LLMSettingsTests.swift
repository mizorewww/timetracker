import Foundation
import Testing
@testable import timetracker

struct LLMSettingsTests {
    @Test
    func modelListRequestUsesOpenAICompatibleModelsEndpoint() throws {
        let service = LLMModelService()
        let request = try service.modelListRequest(
            endpoint: " https://api.openai.com/v1 ",
            apiKey: " test-key "
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func modelListRequestDoesNotAppendModelsTwice() throws {
        let url = try #require(LLMModelService.modelsURL(endpoint: "https://example.test/v1/models"))
        #expect(url.absoluteString == "https://example.test/v1/models")
    }

    @Test
    func fetchModelsDecodesUniqueSortedModelIDs() async throws {
        let service = LLMModelService { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/models")
            let data = Data("""
            {
              "object": "list",
              "data": [
                { "id": "gpt-z", "object": "model" },
                { "id": "gpt-a", "object": "model" },
                { "id": "gpt-a", "object": "model" }
              ]
            }
            """.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        let models = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")

        #expect(models == ["gpt-a", "gpt-z"])
    }

    @Test
    func fetchModelsReportsHTTPFailures() async throws {
        let service = LLMModelService { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(), response)
        }

        do {
            _ = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")
            Issue.record("Expected unauthorized response to throw")
        } catch let error as LLMModelServiceError {
            #expect(error == .responseStatus(401))
        }
    }
}
