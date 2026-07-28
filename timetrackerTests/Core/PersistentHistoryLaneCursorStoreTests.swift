import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PersistentHistoryLaneCursorStoreTests {
    @Test @MainActor
    func persistentStoreUsesCanonicalIndependentLaneLocations() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let physicalDirectory = fixture.directory.appendingPathComponent(
            "physical",
            isDirectory: true
        )
        let aliasDirectory = fixture.directory.appendingPathComponent(
            "alias",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: physicalDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory,
            withDestinationURL: physicalDirectory
        )
        let physicalStoreURL = physicalDirectory.appendingPathComponent(
            "timetracker.store"
        )
        let aliasedScope = TimerStoreScope(
            persistentStoreURL: aliasDirectory.appendingPathComponent(
                "timetracker.store"
            )
        )
        let physicalScope = TimerStoreScope(
            persistentStoreURL: physicalStoreURL
        )
        let aliasedStore = PersistentHistoryLaneCursorStore(
            scope: aliasedScope,
            storeIdentifier: "store-id",
            registeredResetEpoch: 0
        )
        let physicalStore = PersistentHistoryLaneCursorStore(
            scope: physicalScope,
            storeIdentifier: "store-id",
            registeredResetEpoch: 0
        )
        let expectedDirectory = CanonicalFileURL.resolvingExistingAncestor(
            of: physicalDirectory
        )
        let expectedNames: [
            PersistentHistoryProjectionLane: String
        ] = [
            .syncSnapshot:
                "timetracker.store.post-commit-history.sync-snapshot.cursor.v1.json",
            .widget:
                "timetracker.store.post-commit-history.widget.cursor.v1.json",
            .watch:
                "timetracker.store.post-commit-history.watch.cursor.v1.json",
            .liveActivity:
                "timetracker.store.post-commit-history.live-activity.cursor.v1.json",
        ]

        let locations = try PersistentHistoryProjectionLane.allCases.map {
            lane in
            let aliasedLocation = try #require(
                aliasedStore.durableLocation(for: lane)
            )
            let physicalLocation = try #require(
                physicalStore.durableLocation(for: lane)
            )

            #expect(aliasedLocation == physicalLocation)
            #expect(
                physicalLocation.deletingLastPathComponent()
                    == expectedDirectory
            )
            #expect(
                physicalLocation.lastPathComponent
                    == expectedNames[lane]
            )
            #expect(
                physicalLocation.lastPathComponent.hasPrefix(
                    physicalStoreURL.lastPathComponent
                )
            )
            return physicalLocation
        }

        #expect(Set(locations).count == PersistentHistoryProjectionLane.allCases.count)
    }

    @Test
    func inMemoryScopeHasNoDurableLaneLocation() {
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(inMemoryIdentity: UUID()),
            storeIdentifier: "in-memory",
            registeredResetEpoch: 0
        )

        for lane in PersistentHistoryProjectionLane.allCases {
            #expect(store.durableLocation(for: lane) == nil)
        }
    }

    @Test @MainActor
    func registrationFactoryCapturesCurrentResetEpoch() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let fence = PersistentHistoryProjectionResetFence(scope: scope)
        #expect(try fence.advanceForStoreReset() == 1)

        let store = try PersistentHistoryLaneCursorStore
            .registeringCurrentEpoch(
                scope: scope,
                storeIdentifier: "replacement-store"
            )
        let maybeAttempt = try store.beginFullReconciliation(for: .widget)
        let attempt = try #require(maybeAttempt)

        #expect(attempt.resetEpoch == 1)
    }

    @Test @MainActor
    func realOpaqueTokensRoundTripAndRemainLaneIndependent() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let writer = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )

        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .syncSnapshot,
            using: writer
        )
        try establishAfterFullReconciliation(
            history.tokens[1],
            for: .widget,
            using: writer
        )

        let reader = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        #expect(
            try readyToken(reader.load(for: .syncSnapshot))
                == history.tokens[0]
        )
        #expect(
            try readyToken(reader.load(for: .widget))
                == history.tokens[1]
        )
        #expect(
            reader.durableLocation(for: .syncSnapshot)
                != reader.durableLocation(for: .widget)
        )
        #expect(
            try FileManager.default.fileExists(
                atPath: #require(
                    reader.durableLocation(for: .syncSnapshot)
                ).path
            )
        )
        #expect(
            try FileManager.default.fileExists(
                atPath: #require(
                    reader.durableLocation(for: .widget)
                ).path
            )
        )
    }

    @Test @MainActor
    func missingCursorCannotAcknowledgeIncrementalHistory() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )

        let result = try store.advanceIncrementally(
            to: history.tokens[1],
            after: history.tokens[0],
            for: .watch
        )

        #expect(result == .retryRequired)
        guard case .missing = try store.load(for: .watch) else {
            Issue.record(
                "A missing lane must continue to require full reconciliation"
            )
            return
        }
        let location = try #require(
            store.durableLocation(for: .watch)
        )
        #expect(
            FileManager.default.fileExists(atPath: location.path) == false
        )
    }

    @Test @MainActor
    func incrementalAdvanceIsStrictlyMonotonicAndCompareAndSwap() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 3)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let firstProcess = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        let secondProcess = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .syncSnapshot,
            using: firstProcess
        )

        #expect(
            try firstProcess.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[0],
                for: .syncSnapshot
            ) == .advanced
        )
        #expect(
            try secondProcess.advanceIncrementally(
                to: history.tokens[2],
                after: history.tokens[0],
                for: .syncSnapshot
            ) == .retryRequired
        )
        #expect(
            try secondProcess.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[1],
                for: .syncSnapshot
            ) == .alreadyAcknowledged
        )
        #expect(
            try secondProcess.advanceIncrementally(
                to: history.tokens[0],
                after: history.tokens[1],
                for: .syncSnapshot
            ) == .alreadyAcknowledged
        )
        #expect(
            try secondProcess.advanceIncrementally(
                to: history.tokens[2],
                after: history.tokens[1],
                for: .syncSnapshot
            ) == .advanced
        )
        #expect(
            try readyToken(firstProcess.load(for: .syncSnapshot))
                == history.tokens[2]
        )
    }

    @Test @MainActor
    func concurrentSameLaneCompareAndSwapAllowsExactlyOneWinner() async throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 3)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let storeIdentifier = history.storeIdentifier
        let originalToken = history.tokens[0]
        let firstCandidate = history.tokens[1]
        let secondCandidate = history.tokens[2]
        let initialStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            originalToken,
            for: .syncSnapshot,
            using: initialStore
        )

        let results = try await withThrowingTaskGroup(
            of: PersistentHistoryLaneCursorAdvanceResult.self,
            returning: [PersistentHistoryLaneCursorAdvanceResult].self
        ) { group in
            group.addTask {
                try PersistentHistoryLaneCursorStore(
                    scope: scope,
                    storeIdentifier: storeIdentifier,
                    registeredResetEpoch: 0
                ).advanceIncrementally(
                    to: firstCandidate,
                    after: originalToken,
                    for: .syncSnapshot
                )
            }
            group.addTask {
                try PersistentHistoryLaneCursorStore(
                    scope: scope,
                    storeIdentifier: storeIdentifier,
                    registeredResetEpoch: 0
                ).advanceIncrementally(
                    to: secondCandidate,
                    after: originalToken,
                    for: .syncSnapshot
                )
            }
            var results: [PersistentHistoryLaneCursorAdvanceResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        #expect(results.filter { $0 == .advanced }.count == 1)
        #expect(
            results.allSatisfy {
                $0 == .advanced ||
                    $0 == .alreadyAcknowledged ||
                    $0 == .retryRequired
            }
        )
        let persistedToken = try readyToken(
            PersistentHistoryLaneCursorStore(
                scope: scope,
                storeIdentifier: storeIdentifier,
                registeredResetEpoch: 0
            ).load(for: .syncSnapshot)
        )
        #expect(
            persistedToken == firstCandidate
                || persistedToken == secondCandidate
        )
    }

    @Test @MainActor
    func storeIdentifierMismatchRequiresFullReconciliationWithoutReplacingCursor()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let originalStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .widget,
            using: originalStore
        )
        let location = try #require(
            originalStore.durableLocation(for: .widget)
        )
        let originalData = try Data(contentsOf: location)
        let replacementIdentifier = history.storeIdentifier + "-replacement"
        let replacementStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: replacementIdentifier,
            registeredResetEpoch: 0
        )

        try expectRequiresFullReconciliation(
            replacementStore.load(for: .widget)
        )
        #expect(try Data(contentsOf: location) == originalData)
        #expect(
            try replacementStore.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[0],
                for: .widget
            ) == .retryRequired
        )
        #expect(try Data(contentsOf: location) == originalData)

        try establishAfterFullReconciliation(
            history.tokens[1],
            for: .widget,
            using: replacementStore
        )

        #expect(try Data(contentsOf: location) != originalData)
        #expect(
            try readyToken(replacementStore.load(for: .widget))
                == history.tokens[1]
        )
    }

    @Test @MainActor
    func unsupportedVersionAndWrongLaneRequireFullReconciliation() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 1)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        let versionLocation = try #require(
            store.durableLocation(for: .syncSnapshot)
        )
        let laneLocation = try #require(
            store.durableLocation(for: .liveActivity)
        )
        try writeForgedEnvelope(
            formatVersion: 2,
            lane: .syncSnapshot,
            storeIdentifier: history.storeIdentifier,
            token: history.tokens[0],
            to: versionLocation,
            durableRoot: fixture.directory
        )
        try writeForgedEnvelope(
            formatVersion: 1,
            lane: .watch,
            storeIdentifier: history.storeIdentifier,
            token: history.tokens[0],
            to: laneLocation,
            durableRoot: fixture.directory
        )

        try expectRequiresFullReconciliation(
            store.load(for: .syncSnapshot)
        )
        try expectRequiresFullReconciliation(
            store.load(for: .liveActivity)
        )
        #expect(
            FileManager.default.fileExists(atPath: versionLocation.path)
                == false
        )
        #expect(
            FileManager.default.fileExists(atPath: laneLocation.path)
                == false
        )
        #expect(try quarantineEntries(in: fixture.directory).count == 2)
    }

    @Test @MainActor
    func corruptAndOversizedLaneFilesAreQuarantinedWithoutAffectingSibling()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 1)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .widget,
            using: store
        )
        let widgetLocation = try #require(
            store.durableLocation(for: .widget)
        )
        let widgetData = try Data(contentsOf: widgetLocation)
        let corruptLocation = try #require(
            store.durableLocation(for: .syncSnapshot)
        )
        let oversizedLocation = try #require(
            store.durableLocation(for: .watch)
        )
        try DurableLocalFile().write(
            Data("{invalid".utf8),
            to: corruptLocation,
            durableRootURL: fixture.directory
        )
        try DurableLocalFile().write(
            Data(repeating: 0x41, count: 64 * 1024 + 1),
            to: oversizedLocation,
            durableRootURL: fixture.directory
        )

        try expectRequiresFullReconciliation(
            store.load(for: .syncSnapshot)
        )
        try expectRequiresFullReconciliation(
            store.load(for: .watch)
        )

        #expect(
            try readyToken(store.load(for: .widget))
                == history.tokens[0]
        )
        #expect(try Data(contentsOf: widgetLocation) == widgetData)
        #expect(
            FileManager.default.fileExists(atPath: corruptLocation.path)
                == false
        )
        #expect(
            FileManager.default.fileExists(atPath: oversizedLocation.path)
                == false
        )
        let quarantine = try quarantineEntries(in: fixture.directory)
        #expect(quarantine.count == 2)
        #expect(
            try Set(quarantine.map { try Data(contentsOf: $0) })
                == [
                    Data("{invalid".utf8),
                    Data(repeating: 0x41, count: 64 * 1024 + 1),
                ]
        )
    }

    @Test @MainActor
    func failedAtomicReplacementPreservesPreviousCursor() throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let healthyStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .watch,
            using: healthyStore
        )
        let failingStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0,
            localFile: DurableLocalFile(injectFault: { point in
                if point == .afterAtomicWriteBeforeFileSync {
                    throw PersistentHistoryCursorInjectedFailure()
                }
            })
        )

        #expect(throws: PersistentHistoryCursorInjectedFailure.self) {
            _ = try failingStore.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[0],
                for: .watch
            )
        }

        #expect(
            try readyToken(healthyStore.load(for: .watch))
                == history.tokens[0]
        )
        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(".TimeTrackerWrite-")
        }
        #expect(temporaryFiles.isEmpty)
    }

    @Test @MainActor
    func concurrentWritesToDifferentLanesBothSurvive() async throws {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let storeIdentifier = history.storeIdentifier
        let firstToken = history.tokens[0]
        let secondToken = history.tokens[1]

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let store = PersistentHistoryLaneCursorStore(
                    scope: scope,
                    storeIdentifier: storeIdentifier,
                    registeredResetEpoch: 0
                )
                try establishAfterFullReconciliation(
                    firstToken,
                    for: .syncSnapshot,
                    using: store
                )
            }
            group.addTask {
                let store = PersistentHistoryLaneCursorStore(
                    scope: scope,
                    storeIdentifier: storeIdentifier,
                    registeredResetEpoch: 0
                )
                try establishAfterFullReconciliation(
                    secondToken,
                    for: .liveActivity,
                    using: store
                )
            }
            try await group.waitForAll()
        }

        let reader = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: storeIdentifier,
            registeredResetEpoch: 0
        )
        #expect(
            try readyToken(reader.load(for: .syncSnapshot))
                == firstToken
        )
        #expect(
            try readyToken(reader.load(for: .liveActivity))
                == secondToken
        )
    }

    @Test @MainActor
    func emptyFullReconciliationBaselineCanAdvanceAfterFirstTransaction()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 1)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )

        try establishAfterFullReconciliation(
            nil,
            for: .widget,
            using: store
        )
        guard case let .ready(token) = try store.load(for: .widget) else {
            Issue.record("Expected an established empty baseline")
            return
        }
        #expect(token == nil)
        #expect(
            try store.advanceIncrementally(
                to: history.tokens[0],
                after: nil,
                for: .widget
            ) == .advanced
        )
        #expect(
            try readyToken(store.load(for: .widget))
                == history.tokens[0]
        )
    }

    @Test @MainActor
    func supersededFullReconciliationAttemptCannotOverwriteNewerCursor()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        let maybeOlderAttempt = try store.beginFullReconciliation(
            for: .syncSnapshot
        )
        let olderAttempt = try #require(maybeOlderAttempt)
        let maybeNewerAttempt = try store.beginFullReconciliation(
            for: .syncSnapshot
        )
        let newerAttempt = try #require(maybeNewerAttempt)

        #expect(
            try store.establishAfterFullReconciliation(
                history.tokens[1],
                for: .syncSnapshot,
                attempt: newerAttempt
            )
        )
        #expect(
            try store.establishAfterFullReconciliation(
                history.tokens[0],
                for: .syncSnapshot,
                attempt: olderAttempt
            ) == false
        )
        #expect(
            try readyToken(store.load(for: .syncSnapshot))
                == history.tokens[1]
        )
    }

    @Test @MainActor
    func activeFullReconciliationAttemptBlocksIncrementalAcknowledgement()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .widget,
            using: store
        )
        let maybeAttempt = try store.beginFullReconciliation(
            for: .widget
        )
        let attempt = try #require(maybeAttempt)

        guard case
            .requiresFullReconciliation(.interruptedFullReconciliation) =
            try store.load(for: .widget)
        else {
            Issue.record("An active attempt must require full reconciliation")
            return
        }
        #expect(
            try store.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[0],
                for: .widget
            ) == .retryRequired
        )
        #expect(
            try store.establishAfterFullReconciliation(
                history.tokens[1],
                for: .widget,
                attempt: attempt
            )
        )
        #expect(
            try readyToken(store.load(for: .widget))
                == history.tokens[1]
        )
    }

    @Test @MainActor
    func currentFullReconciliationAttemptCanRebaseToEmptyBaseline()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 1)
        let store = PersistentHistoryLaneCursorStore(
            scope: TimerStoreScope(
                persistentStoreURL: fixture.storeURL
            ),
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        try establishAfterFullReconciliation(
            history.tokens[0],
            for: .liveActivity,
            using: store
        )
        let maybeAttempt = try store.beginFullReconciliation(
            for: .liveActivity
        )
        let attempt = try #require(maybeAttempt)

        #expect(
            try store.establishAfterFullReconciliation(
                nil,
                for: .liveActivity,
                attempt: attempt
            )
        )
        guard case let .ready(token) =
            try store.load(for: .liveActivity)
        else {
            Issue.record("Expected the rebased empty baseline")
            return
        }
        #expect(token == nil)
    }

    @Test @MainActor
    func resetEpochRejectsOldWorkAndAllowsNewCoordinatorToReconcile()
        throws
    {
        let fixture = try PersistentHistoryLaneCursorFixture(
            name: #function
        )
        defer { fixture.remove() }
        let history = try fixture.makeHistoryTokens(count: 2)
        let scope = TimerStoreScope(
            persistentStoreURL: fixture.storeURL
        )
        let fence = PersistentHistoryProjectionResetFence(scope: scope)
        #expect(try fence.currentEpoch() == 0)
        let oldStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 0
        )
        let maybeOldAttempt = try oldStore.beginFullReconciliation(
            for: .watch
        )
        let oldAttempt = try #require(maybeOldAttempt)

        #expect(try fence.advanceForStoreReset() == 1)
        #expect(
            try oldStore.establishAfterFullReconciliation(
                history.tokens[0],
                for: .watch,
                attempt: oldAttempt
            ) == false
        )
        #expect(
            try oldStore.beginFullReconciliation(for: .watch) == nil
        )
        #expect(
            try oldStore.advanceIncrementally(
                to: history.tokens[1],
                after: history.tokens[0],
                for: .watch
            ) == .retryRequired
        )
        guard case .requiresFullReconciliation(.resetEpochMismatch) =
            try oldStore.load(for: .watch)
        else {
            Issue.record("Old work must observe the reset epoch mismatch")
            return
        }

        let newStore = PersistentHistoryLaneCursorStore(
            scope: scope,
            storeIdentifier: history.storeIdentifier,
            registeredResetEpoch: 1
        )
        try establishAfterFullReconciliation(
            history.tokens[1],
            for: .watch,
            using: newStore
        )
        #expect(
            try readyToken(newStore.load(for: .watch))
                == history.tokens[1]
        )
    }
}

