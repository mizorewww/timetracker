import Foundation
import OSLog

nonisolated enum PerformanceSignpost {
    private static let signposter = OSSignposter(
        subsystem: AppIdentity.loggingSubsystem,
        category: "Performance"
    )

    nonisolated static func interval<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try operation()
    }

    nonisolated static func interval<T>(
        _ name: StaticString,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await operation()
    }
}
