import Foundation
import SwiftData

nonisolated enum PersistentHistoryProjectionLane:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Sendable
{
    case syncSnapshot = "sync-snapshot"
    case widget
    case watch
    case liveActivity = "live-activity"
}

nonisolated enum PersistentHistoryLaneCursorRecoveryReason:
    Equatable,
    Sendable
{
    case malformed
    case oversized
    case unsupportedFormatVersion(Int)
    case laneMismatch
    case storeIdentifierMismatch
    case resetEpochMismatch
    case interruptedFullReconciliation
}

nonisolated enum PersistentHistoryLaneCursorLoadResult:
    Equatable,
    Sendable
{
    case missing
    case requiresFullReconciliation(
        PersistentHistoryLaneCursorRecoveryReason
    )
    case ready(DefaultHistoryToken?)
}

nonisolated enum PersistentHistoryLaneCursorAdvanceResult:
    Equatable,
    Sendable
{
    case advanced
    case alreadyAcknowledged
    case retryRequired
}

nonisolated enum PersistentHistoryLaneCursorStoreError:
    Error,
    Equatable,
    Sendable
{
    case encodedCursorExceedsMaximumByteCount(
        actualByteCount: Int,
        maximumByteCount: Int
    )
    case resetEpochOverflow
}

nonisolated struct PersistentHistoryLaneCursorFullReconciliationAttempt:
    Codable,
    Equatable,
    Sendable
{
    let id: UUID
    let lane: PersistentHistoryProjectionLane
    let storeIdentifier: String
    let resetEpoch: UInt64
}

/// A reset generation that survives SQLite/cursor cleanup.
///
/// A coordinator captures this value when it is registered. Cloud recovery
/// advances it before deleting any store files, invalidating work that began
/// against the previous physical store even if that work resumes later.
nonisolated struct PersistentHistoryProjectionResetFence:
    @unchecked Sendable
{
    private struct Envelope: Codable {
        let formatVersion: Int
        let epoch: UInt64
    }

    private static let formatVersion = 1
    private static let maximumByteCount = 4 * 1024

    private let scope: TimerStoreScope
    private let localFile: DurableLocalFile

    init(
        scope: TimerStoreScope,
        localFile: DurableLocalFile = DurableLocalFile()
    ) {
        self.scope = scope
        self.localFile = localFile
    }

    func currentEpoch() throws -> UInt64 {
        guard let paths = durablePaths else { return 0 }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            try currentEpochWithExclusiveAccess(paths: paths)
        }
    }

    @discardableResult
    func advanceForStoreReset() throws -> UInt64 {
        guard let paths = durablePaths else { return 0 }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            let current = try currentEpochWithExclusiveAccess(paths: paths)
            guard current < UInt64.max else {
                throw PersistentHistoryLaneCursorStoreError
                    .resetEpochOverflow
            }
            let next = current + 1
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(
                Envelope(
                    formatVersion: Self.formatVersion,
                    epoch: next
                )
            )
            try localFile.write(
                data,
                to: paths.location,
                durableRootURL: paths.durableRoot,
                excludeFromBackup: true
            )
            return next
        }
    }

    fileprivate func currentEpochWithExclusiveAccess(
        paths: (location: URL, durableRoot: URL)
    ) throws -> UInt64 {
        guard let data = try localFile.read(
            upTo: Self.maximumByteCount,
            from: paths.location,
            durableRootURL: paths.durableRoot
        ) else {
            return 0
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.formatVersion == Self.formatVersion else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription:
                    "Unsupported persistent-history reset epoch format."
                )
            )
        }
        return envelope.epoch
    }

    fileprivate var durablePaths: (
        location: URL,
        durableRoot: URL
    )? {
        guard let storeURL = scope.persistentStoreURL else { return nil }
        let durableRoot = storeURL.deletingLastPathComponent()
        return (
            location: durableRoot.appendingPathComponent(
                "."
                    + storeURL.lastPathComponent
                    + ".post-commit-history.reset-epoch.v1.json"
            ),
            durableRoot: durableRoot
        )
    }
}

