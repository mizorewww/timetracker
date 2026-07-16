import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDurableLocalFileQuarantineTests {
    @Test
    func quarantineMovesCanonicalArtifactIntoDedicatedDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        let file = DurableLocalFile()
        try file.write(Data("broken".utf8), to: url)

        let quarantined = try file.quarantineIfPresent(
            at: url,
            prefix: "payload.corrupt-"
        )
        let quarantineURL = try #require(quarantined)
        try file.write(Data("valid".utf8), to: url)

        #expect(quarantineURL.deletingLastPathComponent().lastPathComponent == quarantineName)
        #expect(try String(contentsOf: quarantineURL, encoding: .utf8) == "broken")
        #expect(try String(contentsOf: url, encoding: .utf8) == "valid")
    }

    @Test
    func quarantineCountBudgetAppliesAcrossDiagnosticPrefixes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = MutableDate(Date(timeIntervalSinceReferenceDate: 10_000))
        let file = DurableLocalFile(
            quarantinePolicy: .init(
                maximumFileCount: 2,
                maximumTotalByteCount: 1_024,
                maximumAge: 1_000
            ),
            dateProvider: { clock.value }
        )

        let first = try quarantine(
            Data("one".utf8),
            named: "one.json",
            prefix: "one.corrupt-",
            with: file,
            in: fixture
        )
        clock.value.addTimeInterval(1)
        let second = try quarantine(
            Data("two".utf8),
            named: "two.json",
            prefix: "two.ambiguous-",
            with: file,
            in: fixture
        )
        clock.value.addTimeInterval(1)
        let third = try quarantine(
            Data("three".utf8),
            named: "three.json",
            prefix: "three.corrupt-",
            with: file,
            in: fixture
        )

        #expect(FileManager.default.fileExists(atPath: first.path) == false)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: third.path))
        #expect(try quarantineEntries(in: fixture).count == 2)
    }

    @Test
    func quarantinePrunesExpiredAndImplausiblyFutureDiagnostics() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = MutableDate(Date(timeIntervalSinceReferenceDate: 20_000))
        let file = DurableLocalFile(
            quarantinePolicy: .init(
                maximumFileCount: 8,
                maximumTotalByteCount: 1_024,
                maximumAge: 100
            ),
            dateProvider: { clock.value }
        )
        let expired = try quarantine(
            Data("old".utf8),
            named: "old.json",
            prefix: "old.corrupt-",
            with: file,
            in: fixture
        )
        let future = quarantineDirectory(in: fixture).appendingPathComponent("future.json")
        try Data("future".utf8).write(to: future)
        try FileManager.default.setAttributes(
            [.modificationDate: clock.value.addingTimeInterval(1_000)],
            ofItemAtPath: future.path
        )
        clock.value.addTimeInterval(101)
        let current = try quarantine(
            Data("current".utf8),
            named: "current.json",
            prefix: "current.corrupt-",
            with: file,
            in: fixture
        )

        #expect(FileManager.default.fileExists(atPath: expired.path) == false)
        #expect(FileManager.default.fileExists(atPath: future.path) == false)
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(try quarantineEntries(in: fixture).count == 1)
    }

    @Test
    func quarantineEnforcesTotalBytesAndDoesNotRetainOversizedCandidate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = MutableDate(Date(timeIntervalSinceReferenceDate: 30_000))
        let file = DurableLocalFile(
            quarantinePolicy: .init(
                maximumFileCount: 4,
                maximumTotalByteCount: 6,
                maximumAge: 1_000
            ),
            dateProvider: { clock.value }
        )
        let first = try quarantine(
            Data("1234".utf8),
            named: "first.json",
            prefix: "first.corrupt-",
            with: file,
            in: fixture
        )
        clock.value.addTimeInterval(1)
        let second = try quarantine(
            Data("5678".utf8),
            named: "second.json",
            prefix: "second.corrupt-",
            with: file,
            in: fixture
        )
        let oversizedURL = fixture.root.appendingPathComponent("oversized.json")
        try file.write(Data("1234567".utf8), to: oversizedURL)
        clock.value.addTimeInterval(1)
        let oversizedResult = try file.quarantineIfPresent(
            at: oversizedURL,
            prefix: "oversized.corrupt-"
        )

        #expect(FileManager.default.fileExists(atPath: first.path) == false)
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(oversizedResult == nil)
        #expect(FileManager.default.fileExists(atPath: oversizedURL.path) == false)
        let entries = try quarantineEntries(in: fixture)
        #expect(entries == [second])
        let totalByteCount = try entries.reduce(Int64(0)) { partialResult, url in
            partialResult + (try fileSize(at: url))
        }
        #expect(totalByteCount <= 6)
    }

    @Test
    func quarantineFailureBeforeMoveLeavesCanonicalArtifactInPlace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("broken".utf8), to: url)
        let failingFile = DurableLocalFile(injectFault: { point in
            if point == .beforeQuarantinePruning {
                throw InjectedFailure()
            }
        })

        #expect(throws: InjectedFailure.self) {
            try failingFile.quarantineIfPresent(at: url, prefix: "payload.corrupt-")
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "broken")
        #expect(try quarantineEntries(in: fixture).isEmpty)
    }

    @Test
    func quarantineFailureAfterMoveRollsCanonicalArtifactBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("broken".utf8), to: url)
        let failingFile = DurableLocalFile(injectFault: { point in
            if point == .afterQuarantineMoveBeforeFileSync {
                throw InjectedFailure()
            }
        })

        #expect(throws: InjectedFailure.self) {
            try failingFile.quarantineIfPresent(at: url, prefix: "payload.corrupt-")
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "broken")
        #expect(try quarantineEntries(in: fixture).isEmpty)
    }

    @Test
    func quarantineReportsBothPathsWhenRollbackCannotRestoreCanonicalFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("broken".utf8), to: url)
        let failingFile = DurableLocalFile(injectFault: { point in
            guard point == .afterQuarantineMoveBeforeFileSync else { return }
            try Data("replacement".utf8).write(to: url)
            throw InjectedFailure()
        })

        do {
            _ = try failingFile.quarantineIfPresent(
                at: url,
                prefix: "payload.corrupt-"
            )
            Issue.record("Expected rollback failure")
        } catch let error as DurableLocalFileError {
            guard case let .quarantineRollbackFailed(canonicalPath, quarantinePath) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(canonicalPath == url.path)
            #expect(quarantinePath.contains(".TimeTrackerQuarantine"))
            #expect(FileManager.default.fileExists(atPath: quarantinePath))
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "replacement")
    }

    @Test
    func quarantineRejectsASymbolicLinkDirectoryWithoutTouchingItsTarget() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let externalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TimeTrackerQuarantineEscape-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        try FileManager.default.createDirectory(
            at: externalDirectory,
            withIntermediateDirectories: true
        )
        let sentinel = externalDirectory.appendingPathComponent("sentinel.json")
        try Data("keep".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: quarantineDirectory(in: fixture),
            withDestinationURL: externalDirectory
        )
        let canonical = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("broken".utf8), to: canonical)

        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().quarantineIfPresent(
                at: canonical,
                prefix: "payload.corrupt-"
            )
        }
        #expect(try String(contentsOf: canonical, encoding: .utf8) == "broken")
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
    }

    @Test
    func quarantineRejectsDanglingCanonicalSymbolicLink() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let canonical = fixture.root.appendingPathComponent("payload.json")
        let missingTarget = fixture.root.appendingPathComponent("missing.json")
        try FileManager.default.createSymbolicLink(
            at: canonical,
            withDestinationURL: missingTarget
        )

        #expect(throws: DurableLocalFileError.symbolicLinkNotAllowed) {
            try DurableLocalFile().quarantineIfPresent(
                at: canonical,
                prefix: "payload.corrupt-"
            )
        }
    }

    @Test
    func invalidQuarantinePrefixFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("broken".utf8), to: url)

        #expect(throws: DurableLocalFileError.invalidQuarantinePrefix) {
            try DurableLocalFile().quarantineIfPresent(
                at: url,
                prefix: "../outside-"
            )
        }
        #expect(throws: DurableLocalFileError.invalidQuarantinePrefix) {
            try DurableLocalFile().quarantineIfPresent(
                at: url,
                prefix: String(repeating: "x", count: 129)
            )
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private func quarantine(
        _ data: Data,
        named name: String,
        prefix: String,
        with file: DurableLocalFile,
        in fixture: Fixture
    ) throws -> URL {
        let url = fixture.root.appendingPathComponent(name)
        try file.write(data, to: url)
        let quarantined = try file.quarantineIfPresent(at: url, prefix: prefix)
        return try #require(quarantined)
    }

    private func quarantineEntries(in fixture: Fixture) throws -> [URL] {
        let directory = quarantineDirectory(in: fixture)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantineDirectory(in fixture: Fixture) -> URL {
        fixture.root.appendingPathComponent(quarantineName, isDirectory: true)
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (try #require(attributes[.size] as? NSNumber)).int64Value
    }

    private var quarantineName: String { ".TimeTrackerQuarantine" }

    private struct InjectedFailure: Error {}

    private final class MutableDate {
        var value: Date

        init(_ value: Date) {
            self.value = value
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
