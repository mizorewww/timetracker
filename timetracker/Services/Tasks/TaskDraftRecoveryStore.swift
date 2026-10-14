import Foundation

nonisolated enum TaskDraftRecoveryStoreError: Error, Equatable, Sendable {
    case invalidExistingTaskDraft
    case encodedDraftExceedsMaximumByteCount(
        actualByteCount: Int,
        maximumByteCount: Int
    )
}

/// A small, local-only crash/termination recovery store for existing task drafts.
///
/// Each source task owns one atomically replaced file. Recovery files are not a
/// second task database: callers must supply the current persisted draft before
/// a saved draft can be returned.
nonisolated struct TaskDraftRecoveryStore: @unchecked Sendable {
    nonisolated static let directoryName = "TimeTrackerDrafts"
    nonisolated static let currentSchemaVersion = 1
    nonisolated static let maximumEncodedByteCount = 1 * 1024 * 1024
    nonisolated static let defaultRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private let directoryURLOverride: URL?
    private let retentionInterval: TimeInterval
    private let maximumEncodedByteCount: Int
    private let now: () -> Date
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        retentionInterval: TimeInterval = Self.defaultRetentionInterval,
        maximumEncodedByteCount: Int = Self.maximumEncodedByteCount,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        directoryURLOverride = directoryURL
        self.retentionInterval = retentionInterval
        self.maximumEncodedByteCount = maximumEncodedByteCount
        self.now = now
        self.fileManager = fileManager
    }

    func save(_ draft: TaskEditorDraft, for sourceTaskID: UUID) throws {
        guard draft.taskID == sourceTaskID, draft.baseline != nil else {
            throw TaskDraftRecoveryStoreError.invalidExistingTaskDraft
        }
        let data = try TaskDraftRecoveryCodec.encode(
            TaskDraftRecoveryEnvelope(
                schemaVersion: Self.currentSchemaVersion,
                sourceTaskID: sourceTaskID,
                savedAt: now(),
                draft: draft
            )
        )
        guard data.count <= maximumEncodedByteCount else {
            throw TaskDraftRecoveryStoreError.encodedDraftExceedsMaximumByteCount(
                actualByteCount: data.count,
                maximumByteCount: maximumEncodedByteCount
            )
        }
        let directory = try directoryURL()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = fileURL(for: sourceTaskID, in: directory)
        try data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Returns the saved draft only if it is still valid and differs from what
    /// is persisted now; anything else is removed.
    func load(
        for sourceTaskID: UUID,
        currentDraft: TaskEditorDraft
    ) throws -> TaskEditorDraft? {
        guard currentDraft.taskID == sourceTaskID,
              currentDraft.baseline != nil
        else {
            throw TaskDraftRecoveryStoreError.invalidExistingTaskDraft
        }
        let url = try fileURL(for: sourceTaskID, in: directoryURL())
        guard let envelope = try readEnvelope(at: url) else { return nil }
        guard isRecoverable(envelope, fileName: url.lastPathComponent),
              TaskDraftRecoveryCodec.hasSameRecoverableContent(envelope.draft, currentDraft) == false
        else {
            try removeFile(at: url)
            return nil
        }
        return envelope.draft
    }

    func remove(for sourceTaskID: UUID) throws {
        try removeFile(at: fileURL(for: sourceTaskID, in: directoryURL()))
    }

    /// Removes expired, corrupt, unsupported, or task/file-mismatched entries.
    @discardableResult
    func removeExpired() throws -> Int {
        let directory = try directoryURL()
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        var removedCount = 0
        for url in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json"
        {
            guard let envelope = try readEnvelope(at: url) else {
                removedCount += 1
                continue
            }
            guard isRecoverable(envelope, fileName: url.lastPathComponent) == false else { continue }
            try removeFile(at: url)
            removedCount += 1
        }
        return removedCount
    }

    func fileURL(for sourceTaskID: UUID) throws -> URL {
        try fileURL(for: sourceTaskID, in: directoryURL())
    }

    private func directoryURL() throws -> URL {
        if let directoryURLOverride {
            return directoryURLOverride
        }
        if AppRuntimeEnvironment.isUITesting {
            return fileManager.temporaryDirectory.appendingPathComponent(
                "\(Self.directoryName)-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    private func fileURL(for sourceTaskID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(
            "\(sourceTaskID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func removeFile(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
    }

    /// Reads an envelope; oversized or undecodable files are removed and
    /// treated as absent.
    private func readEnvelope(at url: URL) throws -> TaskDraftRecoveryEnvelope? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        guard size <= maximumEncodedByteCount,
              let envelope = try? TaskDraftRecoveryCodec.decode(Data(contentsOf: url))
        else {
            try removeFile(at: url)
            return nil
        }
        return envelope
    }

    private func isRecoverable(_ envelope: TaskDraftRecoveryEnvelope, fileName: String) -> Bool {
        envelope.schemaVersion == Self.currentSchemaVersion &&
            envelope.draft.taskID == envelope.sourceTaskID &&
            envelope.draft.baseline != nil &&
            fileName == "\(envelope.sourceTaskID.uuidString.lowercased()).json" &&
            now().timeIntervalSince(envelope.savedAt) <= retentionInterval
    }
}
