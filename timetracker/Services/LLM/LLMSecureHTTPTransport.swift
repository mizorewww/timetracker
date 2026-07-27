import Foundation

nonisolated enum LLMSecureHTTPTransport {
    static let maximumResponseByteCount = 2 * 1024 * 1024
    static let resourceTimeoutInterval: TimeInterval = 60

    private static let productionSession = URLSession(configuration: productionConfiguration())

    static func productionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = resourceTimeoutInterval
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        return configuration
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(
            for: request,
            session: productionSession,
            maximumResponseByteCount: maximumResponseByteCount
        )
    }

    static func data(
        for request: URLRequest,
        session: URLSession,
        maximumResponseByteCount: Int
    ) async throws -> (Data, URLResponse) {
        precondition(maximumResponseByteCount > 0)

        do {
            let (bytes, response) = try await session.bytes(
                for: request,
                delegate: LLMRedirectPolicyDelegate()
            )
            let dataTask = bytes.task

            do {
                try validateResponseMetadata(
                    response,
                    maximumResponseByteCount: maximumResponseByteCount
                )
            } catch {
                dataTask.cancel()
                throw error
            }

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()

                var data = Data()
                if response.expectedContentLength > 0 {
                    data.reserveCapacity(Int(response.expectedContentLength))
                }

                for try await byte in bytes {
                    guard data.count < maximumResponseByteCount else {
                        dataTask.cancel()
                        throw LLMModelServiceError.responseTooLarge
                    }
                    data.append(byte)
                    if data.count.isMultiple(of: 16 * 1024) {
                        try Task.checkCancellation()
                    }
                }

                try Task.checkCancellation()
                try validateResponseStatus(response, data: data)
                return (data, response)
            } onCancel: {
                dataTask.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw LLMModelServiceError.timeout
        }
    }

    static func validateBufferedResponse(_ data: Data) throws {
        guard data.count <= maximumResponseByteCount else {
            throw LLMModelServiceError.responseTooLarge
        }
    }

    static func validateResponseHeaders(
        _ response: URLResponse,
        maximumResponseByteCount: Int
    ) throws {
        try validateResponseStatus(response, data: Data())
        try validateResponseMetadata(
            response,
            maximumResponseByteCount: maximumResponseByteCount
        )
    }

    private static func validateResponseMetadata(
        _ response: URLResponse,
        maximumResponseByteCount: Int
    ) throws {
        guard response is HTTPURLResponse else {
            throw LLMModelServiceError.invalidResponse
        }
        guard response.expectedContentLength <= Int64(maximumResponseByteCount) else {
            throw LLMModelServiceError.responseTooLarge
        }
    }

    private static func validateResponseStatus(
        _ response: URLResponse,
        data: Data
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMModelServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(
                httpResponse.statusCode,
                providerMessage: providerErrorMessage(from: data)
            )
        }
    }

    private static func providerErrorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct ProviderError: Decodable {
                let message: String?
                let code: String?
            }

            let error: ProviderError?
        }

        guard let error = try? JSONDecoder().decode(
            Envelope.self,
            from: data
        ).error else {
            return nil
        }
        let parts = [error.code, error.message]
            .compactMap { value in
                value?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { $0.isEmpty == false }
        guard parts.isEmpty == false else { return nil }
        return String(parts.joined(separator: ": ").prefix(2048))
    }
}

final class LLMRedirectPolicyDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let sourceURL = response.url,
              let destinationURL = request.url,
              LLMModelService.isSafeRedirect(from: sourceURL, to: destinationURL)
        else {
            completionHandler(nil)
            return
        }

        var redirectedRequest = request
        if redirectedRequest.value(forHTTPHeaderField: "Authorization") == nil,
           let authorization = task.currentRequest?.value(forHTTPHeaderField: "Authorization") ??
           task.originalRequest?.value(forHTTPHeaderField: "Authorization")
        {
            redirectedRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirectedRequest)
    }
}
