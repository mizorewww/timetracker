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