/// Persists one opaque SwiftData history token per projection lane.
///
/// Each lane owns a separate sidecar so a successful Widget publication can
/// advance independently from a failed Watch or Live Activity publication.
/// The store basename prefix deliberately makes Cloud recovery's physical-store
/// cleanup remove these cursors alongside the SQLite files.
nonisolated struct PersistentHistoryLaneCursorStore: @unchecked Sendable {
    private struct Envelope: Codable, Equatable {
        let formatVersion: Int
        let lane: PersistentHistoryProjectionLane
        let storeIdentifier: String
        let resetEpoch: UInt64
        let token: DefaultHistoryToken?
    }

    private static let formatVersion = 1
    private static let maximumCursorByteCount = 64 * 1024

    private let scope: TimerStoreScope
    private let storeIdentifier: String
    private let registeredResetEpoch: UInt64
    private let localFile: DurableLocalFile
    private let resetFence: PersistentHistoryProjectionResetFence

    init(
        scope: TimerStoreScope,
        storeIdentifier: String,
        registeredResetEpoch: UInt64,
        localFile: DurableLocalFile = DurableLocalFile()
    ) {
        self.scope = scope
        self.storeIdentifier = storeIdentifier
        self.registeredResetEpoch = registeredResetEpoch
        self.localFile = localFile
        resetFence = PersistentHistoryProjectionResetFence(
            scope: scope,
            localFile: localFile
        )
    }

    /// Registers a coordinator against the physical store generation that is
    /// current at creation time.
    ///
    /// Callers should prefer this factory over supplying an epoch directly.
    /// If Cloud recovery resets the store after registration, every subsequent
    /// cursor operation detects the stale epoch and refuses to acknowledge
    /// work from the replaced store.
    static func registeringCurrentEpoch(
        scope: TimerStoreScope,
        storeIdentifier: String,
        localFile: DurableLocalFile = DurableLocalFile()
    ) throws -> Self {
        let registeredResetEpoch =
            try PersistentHistoryProjectionResetFence(
                scope: scope,
                localFile: localFile
            ).currentEpoch()
        return Self(
            scope: scope,
            storeIdentifier: storeIdentifier,
            registeredResetEpoch: registeredResetEpoch,
            localFile: localFile
        )
    }

    func durableLocation(
        for lane: PersistentHistoryProjectionLane
    ) -> URL? {
        guard let storeURL = scope.persistentStoreURL else { return nil }
        return storeURL.deletingLastPathComponent().appendingPathComponent(
            storeURL.lastPathComponent
                + ".post-commit-history."
                + lane.rawValue
                + ".cursor.v1.json"
        )
    }

    func load(
        for lane: PersistentHistoryProjectionLane
    ) throws -> PersistentHistoryLaneCursorLoadResult {
        guard let paths = durablePaths(for: lane) else {
            return .missing
        }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            guard try resetEpochMatchesWithExclusiveAccess() else {
                return .requiresFullReconciliation(.resetEpochMismatch)
            }
            if let attemptLocation = durableAttemptLocation(for: lane),
               try loadAttemptWithExclusiveAccess(
                   from: attemptLocation,
                   durableRoot: paths.durableRoot
               ) != nil
            {
                return .requiresFullReconciliation(
                    .interruptedFullReconciliation
                )
            }
            return try loadWithExclusiveAccess(
                for: lane,
                location: paths.location,
                durableRoot: paths.durableRoot
            )
        }
    }

    func beginFullReconciliation(
        for lane: PersistentHistoryProjectionLane
    ) throws -> PersistentHistoryLaneCursorFullReconciliationAttempt? {
        guard let paths = durablePaths(for: lane),
              let attemptLocation = durableAttemptLocation(for: lane)
        else {
            return nil
        }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            guard try resetEpochMatchesWithExclusiveAccess() else {
                return nil
            }
            let attempt =
                PersistentHistoryLaneCursorFullReconciliationAttempt(
                    id: UUID(),
                    lane: lane,
                    storeIdentifier: storeIdentifier,
                    resetEpoch: registeredResetEpoch
                )
            try writeCodableWithExclusiveAccess(
                attempt,
                to: attemptLocation,
                durableRoot: paths.durableRoot
            )
            return attempt
        }
    }

    @discardableResult
    func establishAfterFullReconciliation(
        _ token: DefaultHistoryToken?,
        for lane: PersistentHistoryProjectionLane,
        attempt: PersistentHistoryLaneCursorFullReconciliationAttempt
    ) throws -> Bool {
        guard let paths = durablePaths(for: lane),
              let attemptLocation = durableAttemptLocation(for: lane)
        else {
            return false
        }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            guard try resetEpochMatchesWithExclusiveAccess(),
                  attempt.lane == lane,
                  attempt.storeIdentifier == storeIdentifier,
                  attempt.resetEpoch == registeredResetEpoch,
                  try loadAttemptWithExclusiveAccess(
                      from: attemptLocation,
                      durableRoot: paths.durableRoot
                  ) == attempt
            else {
                return false
            }

            try writeWithExclusiveAccess(
                token: token,
                lane: lane,
                location: paths.location,
                durableRoot: paths.durableRoot
            )
            try localFile.removeIfPresent(
                at: attemptLocation,
                durableRootURL: paths.durableRoot
            )
            return true
        }
    }

    /// Advances only when the on-disk cursor still equals `expectedToken`.
    ///
    /// This compare-and-swap prevents a slower process from acknowledging past
    /// a generation that another process has already replaced or rebased.
    func advanceIncrementally(
        to candidateToken: DefaultHistoryToken,
        after expectedToken: DefaultHistoryToken?,
        for lane: PersistentHistoryProjectionLane
    ) throws -> PersistentHistoryLaneCursorAdvanceResult {
        guard let paths = durablePaths(for: lane) else {
            return .retryRequired
        }
        return try localFile.withExclusiveAccess(
            through: paths.durableRoot
        ) {
            guard try resetEpochMatchesWithExclusiveAccess() else {
                return .retryRequired
            }
            if let attemptLocation = durableAttemptLocation(for: lane),
               try loadAttemptWithExclusiveAccess(
                   from: attemptLocation,
                   durableRoot: paths.durableRoot
               ) != nil
            {
                return .retryRequired
            }
            guard case let .ready(currentToken) =
                try loadWithExclusiveAccess(
                    for: lane,
                    location: paths.location,
                    durableRoot: paths.durableRoot
                )
            else {
                return .retryRequired
            }
            if Self.isAtLeast(currentToken, candidateToken) {
                return .alreadyAcknowledged
            }
            guard currentToken == expectedToken,
                  (expectedToken.map { candidateToken > $0 } ?? true)
            else {
                return .retryRequired
            }
            try writeWithExclusiveAccess(
                token: candidateToken,
                lane: lane,
                location: paths.location,
                durableRoot: paths.durableRoot
            )
            return .advanced
        }
    }

    private func durablePaths(
        for lane: PersistentHistoryProjectionLane
    ) -> (location: URL, durableRoot: URL)? {
        guard let location = durableLocation(for: lane) else { return nil }
        return (
            location: location,
            durableRoot: location.deletingLastPathComponent()
        )
    }

    private func durableAttemptLocation(
        for lane: PersistentHistoryProjectionLane
    ) -> URL? {
        guard let storeURL = scope.persistentStoreURL else { return nil }
        return storeURL.deletingLastPathComponent().appendingPathComponent(
            storeURL.lastPathComponent
                + ".post-commit-history."
                + lane.rawValue
                + ".attempt.v1.json"
        )
    }

    private func resetEpochMatchesWithExclusiveAccess() throws -> Bool {
        guard let paths = resetFence.durablePaths else {
            return registeredResetEpoch == 0
        }
        return try resetFence.currentEpochWithExclusiveAccess(paths: paths)
            == registeredResetEpoch
    }

    private func loadWithExclusiveAccess(
        for lane: PersistentHistoryProjectionLane,
        location: URL,
        durableRoot: URL
    ) throws -> PersistentHistoryLaneCursorLoadResult {
        let data: Data
        do {
            guard let loaded = try localFile.read(
                upTo: Self.maximumCursorByteCount,
                from: location,
                durableRootURL: durableRoot
            ) else {
                return .missing
            }
            data = loaded
        } catch is DurableLocalFileReadError {
            try quarantineWithExclusiveAccess(
                lane: lane,
                location: location,
                durableRoot: durableRoot
            )
            return .requiresFullReconciliation(.oversized)
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            try quarantineWithExclusiveAccess(
                lane: lane,
                location: location,
                durableRoot: durableRoot
            )
            return .requiresFullReconciliation(.malformed)
        }

        guard envelope.formatVersion == Self.formatVersion else {
            try quarantineWithExclusiveAccess(
                lane: lane,
                location: location,
                durableRoot: durableRoot
            )
            return .requiresFullReconciliation(
                .unsupportedFormatVersion(envelope.formatVersion)
            )
        }
        guard envelope.lane == lane else {
            try quarantineWithExclusiveAccess(
                lane: lane,
                location: location,
                durableRoot: durableRoot
            )
            return .requiresFullReconciliation(.laneMismatch)
        }
        guard envelope.storeIdentifier == storeIdentifier else {
            // A cursor from a replaced physical store is not corrupt. Preserve
            // it until a successful full reconciliation publishes the new
            // store identity and token together.
            return .requiresFullReconciliation(.storeIdentifierMismatch)
        }
        guard envelope.resetEpoch == registeredResetEpoch else {
            return .requiresFullReconciliation(.resetEpochMismatch)
        }
        return .ready(envelope.token)
    }

    private func writeWithExclusiveAccess(
        token: DefaultHistoryToken?,
        lane: PersistentHistoryProjectionLane,
        location: URL,
        durableRoot: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(
            Envelope(
                formatVersion: Self.formatVersion,
                lane: lane,
                storeIdentifier: storeIdentifier,
                resetEpoch: registeredResetEpoch,
                token: token
            )
        )
        guard data.count <= Self.maximumCursorByteCount else {
            throw PersistentHistoryLaneCursorStoreError
                .encodedCursorExceedsMaximumByteCount(
                    actualByteCount: data.count,
                    maximumByteCount: Self.maximumCursorByteCount
                )
        }
        try localFile.write(
            data,
            to: location,
            durableRootURL: durableRoot,
            excludeFromBackup: true
        )
    }

    private func loadAttemptWithExclusiveAccess(
        from location: URL,
        durableRoot: URL
    ) throws -> PersistentHistoryLaneCursorFullReconciliationAttempt? {
        let data: Data
        do {
            guard let loaded = try localFile.read(
                upTo: Self.maximumCursorByteCount,
                from: location,
                durableRootURL: durableRoot
            ) else {
                return nil
            }
            data = loaded
        } catch is DurableLocalFileReadError {
            _ = try localFile.quarantineIfPresent(
                at: location,
                prefix: "HistoryCursorAttempt.corrupt-",
                durableRootURL: durableRoot
            )
            return nil
        }
        do {
            return try JSONDecoder().decode(
                PersistentHistoryLaneCursorFullReconciliationAttempt.self,
                from: data
            )
        } catch {
            _ = try localFile.quarantineIfPresent(
                at: location,
                prefix: "HistoryCursorAttempt.corrupt-",
                durableRootURL: durableRoot
            )
            return nil
        }
    }

    private func writeCodableWithExclusiveAccess<Value: Encodable>(
        _ value: Value,
        to location: URL,
        durableRoot: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= Self.maximumCursorByteCount else {
            throw PersistentHistoryLaneCursorStoreError
                .encodedCursorExceedsMaximumByteCount(
                    actualByteCount: data.count,
                    maximumByteCount: Self.maximumCursorByteCount
                )
        }
        try localFile.write(
            data,
            to: location,
            durableRootURL: durableRoot,
            excludeFromBackup: true
        )
    }

    private static func isAtLeast(
        _ acknowledged: DefaultHistoryToken?,
        _ candidate: DefaultHistoryToken?
    ) -> Bool {
        switch (acknowledged, candidate) {
        case (_, nil):
            true
        case (nil, .some):
            false
        case let (.some(acknowledged), .some(candidate)):
            acknowledged >= candidate
        }
    }

    private func quarantineWithExclusiveAccess(
        lane: PersistentHistoryProjectionLane,
        location: URL,
        durableRoot: URL
    ) throws {
        _ = try localFile.quarantineIfPresent(
            at: location,
            prefix: "HistoryCursor-\(lane.rawValue).corrupt-",
            durableRootURL: durableRoot
        )
    }
}
