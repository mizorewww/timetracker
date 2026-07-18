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
                == [leaf, two, one, fixture.root, leaf].map {
                    CanonicalFileURL.resolvingExistingAncestor(of: $0)
                }
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
                == [leaf, parent, fixture.root, leaf].map {
                    CanonicalFileURL.resolvingExistingAncestor(of: $0)
                }
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

    @Test
    func mutationsAllowASymbolicLinkOnlyAboveTheDurableRoot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let physicalParent = fixture.root.appendingPathComponent(
            "physical",
            isDirectory: true
        )
        let physicalRoot = physicalParent.appendingPathComponent(
            "managed",
            isDirectory: true
        )
        let aliasParent = fixture.root.appendingPathComponent(
            "alias",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: physicalRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasParent,
            withDestinationURL: physicalParent
        )
        let aliasRoot = aliasParent.appendingPathComponent(
            "managed",
            isDirectory: true
        )
        let aliasURL = aliasRoot.appendingPathComponent("payload.json")

        try DurableLocalFile().write(
            Data("durable".utf8),
            to: aliasURL,
            durableRootURL: aliasRoot
        )

        let physicalURL = physicalRoot.appendingPathComponent("payload.json")
        #expect(try String(contentsOf: physicalURL, encoding: .utf8) == "durable")

        try DurableLocalFile().removeIfPresent(
            at: aliasURL,
            durableRootURL: aliasRoot
        )
        #expect(FileManager.default.fileExists(atPath: physicalURL.path) == false)

        try DurableLocalFile().write(
            Data("quarantine".utf8),
            to: aliasURL,
            durableRootURL: aliasRoot
        )
        let quarantined = try DurableLocalFile().quarantineIfPresent(
            at: aliasURL,
            prefix: "payload.corrupt-",
            durableRootURL: aliasRoot
        )
        let quarantineURL = try #require(quarantined)
        #expect(try String(contentsOf: quarantineURL, encoding: .utf8) == "quarantine")
        #expect(FileManager.default.fileExists(atPath: physicalURL.path) == false)
    }

    @Test
    func mutationsStillRejectASymbolicLinkAtTheDurableRoot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let physicalRoot = fixture.root.appendingPathComponent(
            "physical",
            isDirectory: true
        )
        let aliasRoot = fixture.root.appendingPathComponent(
            "alias",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: physicalRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: aliasRoot,
            withDestinationURL: physicalRoot
        )

        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().write(
                Data("blocked".utf8),
                to: aliasRoot.appendingPathComponent("payload.json"),
                durableRootURL: aliasRoot
            )
        }
        let physicalURL = physicalRoot.appendingPathComponent("payload.json")
        try Data("keep".utf8).write(to: physicalURL)
        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().removeIfPresent(
                at: aliasRoot.appendingPathComponent("payload.json"),
                durableRootURL: aliasRoot
            )
        }
        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().quarantineIfPresent(
                at: aliasRoot.appendingPathComponent("payload.json"),
                prefix: "payload.corrupt-",
                durableRootURL: aliasRoot
            )
        }
        #expect(try String(contentsOf: physicalURL, encoding: .utf8) == "keep")

        let danglingRoot = fixture.root.appendingPathComponent(
            "dangling",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: danglingRoot,
            withDestinationURL: fixture.root.appendingPathComponent("missing")
        )
        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().write(
                Data("blocked".utf8),
                to: danglingRoot.appendingPathComponent("payload.json"),
                durableRootURL: danglingRoot
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
