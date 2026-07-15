import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMResponseTransportTests {
    @Test
    func productionSessionIsEphemeralAndResourceBounded() {
        let configuration = LLMSecureHTTPTransport.productionConfiguration()

        #expect(LLMSecureHTTPTransport.maximumResponseByteCount == 2 * 1_024 * 1_024)
        #expect(configuration.timeoutIntervalForResource == 60)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieStorage == nil)
    }

    @Test
    func streamingTransportAcceptsTheExactByteLimit() async throws {
        let exchange = LLMTransportTestExchange(
            behavior: .complete(statusCode: 200, headers: [:], body: Data(repeating: 0x41, count: 64))
        )
        let fixture = Self.fixture(exchange: exchange)
        defer { fixture.session.invalidateAndCancel() }

        let (data, response) = try await LLMSecureHTTPTransport.data(
            for: URLRequest(url: fixture.url),
            session: fixture.session,
            maximumResponseByteCount: 64
        )

        #expect(data == Data(repeating: 0x41, count: 64))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test
    func streamingTransportCancelsAtTheFirstByteBeyondTheLimit() async throws {
        let exchange = LLMTransportTestExchange(
            behavior: .complete(statusCode: 200, headers: [:], body: Data(repeating: 0x42, count: 65))
        )
        let fixture = Self.fixture(exchange: exchange)
        defer { fixture.session.invalidateAndCancel() }

        await Self.expectResponseTooLarge {
            _ = try await LLMSecureHTTPTransport.data(
                for: URLRequest(url: fixture.url),
                session: fixture.session,
                maximumResponseByteCount: 64
            )
        }
        #expect(await Self.eventually { exchange.wasStopped })
    }

    @Test
    func contentLengthPreflightRejectsOversizedDeclaredBody() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "65"]
            )
        )

        #expect(throws: LLMModelServiceError.responseTooLarge) {
            try LLMSecureHTTPTransport.validateResponseHeaders(
                response,
                maximumResponseByteCount: 64
            )
        }
    }

    @Test
    func nonSuccessStatusTakesPriorityOverDeclaredBodySize() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.test")!,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "999999999"]
            )
        )

        #expect(throws: LLMModelServiceError.responseStatus(429)) {
            try LLMSecureHTTPTransport.validateResponseHeaders(
                response,
                maximumResponseByteCount: 64
            )
        }
    }

    @Test
    func cancellationPropagatesWhileWaitingForResponseHeaders() async throws {
        let exchange = LLMTransportTestExchange(behavior: .pending)
        let fixture = Self.fixture(exchange: exchange)
        defer { fixture.session.invalidateAndCancel() }
        let transportTask = Task {
            try await LLMSecureHTTPTransport.data(
                for: URLRequest(url: fixture.url),
                session: fixture.session,
                maximumResponseByteCount: 64
            )
        }

        #expect(await Self.eventually { exchange.didStart })
        transportTask.cancel()
        await Self.expectCancellation(from: transportTask)
        #expect(await Self.eventually { exchange.wasStopped })
    }

    @Test
    func URLTimeoutBecomesTypedTransportTimeout() async throws {
        let exchange = LLMTransportTestExchange(behavior: .fail(.timedOut))
        let fixture = Self.fixture(exchange: exchange)
        defer { fixture.session.invalidateAndCancel() }

        do {
            _ = try await LLMSecureHTTPTransport.data(
                for: URLRequest(url: fixture.url),
                session: fixture.session,
                maximumResponseByteCount: 64
            )
            Issue.record("Expected typed timeout")
        } catch let error as LLMModelServiceError {
            #expect(error == .timeout)
        }
    }

    @Test
    func modelServiceDefendsAgainstOversizedInjectedTransportData() async throws {
        let service = LLMModelService(transport: Self.oversizedInjectedTransport)

        await Self.expectResponseTooLarge {
            _ = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")
        }
    }

    @Test
    func injectedTransportPreservesHTTPStatusPriorityOverBufferedBodyLimit() async throws {
        let service = LLMModelService { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.test")!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (Data(count: LLMSecureHTTPTransport.maximumResponseByteCount + 1), response)
        }

        do {
            _ = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")
            Issue.record("Expected HTTP status failure")
        } catch let error as LLMModelServiceError {
            #expect(error == .responseStatus(429))
        }
    }

    @Test
    func inboxServiceDefendsAgainstOversizedInjectedTransportData() async throws {
        let service = LLMInboxSuggestionService(transport: Self.oversizedInjectedTransport)
        let candidate = LLMTaskCandidate(
            id: UUID(),
            title: "Design",
            path: "Work / Design",
            iconName: "paintbrush",
            colorHex: "1677FF"
        )

        await Self.expectResponseTooLarge {
            _ = try await service.suggest(
                inboxTitle: "Polish spacing",
                candidates: [candidate],
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
    }

    @Test
    func checklistServiceDefendsAgainstOversizedInjectedTransportData() async throws {
        let service = LLMChecklistVisualSuggestionService(transport: Self.oversizedInjectedTransport)

        await Self.expectResponseTooLarge {
            _ = try await service.suggest(
                checklistTitle: "Polish spacing",
                taskTitle: "Design",
                taskPath: "Work / Design",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
    }

    @Test
    func responseLimitErrorsHaveLocalizedDescriptions() throws {
        let responseTooLarge = try #require(LLMModelServiceError.responseTooLarge.errorDescription)
        let timeout = try #require(LLMModelServiceError.timeout.errorDescription)

        #expect(!responseTooLarge.isEmpty)
        #expect(responseTooLarge != "settings.llm.error.responseTooLarge")
        #expect(!timeout.isEmpty)
        #expect(timeout != "settings.llm.error.timeout")
    }

    private static let oversizedInjectedTransport: LLMModelService.Transport = { request in
        let response = try #require(
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (Data(count: LLMSecureHTTPTransport.maximumResponseByteCount + 1), response)
    }

    private static func fixture(exchange: LLMTransportTestExchange) -> (url: URL, session: URLSession) {
        let url = URL(string: "https://llm-transport.test/\(UUID().uuidString)")!
        LLMTransportTestURLProtocol.registry.register(exchange, for: url)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LLMTransportTestURLProtocol.self]
        configuration.urlCache = nil
        return (url, URLSession(configuration: configuration))
    }

    private static func expectResponseTooLarge(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected oversized response to be rejected")
        } catch let error as LLMModelServiceError {
            #expect(error == .responseTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func expectCancellation(
        from task: Task<(Data, URLResponse), Error>
    ) async {
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    private static func eventually(
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

nonisolated private final class LLMTransportTestExchange: @unchecked Sendable {
    enum Behavior: Sendable {
        case complete(statusCode: Int, headers: [String: String], body: Data)
        case pending
        case fail(URLError.Code)
    }

    let behavior: Behavior
    private let lock = NSLock()
    private var started = false
    private var responseDelivered = false
    private var stopped = false

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    var didStart: Bool { lock.withLock { started } }
    var didDeliverResponse: Bool { lock.withLock { responseDelivered } }
    var wasStopped: Bool { lock.withLock { stopped } }

    func markStarted() {
        lock.withLock { started = true }
    }

    func markResponseDelivered() {
        lock.withLock { responseDelivered = true }
    }

    func markStopped() {
        lock.withLock { stopped = true }
    }
}

nonisolated private final class LLMTransportTestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var exchanges: [URL: LLMTransportTestExchange] = [:]

    func register(_ exchange: LLMTransportTestExchange, for url: URL) {
        lock.withLock { exchanges[url] = exchange }
    }

    func exchange(for url: URL) -> LLMTransportTestExchange? {
        lock.withLock { exchanges[url] }
    }
}

nonisolated private final class LLMTransportTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = LLMTransportTestRegistry()
    private var exchange: LLMTransportTestExchange?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let exchange = Self.registry.exchange(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        self.exchange = exchange
        exchange.markStarted()

        switch exchange.behavior {
        case let .complete(statusCode, headers, body):
            deliverResponse(statusCode: statusCode, headers: headers, exchange: exchange)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .pending:
            break
        case let .fail(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {
        exchange?.markStopped()
    }

    private func deliverResponse(
        statusCode: Int,
        headers: [String: String],
        exchange: LLMTransportTestExchange
    ) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        exchange.markResponseDelivered()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}
