import CoreData
import Foundation
import SwiftData

nonisolated enum PersistentHistoryProjectionInvocationKind:
    Equatable,
    Sendable
{
    case fullReconciliation
    case incremental
    case forcedCurrentState
}

nonisolated struct PersistentHistoryProjectionInvocation:
    Equatable,
    Sendable
{
    let lane: PersistentHistoryProjectionLane
    let kind: PersistentHistoryProjectionInvocationKind
    let transactionCount: Int
    let events: Set<StoreDomainEvent>
}

nonisolated enum PersistentHistoryProjectionDriverError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case missingPersistentStoreIdentifier
    case historyStoreIdentifierMismatch(
        expected: String,
        actual: String
    )
    case fullReconciliationSuperseded
    case cursorAdvanceRequiresRetry

    var errorDescription: String? {
        switch self {
        case .missingPersistentStoreIdentifier:
            "The SwiftData store does not expose a persistent identifier."
        case let .historyStoreIdentifierMismatch(expected, actual):
            "Persistent history belongs to store \(actual), not \(expected)."
        case .fullReconciliationSuperseded:
            "The full projection reconciliation was superseded or reset."
        case .cursorAdvanceRequiresRetry:
            "The persistent-history projection cursor changed concurrently."
        }
    }
}

private nonisolated struct PersistentHistoryProjectionStoreIdentity:
    Sendable
{
    let cursorIdentifier: String
    let expectedHistoryIdentifier: String?

    static func resolve(
        scope: TimerStoreScope
    ) throws -> Self {
        guard let storeURL = scope.persistentStoreURL else {
            return Self(
                cursorIdentifier:
                scope.persistentHistoryFallbackStoreIdentifier,
                expectedHistoryIdentifier: nil
            )
        }
        let metadata = try NSPersistentStoreCoordinator
            .metadataForPersistentStore(
                type: .sqlite,
                at: storeURL
            )
        guard let identifier = metadata[NSStoreUUIDKey] as? String,
              identifier.isEmpty == false
        else {
            throw PersistentHistoryProjectionDriverError
                .missingPersistentStoreIdentifier
        }
        return Self(
            cursorIdentifier: identifier,
            expectedHistoryIdentifier: identifier
        )
    }
}

private nonisolated struct PersistentHistoryProjectionHistorySummary:
    Sendable
{
    let lastToken: DefaultHistoryToken?
    let transactionCount: Int
    let allEvents: Set<StoreDomainEvent>
    let localMutationEvents: Set<StoreDomainEvent>
}

@ModelActor
private actor PersistentHistoryProjectionHistoryReader {
    private static let pageSize: UInt64 = 256

    func scan(
        after acknowledgedToken: DefaultHistoryToken?,
        expectedStoreIdentifier: String?
    ) throws -> PersistentHistoryProjectionHistorySummary {
        var lastToken = acknowledgedToken
        var transactionCount = 0
        var allEvents: Set<StoreDomainEvent> = []
        var localMutationEvents: Set<StoreDomainEvent> = []

        while true {
            var descriptor: HistoryDescriptor<DefaultHistoryTransaction> = if let lastToken {
                HistoryDescriptor(
                    predicate: #Predicate { transaction in
                        transaction.token > lastToken
                    }
                )
            } else {
                HistoryDescriptor<DefaultHistoryTransaction>()
            }
            descriptor.fetchLimit = Self.pageSize
            let transactions = try modelContext.fetchHistory(descriptor)
            guard transactions.isEmpty == false else { break }

            // SwiftData returns history chronologically. Preserve that order
            // so the final token is the exact frontier for this page.
            for transaction in transactions {
                if let expectedStoreIdentifier,
                   transaction.storeIdentifier
                   != expectedStoreIdentifier
                {
                    throw PersistentHistoryProjectionDriverError
                        .historyStoreIdentifierMismatch(
                            expected: expectedStoreIdentifier,
                            actual: transaction.storeIdentifier
                        )
                }
                transactionCount = Self.saturatingAdd(
                    transactionCount,
                    1
                )
                let transactionEvents =
                    PersistentHistoryProjectionImpact.events(
                        forEntityNames: Set(transaction.changes.map {
                            $0.changedPersistentIdentifier.entityName
                        })
                    )
                allEvents = StoreDomainEventBatchLimiter.bounded(
                    allEvents.union(transactionEvents)
                )
                if transaction.author
                    == TimeTrackerHistoryAuthor.localMutation.rawValue
                {
                    localMutationEvents =
                        StoreDomainEventBatchLimiter.bounded(
                            localMutationEvents.union(
                                transactionEvents
                            )
                        )
                }
            }

            guard let candidateToken =
                transactions.last?.token,
                candidateToken != lastToken
            else {
                throw PersistentHistoryProjectionDriverError
                    .cursorAdvanceRequiresRetry
            }
            lastToken = candidateToken
            if transactions.count < Int(Self.pageSize) {
                break
            }
        }

        return PersistentHistoryProjectionHistorySummary(
            lastToken: lastToken,
            transactionCount: transactionCount,
            allEvents: allEvents,
            localMutationEvents: localMutationEvents
        )
    }

    private static func saturatingAdd(
        _ lhs: Int,
        _ rhs: Int
    ) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }
}

