import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTimerMutationLockTests {
    @Test
    func storeScopesCanonicalizePersistentPathsAndRetainInMemoryIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let realDirectory = fixture.root.appendingPathComponent("real", isDirectory: true)
        let aliasDirectory = fixture.root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasDirectory,
            withDestinationURL: realDirectory
        )

        let direct = TimerStoreScope(
            persistentStoreURL: realDirectory.appendingPathComponent("timer.store")
        )
        let aliased = TimerStoreScope(
            persistentStoreURL: aliasDirectory.appendingPathComponent("timer.store")
        )
        #expect(direct == aliased)
        #expect(direct.mutationLockURL.lastPathComponent == "timer.store.timer-mutations.lock")

        let identity = UUID()
        #expect(
            TimerStoreScope(inMemoryIdentity: identity)
                == TimerStoreScope(inMemoryIdentity: identity)
        )
        #expect(
            TimerStoreScope(inMemoryIdentity: identity)
                != TimerStoreScope(inMemoryIdentity: UUID())
        )
    }

    @Test
    func sameStoreCannotEnterTwoTimerMutationsConcurrently() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scope = fixture.scope(named: "shared.store")
        let lock = StoreScopedTimerMutationLock()
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondAttempting = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? lock.withExclusiveAccess(for: scope) {
                firstEntered.signal()
                releaseFirst.wait()
            }
            firstFinished.signal()
        }
        #expect(firstEntered.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global().async {
            secondAttempting.signal()
            _ = try? lock.withExclusiveAccess(for: scope) {
                secondEntered.signal()
            }
            secondFinished.signal()
        }
        #expect(secondAttempting.wait(timeout: .now() + 2) == .success)
        #expect(secondEntered.wait(timeout: .now() + 0.05) == .timedOut)

        releaseFirst.signal()
        #expect(firstFinished.wait(timeout: .now() + 2) == .success)
        #expect(secondEntered.wait(timeout: .now() + 2) == .success)
        #expect(secondFinished.wait(timeout: .now() + 2) == .success)
    }

    @Test
    func differentStoresDoNotBlockEachOther() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstScope = fixture.scope(named: "first.store")
        let secondScope = fixture.scope(named: "second.store")
        let lock = StoreScopedTimerMutationLock()
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? lock.withExclusiveAccess(for: firstScope) {
                firstEntered.signal()
                releaseFirst.wait()
            }
            firstFinished.signal()
        }
        #expect(firstEntered.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global().async {
            _ = try? lock.withExclusiveAccess(for: secondScope) {
                secondEntered.signal()
            }
            secondFinished.signal()
        }
        #expect(secondEntered.wait(timeout: .now() + 2) == .success)
        #expect(secondFinished.wait(timeout: .now() + 2) == .success)

        releaseFirst.signal()
        #expect(firstFinished.wait(timeout: .now() + 2) == .success)
    }

    @Test
    func thrownMutationReleasesTheStoreLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scope = fixture.scope(named: "throwing.store")
        let lock = StoreScopedTimerMutationLock()

        #expect(throws: InjectedFailure.self) {
            try lock.withExclusiveAccess(for: scope) { () throws in
                throw InjectedFailure()
            }
        }
        let value = try lock.withExclusiveAccess(for: scope) { 42 }
        #expect(value == 42)
    }

    @Test
    func transactionCreatesFreshContextsOnlyAfterEnteringTheStoreLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scope = fixture.scope(named: "context.store")
        let lock = StoreScopedTimerMutationLock()
        let container = try timetrackerApp.makeUnitTestHostModelContainer()
        let competingAttempt = DispatchSemaphore(value: 0)
        let competingEntry = DispatchSemaphore(value: 0)
        let competingFinished = DispatchSemaphore(value: 0)
        let competitorWasBlocked = ThreadSafeFlag()
        var creationCount = 0
        let factory = TimerModelContextFactory {
            creationCount += 1
            if creationCount == 1 {
                DispatchQueue.global().async {
                    competingAttempt.signal()
                    _ = try? lock.withExclusiveAccess(for: scope) {
                        competingEntry.signal()
                    }
                    competingFinished.signal()
                }
                let attempted = competingAttempt.wait(timeout: .now() + 2) == .success
                let entry = competingEntry.wait(timeout: .now() + 0.05)
                competitorWasBlocked.set(attempted && entry == .timedOut)
            }
            return ModelContext(container)
        }
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            contextFactory: factory,
            mutationLock: lock
        )
        var retainedContexts: [ModelContext] = []

        try transaction.withFreshContext { retainedContexts.append($0) }
        #expect(competingEntry.wait(timeout: .now() + 2) == .success)
        #expect(competingFinished.wait(timeout: .now() + 2) == .success)
        try transaction.withFreshContext { retainedContexts.append($0) }

        #expect(competitorWasBlocked.value)
        #expect(retainedContexts.count == 2)
        #expect(retainedContexts[0] !== retainedContexts[1])
    }

    @Test
    func transactionCommitsOnceAndRollsBackThrownMutations() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scope = fixture.scope(named: "atomic.store")
        let container = try timetrackerApp.makeUnitTestHostModelContainer()
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        try transaction.withFreshContext { context in
            context.insert(
                TaskNode(title: "Committed", parentID: nil, deviceID: "test")
            )
        }
        #expect(
            try transaction.withFreshContext { context in
                try context.fetch(FetchDescriptor<TaskNode>()).map(\.title)
            } == ["Committed"]
        )

        #expect(throws: InjectedFailure.self) {
            try transaction.withFreshContext { context in
                context.insert(
                    TaskNode(title: "Rolled back", parentID: nil, deviceID: "test")
                )
                throw InjectedFailure()
            }
        }
        #expect(
            try transaction.withFreshContext { context in
                try context.fetch(FetchDescriptor<TaskNode>()).map(\.title)
            } == ["Committed"]
        )
    }

    @Test
    func readTransactionUsesFreshContextsWithoutSavingThem() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let scope = fixture.scope(named: "read.store")
        let container = try timetrackerApp.makeUnitTestHostModelContainer()
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        var firstContext: ModelContext?

        try transaction.withFreshReadContext { context in
            firstContext = context
            context.insert(
                TaskNode(title: "Must not save", parentID: nil, deviceID: "test")
            )
        }

        let persistedTitles = try transaction.withFreshReadContext { context in
            #expect(context !== firstContext)
            return try context.fetch(FetchDescriptor<TaskNode>()).map(\.title)
        }
        #expect(persistedTitles.isEmpty)
    }

    private struct InjectedFailure: Error {}

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TimeTrackerTimerMutationLockTests-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func scope(named fileName: String) -> TimerStoreScope {
            TimerStoreScope(persistentStoreURL: root.appendingPathComponent(fileName))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private final nonisolated class ThreadSafeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}
