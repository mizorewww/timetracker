import Foundation

nonisolated enum LiveActivityRecovery: Equatable, Sendable {
    case none
    case openSettings
    case retryWhenForeground
    case retry
}

nonisolated enum LiveActivityFailure: Equatable, Sendable {
    case unsupported
    case denied
    case backgroundStart
    case capacity
    case configuration
    case payloadTooLarge
    case removed
    case system

    var recovery: LiveActivityRecovery {
        switch self {
        case .denied:
            .openSettings
        case .backgroundStart:
            .retryWhenForeground
        case .capacity, .removed, .system:
            .retry
        case .unsupported, .configuration, .payloadTooLarge:
            .none
        }
    }
}

nonisolated enum LiveActivityStatus: Equatable, Sendable {
    case ready
    case synchronizing
    case active
    case unavailable(LiveActivityFailure)
}
