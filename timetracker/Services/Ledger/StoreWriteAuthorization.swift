/// Selects the write-safety authority used by a store facade.
///
/// Production stores always use `applicationState`. Unit tests opt into the
/// isolated harness explicitly so a developer's real fallback/recovery state
/// cannot make an in-memory fixture read-only or be changed by the test.
nonisolated enum StoreWriteAuthorization: Sendable {
    case applicationState
    case isolatedTestHarness

    var usesApplicationState: Bool {
        if case .applicationState = self {
            return true
        }
        return false
    }

    @MainActor
    func requireUserWritesAllowed() throws {
        switch self {
        case .applicationState:
            try AppCloudSync.requireUserWritesAllowed()
        case .isolatedTestHarness:
            return
        }
    }
}
