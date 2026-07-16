import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDurableLocalFileLockingTests {
    @Test
    func writeAndQuarantineShareTheDurableRootLock() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("payload.json")
        try DurableLocalFile().write(Data("old".utf8), to: url)
        let writerEntered = DispatchSemaphore(value: 0)
        let releaseWriter = DispatchSemaphore(value: 0)
        let writerFinished = DispatchSemaphore(value: 0)
        let quarantineAttempting = DispatchSemaphore(value: 0)
        let quarantineEntered = DispatchSemaphore(value: 0)
        let quarantineFinished = DispatchSemaphore(value: 0)
        let writer = DurableLocalFile(injectFault: { point in
            guard point == .afterAtomicWriteBeforeFileSync else { return }
            writerEntered.signal()
            releaseWriter.wait()
        })
        let quarantiner = DurableLocalFile(injectFault: { point in
            if point == .beforeQuarantinePruning { quarantineEntered.signal() }
        })

        DispatchQueue.global().async {
            try? writer.write(
                Data("new".utf8),
                to: url,
                durableRootURL: fixture.root
            )
            writerFinished.signal()
        }
        #expect(writerEntered.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global().async {
            quarantineAttempting.signal()
            _ = try? quarantiner.quarantineIfPresent(
                at: url,
                prefix: "payload.corrupt-",
                durableRootURL: fixture.root
            )
            quarantineFinished.signal()
        }
        #expect(quarantineAttempting.wait(timeout: .now() + 2) == .success)
        #expect(quarantineEntered.wait(timeout: .now() + 0.05) == .timedOut)

        releaseWriter.signal()
        #expect(writerFinished.wait(timeout: .now() + 2) == .success)
        #expect(quarantineEntered.wait(timeout: .now() + 2) == .success)
        #expect(quarantineFinished.wait(timeout: .now() + 2) == .success)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        let entry = try #require(quarantineEntries(in: fixture).first)
        #expect(try String(contentsOf: entry, encoding: .utf8) == "new")
    }

    private func quarantineEntries(in fixture: Fixture) throws -> [URL] {
        let directory = fixture.root.appendingPathComponent(
            ".TimeTrackerQuarantine",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TimeTrackerDurableFileLockingTests-\(UUID().uuidString)",
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
