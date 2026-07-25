import Foundation

extension LLMSecureHTTPTransport {
    /// Streaming generations (large plans with long chains of thought) can
    /// legitimately exceed the 60-second buffered-response budget, so the
    /// streaming session gets a wider total-transfer cap while keeping the
    /// same per-request idle timeout and every other transport invariant.
    static let streamingResourceTimeoutInterval: TimeInterval = 300

    private static let productionStreamingSession = URLSession(
        configuration: streamingConfiguration()
    )

    static func streamingConfiguration() -> URLSessionConfiguration {
        let configuration = productionConfiguration()
        configuration.timeoutIntervalForResource = streamingResourceTimeoutInterval
        return configuration
    }

    /// Reads an OpenAI-compatible `text/event-stream` body under the same
    /// security contract as `data(for:)`: identical header validation, byte
    /// ceiling, redirect policy, timeout mapping, and cancellation
    /// propagation — only the consumption differs (incremental SSE frames
    /// instead of one buffered body).
    static func streamEvents(
        for request: URLRequest
    ) -> AsyncThrowingStream<LLMGenerationStreamEvent, Error> {
        streamEvents(
            for: request,
            session: productionStreamingSession,
            maximumResponseByteCount: maximumResponseByteCount
        )
    }

    static func streamEvents(
        for request: URLRequest,
        session: URLSession,
        maximumResponseByteCount: Int
    ) -> AsyncThrowingStream<LLMGenerationStreamEvent, Error> {
        precondition(maximumResponseByteCount > 0)
        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let (bytes, response) = try await session.bytes(
                        for: request,
                        delegate: LLMRedirectPolicyDelegate()
                    )
                    let dataTask = bytes.task

                    do {
                        try validateResponseHeaders(
                            response,
                            maximumResponseByteCount: maximumResponseByteCount
                        )
                    } catch {
                        dataTask.cancel()
                        throw error
                    }

                    try await withTaskCancellationHandler {
                        var parser = LLMServerSentEventParser()
                        var receivedByteCount = 0
                        for try await byte in bytes {
                            guard receivedByteCount < maximumResponseByteCount else {
                                dataTask.cancel()
                                throw LLMModelServiceError.responseTooLarge
                            }
                            receivedByteCount += 1
                            for payload in parser.append(byte) {
                                if emit(payload, to: continuation) == .finished {
                                    continuation.finish()
                                    return
                                }
                            }
                            if receivedByteCount.isMultiple(of: 16 * 1024) {
                                try Task.checkCancellation()
                            }
                        }
                        try Task.checkCancellation()
                        for payload in parser.finish() {
                            _ = emit(payload, to: continuation)
                        }
                        continuation.finish()
                    } onCancel: {
                        dataTask.cancel()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: LLMModelServiceError.timeout)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private enum StreamEmission {
        case emitted
        case finished
    }

    private static func emit(
        _ payload: String,
        to continuation: AsyncThrowingStream<LLMGenerationStreamEvent, Error>.Continuation
    ) -> StreamEmission {
        if payload == "[DONE]" {
            return .finished
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(
                  OpenAIChatCompletionStreamChunk.self,
                  from: data
              )
        else {
            return .emitted
        }
        for choice in chunk.choices {
            if let reasoning = choice.delta?.reasoning_content, !reasoning.isEmpty {
                continuation.yield(.reasoningDelta(reasoning))
            }
            if let content = choice.delta?.content, !content.isEmpty {
                continuation.yield(.contentDelta(content))
            }
        }
        if let usage = chunk.usage {
            continuation.yield(.usage(usage))
        }
        return .emitted
    }
}