private struct PersistentHistoryCursorEnvelope: Encodable {
    let formatVersion: Int
    let lane: PersistentHistoryProjectionLane
    let storeIdentifier: String
    let resetEpoch: UInt64 = 0
    let token: DefaultHistoryToken
}

private struct PersistentHistoryCursorInjectedFailure: Error {}

private enum PersistentHistoryCursorTestFailure: Error {
    case expectedReadyCursor
}

private struct PersistentHistoryCursorTokens {
    let storeIdentifier: String
    let tokens: [DefaultHistoryToken]
}

@MainActor
private struct PersistentHistoryLaneCursorFixture {
    let directory: URL
    let storeURL: URL

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PersistentHistoryLaneCursorStoreTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        storeURL = directory.appendingPathComponent("timetracker.store")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func makeHistoryTokens(
        count: Int
    ) throws -> PersistentHistoryCursorTokens {
        precondition(count > 0)
        return try autoreleasepool {
            let schema = TimeTrackerModelRegistry.currentSchema
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [
                    ModelConfiguration(
                        "PersistentHistoryLaneCursor",
                        schema: schema,
                        url: storeURL,
                        cloudKitDatabase: .none
                    ),
                ]
            )
            let context = ModelContext(container)
            context.autosaveEnabled = false

            for index in 0 ..< count {
                try context.performAtomicMutation(
                    author: .localMutation
                ) {
                    context.insert(
                        TaskNode(
                            title: "History \(index)",
                            parentID: nil,
                            deviceID: "history-cursor-test"
                        )
                    )
                }
            }

            let transactions = try context.fetchHistory(
                HistoryDescriptor<DefaultHistoryTransaction>()
            ).filter {
                $0.author == TimeTrackerHistoryAuthor.localMutation.rawValue
                    && $0.changes.isEmpty == false
            }
            let selected = Array(
                transactions
                    .sorted { $0.token < $1.token }
                    .suffix(count)
            )
            guard selected.count == count,
                  let storeIdentifier = selected.first?.storeIdentifier
            else {
                throw PersistentHistoryCursorTestFailure
                    .expectedReadyCursor
            }
            return PersistentHistoryCursorTokens(
                storeIdentifier: storeIdentifier,
                tokens: selected.map(\.token)
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func readyToken(
    _ result: PersistentHistoryLaneCursorLoadResult
) throws -> DefaultHistoryToken {
    guard case let .ready(optionalToken) = result,
          let token = optionalToken
    else {
        Issue.record("Expected a ready persistent-history lane cursor")
        throw PersistentHistoryCursorTestFailure.expectedReadyCursor
    }
    return token
}

private func establishAfterFullReconciliation(
    _ token: DefaultHistoryToken?,
    for lane: PersistentHistoryProjectionLane,
    using store: PersistentHistoryLaneCursorStore
) throws {
    let maybeAttempt = try store.beginFullReconciliation(for: lane)
    let attempt = try #require(maybeAttempt)
    #expect(
        try store.establishAfterFullReconciliation(
            token,
            for: lane,
            attempt: attempt
        )
    )
}

private func expectRequiresFullReconciliation(
    _ result: PersistentHistoryLaneCursorLoadResult
) {
    guard case .requiresFullReconciliation = result else {
        Issue.record(
            "Invalid persistent-history cursor must require full reconciliation"
        )
        return
    }
}

private func writeForgedEnvelope(
    formatVersion: Int,
    lane: PersistentHistoryProjectionLane,
    storeIdentifier: String,
    token: DefaultHistoryToken,
    to location: URL,
    durableRoot: URL
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try DurableLocalFile().write(
        encoder.encode(
            PersistentHistoryCursorEnvelope(
                formatVersion: formatVersion,
                lane: lane,
                storeIdentifier: storeIdentifier,
                token: token
            )
        ),
        to: location,
        durableRootURL: durableRoot
    )
}

private func quarantineEntries(in root: URL) throws -> [URL] {
    let directory = root.appendingPathComponent(
        ".TimeTrackerQuarantine",
        isDirectory: true
    )
    guard FileManager.default.fileExists(atPath: directory.path) else {
        return []
    }
    return try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).sorted { $0.lastPathComponent < $1.lastPathComponent }
}