/// Reads SwiftData history and acknowledges each external projection only
/// after that projection effect succeeds.
///
/// The actor is intentionally not MainActor-isolated. It owns synchronous
/// cursor locks and delegates SwiftData access to a dedicated `@ModelActor`.
/// Callers still own in-process coalescing and per-lane retry policy.
actor PersistentHistoryProjectionDriver {
    typealias Effect = @Sendable (
        PersistentHistoryProjectionInvocation
    ) async throws -> Void

    private enum VolatileCursor {
        case ready(DefaultHistoryToken?)
    }

    private let scope: TimerStoreScope
    private let reader: PersistentHistoryProjectionHistoryReader
    private let localFile: DurableLocalFile
    private let effect: Effect
    private var identity:
        PersistentHistoryProjectionStoreIdentity?
    private var durableCursorStore:
        PersistentHistoryLaneCursorStore?
    private var volatileCursors: [
        PersistentHistoryProjectionLane: VolatileCursor
    ] = [:]

    init(
        container: ModelContainer,
        scope: TimerStoreScope,
        localFile: DurableLocalFile = DurableLocalFile(),
        effect: @escaping Effect
    ) {
        self.scope = scope
        reader = PersistentHistoryProjectionHistoryReader(
            modelContainer: container
        )
        self.localFile = localFile
        self.effect = effect
    }

    func run(
        _ lane: PersistentHistoryProjectionLane,
        forceCurrentStateEffect: Bool = false
    ) async throws {
        if scope.persistentStoreURL == nil {
            let identity = try registeredIdentity()
            try await runVolatile(
                lane,
                identity: identity,
                forceCurrentStateEffect:
                forceCurrentStateEffect
            )
            return
        }

        do {
            let (identity, cursorStore) =
                try registeredPersistentState()
            switch try cursorStore.load(for: lane) {
            case .missing, .requiresFullReconciliation:
                try await reconcileFully(
                    lane,
                    identity: identity,
                    cursorStore: cursorStore
                )
            case let .ready(acknowledgedToken):
                do {
                    try await runIncrementally(
                        lane,
                        after: acknowledgedToken,
                        identity: identity,
                        cursorStore: cursorStore,
                        forceCurrentStateEffect:
                        forceCurrentStateEffect
                    )
                } catch let error as SwiftDataError
                    where error == .historyTokenExpired
                {
                    try await reconcileFully(
                        lane,
                        identity: identity,
                        cursorStore: cursorStore
                    )
                }
            }
        } catch {
            // A reset, superseded attempt, failed effect, or CAS race must not
            // leave a future run permanently bound to a stale registration.
            identity = nil
            durableCursorStore = nil
            throw error
        }
    }

    private func runVolatile(
        _ lane: PersistentHistoryProjectionLane,
        identity: PersistentHistoryProjectionStoreIdentity,
        forceCurrentStateEffect: Bool
    ) async throws {
        guard case let .ready(acknowledgedToken) =
            volatileCursors[lane]
        else {
            let summary = try await reader.scan(
                after: nil,
                expectedStoreIdentifier:
                identity.expectedHistoryIdentifier
            )
            try await effect(PersistentHistoryProjectionInvocation(
                lane: lane,
                kind: .fullReconciliation,
                transactionCount: summary.transactionCount,
                events: [.fullSync]
            ))
            volatileCursors[lane] = .ready(summary.lastToken)
            return
        }

        let summary = try await reader.scan(
            after: acknowledgedToken,
            expectedStoreIdentifier:
            identity.expectedHistoryIdentifier
        )
        guard let candidateToken = summary.lastToken,
              candidateToken != acknowledgedToken
        else {
            if forceCurrentStateEffect {
                try await runForcedCurrentStateEffect(
                    lane: lane,
                    transactionCount: 0
                )
            }
            return
        }
        if Self.shouldRunEffect(lane: lane, summary: summary) {
            try await effect(PersistentHistoryProjectionInvocation(
                lane: lane,
                kind: .incremental,
                transactionCount: summary.transactionCount,
                events: Self.events(
                    for: lane,
                    summary: summary
                )
            ))
        } else if forceCurrentStateEffect {
            try await runForcedCurrentStateEffect(
                lane: lane,
                transactionCount: summary.transactionCount
            )
        }
        volatileCursors[lane] = .ready(candidateToken)
    }

    private func reconcileFully(
        _ lane: PersistentHistoryProjectionLane,
        identity: PersistentHistoryProjectionStoreIdentity,
        cursorStore: PersistentHistoryLaneCursorStore
    ) async throws {
        guard let attempt = try cursorStore.beginFullReconciliation(
            for: lane
        ) else {
            throw PersistentHistoryProjectionDriverError
                .fullReconciliationSuperseded
        }
        let summary = try await reader.scan(
            after: nil,
            expectedStoreIdentifier:
            identity.expectedHistoryIdentifier
        )
        try await effect(PersistentHistoryProjectionInvocation(
            lane: lane,
            kind: .fullReconciliation,
            transactionCount: summary.transactionCount,
            events: [.fullSync]
        ))
        guard try cursorStore.establishAfterFullReconciliation(
            summary.lastToken,
            for: lane,
            attempt: attempt
        ) else {
            throw PersistentHistoryProjectionDriverError
                .fullReconciliationSuperseded
        }
    }

    private func runIncrementally(
        _ lane: PersistentHistoryProjectionLane,
        after acknowledgedToken: DefaultHistoryToken?,
        identity: PersistentHistoryProjectionStoreIdentity,
        cursorStore: PersistentHistoryLaneCursorStore,
        forceCurrentStateEffect: Bool
    ) async throws {
        let summary = try await reader.scan(
            after: acknowledgedToken,
            expectedStoreIdentifier:
            identity.expectedHistoryIdentifier
        )
        guard let candidateToken = summary.lastToken,
              candidateToken != acknowledgedToken
        else {
            if forceCurrentStateEffect {
                try await runForcedCurrentStateEffect(
                    lane: lane,
                    transactionCount: 0
                )
            }
            return
        }
        if Self.shouldRunEffect(lane: lane, summary: summary) {
            try await effect(PersistentHistoryProjectionInvocation(
                lane: lane,
                kind: .incremental,
                transactionCount: summary.transactionCount,
                events: Self.events(
                    for: lane,
                    summary: summary
                )
            ))
        } else if forceCurrentStateEffect {
            try await runForcedCurrentStateEffect(
                lane: lane,
                transactionCount: summary.transactionCount
            )
        }
        switch try cursorStore.advanceIncrementally(
            to: candidateToken,
            after: acknowledgedToken,
            for: lane
        ) {
        case .advanced, .alreadyAcknowledged:
            return
        case .retryRequired:
            throw PersistentHistoryProjectionDriverError
                .cursorAdvanceRequiresRetry
        }
    }

    private func runForcedCurrentStateEffect(
        lane: PersistentHistoryProjectionLane,
        transactionCount: Int
    ) async throws {
        try await effect(PersistentHistoryProjectionInvocation(
            lane: lane,
            kind: .forcedCurrentState,
            transactionCount: transactionCount,
            events: []
        ))
    }

    private func registeredIdentity()
        throws -> PersistentHistoryProjectionStoreIdentity
    {
        if let identity {
            return identity
        }
        let resolved =
            try PersistentHistoryProjectionStoreIdentity.resolve(
                scope: scope
            )
        identity = resolved
        return resolved
    }

    /// Resolves the physical store UUID inside an epoch read sandwich.
    ///
    /// A Cloud recovery can replace the SQLite file while metadata is being
    /// resolved. Caching only when both epoch reads agree prevents a new epoch
    /// from ever being paired with the old store's UUID.
    private func registeredPersistentState() throws -> (
        PersistentHistoryProjectionStoreIdentity,
        PersistentHistoryLaneCursorStore
    ) {
        if let identity, let durableCursorStore {
            return (identity, durableCursorStore)
        }

        let resetFence = PersistentHistoryProjectionResetFence(
            scope: scope,
            localFile: localFile
        )
        while true {
            let epochBeforeMetadata = try resetFence.currentEpoch()
            let resolved =
                try PersistentHistoryProjectionStoreIdentity.resolve(
                    scope: scope
                )
            let epochAfterMetadata = try resetFence.currentEpoch()
            guard epochBeforeMetadata == epochAfterMetadata else {
                continue
            }

            let registered = PersistentHistoryLaneCursorStore(
                scope: scope,
                storeIdentifier: resolved.cursorIdentifier,
                registeredResetEpoch: epochAfterMetadata,
                localFile: localFile
            )
            identity = resolved
            durableCursorStore = registered
            return (resolved, registered)
        }
    }

    private static func shouldRunEffect(
        lane: PersistentHistoryProjectionLane,
        summary: PersistentHistoryProjectionHistorySummary
    ) -> Bool {
        PersistentHistoryProjectionImpact.affects(
            lane: lane,
            events: events(for: lane, summary: summary)
        )
    }

    private static func events(
        for lane: PersistentHistoryProjectionLane,
        summary: PersistentHistoryProjectionHistorySummary
    ) -> Set<StoreDomainEvent> {
        switch lane {
        case .syncSnapshot:
            summary.localMutationEvents
        case .widget, .watch, .liveActivity:
            summary.allEvents
        }
    }
}
