import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDurableLocalFileTests {
    @Test
    func firstWriteCreatesNestedDirectoryAndPersistsData() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let one = fixture.root.appendingPathComponent("one", isDirectory: true)
        let two = one.appendingPathComponent("two", isDirectory: true)
        let leaf = two.appendingPathComponent("three", isDirectory: true)
        let url = leaf.appendingPathComponent("payload.json")
        let payload = Data("durable".utf8)
        let probe = DirectorySyncProbe()

        try DurableLocalFile(directorySynchronizer: probe.synchronize)
            .write(payload, to: url, durableRootURL: fixture.root)

        #expect(try Data(contentsOf: url) == payload)
        #expect(
            probe.paths
                == [leaf, two, one, fixture.root, leaf].map(\.standardizedFileURL)
        )
    }

    @Test
    func retryAfterDirectoryCreationFaultRepairsExistingAncestry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let parent = fixture.root.appendingPathComponent("new-parent", isDirectory: true)
        let leaf = parent.appendingPathComponent("child", isDirectory: true)
        let url = leaf.appendingPathComponent("payload.json")
        let interruptedProbe = DirectorySyncProbe()
        let failingFile = DurableLocalFile(
            directorySynchronizer: interruptedProbe.synchronize,
            injectFault: { point in
                if point == .afterDirectoryCreationBeforeParentSync {
                    throw InjectedFailure()
                }
            }
        )

        #expect(throws: InjectedFailure.self) {
            try failingFile.write(
                Data("first".utf8),
                to: url,
                durableRootURL: fixture.root
            )
        }
        #expect(interruptedProbe.paths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: leaf.path))
        #expect(FileManager.default.fileExists(atPath: url.path) == false)

        let retryProbe = DirectorySyncProbe()
        try DurableLocalFile(directorySynchronizer: retryProbe.synchronize)
            .write(Data("second".utf8), to: url, durableRootURL: fixture.root)

        #expect(
            retryProbe.paths
                == [leaf, parent, fixture.root, leaf].map(\.standardizedFileURL)
        )
        #expect(try String(contentsOf: url, encoding: .utf8) == "second")
    }

    @Test
    func explicitDurableRootMustBeAnExistingAncestor() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = fixture.root.appendingPathComponent("target/child", isDirectory: true)
        let unrelated = fixture.root.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        let url = target.appendingPathComponent("payload.json")

        #expect(throws: DurableLocalFileError.durableRootIsNotAncestor) {
            try DurableLocalFile().write(
                Data("invalid".utf8),
                to: url,
                durableRootURL: unrelated
            )
        }
        #expect(FileManager.default.fileExists(atPath: target.path) == false)

        let missingRoot = fixture.root.appendingPathComponent("missing", isDirectory: true)
        #expect(throws: DurableLocalFileError.durableRootUnavailable) {
            try DurableLocalFile().write(
                Data("invalid".utf8),
                to: missingRoot.appendingPathComponent("payload.json"),
                durableRootURL: missingRoot
            )
        }
    }

    @Test
    func faultBeforePublishPreservesCanonicalDataAndRemovesTemporaryFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("old".utf8), to: url)
        let failingFile = DurableLocalFile(injectFault: { point in
            if point == .afterAtomicWriteBeforeFileSync {
                throw InjectedFailure()
            }
        })

        #expect(throws: InjectedFailure.self) {
            try failingFile.write(Data("new".utf8), to: url)
        }

        #expect(try String(contentsOf: url, encoding: .utf8) == "old")
        let temporaryFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".TimeTrackerWrite-") }
        #expect(temporaryFiles.isEmpty)
    }

    @Test
    func nextWriteRemovesTemporaryFileLeftByAnInterruptedProcess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let staleTemporaryURL = fixture.root.appendingPathComponent(
            ".TimeTrackerWrite-00000000-0000-0000-0000-000000000000.tmp"
        )
        try Data("stale".utf8).write(to: staleTemporaryURL)
        let canonicalURL = fixture.root.appendingPathComponent("payload.json")

        try DurableLocalFile().write(Data("new".utf8), to: canonicalURL)

        #expect(FileManager.default.fileExists(atPath: staleTemporaryURL.path) == false)
        #expect(try String(contentsOf: canonicalURL, encoding: .utf8) == "new")
    }

    @Test
    func managedPathRejectsDirectoriesWithoutRemovingTheirContents() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directoryURL = fixture.root.appendingPathComponent("payload.json", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sentinelURL = directoryURL.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinelURL)
        let file = DurableLocalFile()

        #expect(throws: DurableLocalFileError.managedPathIsNotRegularFile) {
            try file.write(Data("replace".utf8), to: directoryURL)
        }
        #expect(throws: DurableLocalFileError.managedPathIsNotRegularFile) {
            try file.removeIfPresent(at: directoryURL)
        }
        #expect(throws: DurableLocalFileError.managedPathIsNotRegularFile) {
            try file.quarantineIfPresent(at: directoryURL, prefix: "payload.corrupt-")
        }
        #expect(try String(contentsOf: sentinelURL, encoding: .utf8) == "keep")
    }

    @Test
    func reservedRootLockPathFailsClosedForEveryMutation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lockURL = fixture.root.appendingPathComponent(DurableLocalFile.lockFileName)
        let file = DurableLocalFile()

        #expect(throws: DurableLocalFileError.reservedLockPath) {
            try file.write(Data("replace".utf8), to: lockURL, durableRootURL: fixture.root)
        }
        #expect(throws: DurableLocalFileError.reservedLockPath) {
            try file.removeIfPresent(at: lockURL, durableRootURL: fixture.root)
        }
        #expect(throws: DurableLocalFileError.reservedLockPath) {
            try file.quarantineIfPresent(
                at: lockURL,
                prefix: "lock.corrupt-",
                durableRootURL: fixture.root
            )
        }
    }

    #if os(iOS)
    @Test
    func writeAppliesProtectionBeforePublishingTheFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("protected.json")

        try DurableLocalFile().write(Data("secret".utf8), to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(
            attributes[.protectionKey] as? FileProtectionType
                == .completeUntilFirstUserAuthentication
        )
    }
    #endif

    private struct InjectedFailure: Error {}

    private final class DirectorySyncProbe {
        private(set) var paths: [URL] = []

        func synchronize(_ url: URL) {
            paths.append(url.standardizedFileURL)
        }
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TimeTrackerDurableFileTests-\(UUID().uuidString)",
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
