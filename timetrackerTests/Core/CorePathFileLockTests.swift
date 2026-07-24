import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CorePathFileLockTests {
    @Test
    func registryCanonicalizesEquivalentPathsAndReusesOneProcessLock() {
        let root = FileManager.default.temporaryDirectory
        let direct = root.appendingPathComponent("TimeTracker.lock")
        let equivalent = root
            .appendingPathComponent("nested")
            .appendingPathComponent("..")
            .appendingPathComponent("TimeTracker.lock")

        let first = PathFileLockRegistry.shared.lock(for: direct)
        let second = PathFileLockRegistry.shared.lock(for: equivalent)

        #expect(first === second)
    }

    @Test
    func processLockSupportsNestedAccessAndReleasesAfterAnError() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lockURL = fixture.root.appendingPathComponent("state.lock")
        let lock = PathFileLockRegistry.shared.lock(for: lockURL)
        var depth = 0

        try lock.withExclusiveAccess {
            depth += 1
            try lock.withExclusiveAccess {
                depth += 1
            }
        }
        #expect(depth == 2)

        #expect(throws: InjectedFailure.self) {
            try lock.withExclusiveAccess { () throws -> Void in
                throw InjectedFailure()
            }
        }
        let value = try lock.withExclusiveAccess { 42 }
        #expect(value == 42)
    }

    @Test
    func registryResolvesSymlinkedParentDirectories() throws {
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

        let direct = realDirectory.appendingPathComponent("nested/state.lock")
        let aliased = aliasDirectory.appendingPathComponent("nested/state.lock")

        #expect(
            PathFileLockRegistry.shared.lock(for: direct)
                === PathFileLockRegistry.shared.lock(for: aliased)
        )
    }

    @Test
    func processLockOpensThroughASymbolicLinkOnlyAboveTheLockPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let physicalDirectory = fixture.root.appendingPathComponent(
            "physical",
            isDirectory: true
        )
        let aliasDirectory = fixture.root.appendingPathComponent(
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
        let lockURL = aliasDirectory.appendingPathComponent("state.lock")

        let value = try PathFileLockRegistry.shared.lock(for: lockURL)
            .withExclusiveAccess { 42 }

        #expect(value == 42)
        #expect(
            FileManager.default.fileExists(
                atPath: physicalDirectory.appendingPathComponent("state.lock").path
            )
        )
    }

    @Test
    func processLockStillRejectsASymbolicLinkAtTheLockPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let targetURL = fixture.root.appendingPathComponent("target.lock")
        let aliasURL = fixture.root.appendingPathComponent("alias.lock")
        try Data().write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: aliasURL,
            withDestinationURL: targetURL
        )

        #expect(throws: POSIXError.self) {
            try PathFileLockRegistry.shared.lock(for: aliasURL)
                .withExclusiveAccess {}
        }
    }

    @Test
    func hardLinkAliasesCannotEnterTheSameFileLockConcurrently() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directURL = fixture.root.appendingPathComponent("direct.lock")
        let aliasURL = fixture.root.appendingPathComponent("alias.lock")
        try Data().write(to: directURL)
        try FileManager.default.linkItem(at: directURL, to: aliasURL)

        let directLock = PathFileLockRegistry.shared.lock(for: directURL)
        let aliasLock = PathFileLockRegistry.shared.lock(for: aliasURL)
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondAttempting = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? directLock.withExclusiveAccess {
                firstEntered.signal()
                releaseFirst.wait()
            }
            firstFinished.signal()
        }
        #expect(firstEntered.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global().async {
            secondAttempting.signal()
            _ = try? aliasLock.withExclusiveAccess {
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
    func processLockTimesOutInsteadOfBlockingForever() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lockURL = fixture.root.appendingPathComponent("contended.lock")

        // Simulate another process holding the exclusive flock.
        let descriptor = lockURL.path.withCString { path in
            Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX) == 0)
        defer { flock(descriptor, LOCK_UN) }

        let previousTimeout = PathProcessFileLock.acquireTimeout
        PathProcessFileLock.acquireTimeout = 0.3
        defer { PathProcessFileLock.acquireTimeout = previousTimeout }

        let lock = PathFileLockRegistry.shared.lock(for: lockURL)
        let started = Date()
        do {
            try lock.withExclusiveAccess {}
            Issue.record("A contended lock must fail instead of blocking forever.")
        } catch let error as POSIXError {
            #expect(error.code == .ETIMEDOUT)
        }
        #expect(Date().timeIntervalSince(started) < 3)
    }

    private struct InjectedFailure: Error {}

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TimeTrackerPathLockTests-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
