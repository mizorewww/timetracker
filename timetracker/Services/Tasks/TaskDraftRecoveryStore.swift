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
    nonisolated static let maximumEncodedByteCount = 1 * 1_024 * 1_024
    nonisolated static let defaultRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

    struct Locations {
        let directory: URL
        let durableRoot: URL
    }

    private let directoryURLOverride: URL?
    private let durableRootURLOverride: URL?
    private let retentionInterval: TimeInterval
    private let maximumEncodedByteCount: Int
    private let now: () -> Date
    private let fileManager: FileManager
    let localFile: DurableLocalFile
    private let commandLineArguments: [String]
    private let processIdentifier: Int32

    init(
        directoryURL: URL? = nil,
        durableRootURL: URL? = nil,
        retentionInterval: TimeInterval = Self.defaultRetentionInterval,
        maximumEncodedByteCount: Int = Self.maximumEncodedByteCount,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default,
        localFile: DurableLocalFile? = nil,
        commandLineArguments: [String] = CommandLine.arguments,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        precondition(retentionInterval >= 0)
        precondition(maximumEncodedByteCount > 0)
        self.directoryURLOverride = directoryURL
        self.durableRootURLOverride = durableRootURL
        self.retentionInterval = retentionInterval
        self.maximumEncodedByteCount = maximumEncodedByteCount
        self.now = now
        self.fileManager = fileManager
        self.localFile = localFile ?? DurableLocalFile(fileManager: fileManager)
        self.commandLineArguments = commandLineArguments
        self.processIdentifier = processIdentifier
    }

    func save(_ draft: TaskEditorDraft, for sourceTaskID: UUID) throws {
        guard draft.taskID == sourceTaskID, draft.baseline != nil else {
            throw TaskDraftRecoveryStoreError.invalidExistingTaskDraft
        }

        let envelope = TaskDraftRecoveryEnvelope(
            schemaVersion: Self.currentSchemaVersion,
            sourceTaskID: sourceTaskID,
            savedAt: now(),
            draft: draft
        )
        let data = try TaskDraftRecoveryCodec.encode(envelope)
        guard data.count <= maximumEncodedByteCount else {
            throw TaskDraftRecoveryStoreError.encodedDraftExceedsMaximumByteCount(
                actualByteCount: data.count,
                maximumByteCount: maximumEncodedByteCount
            )
        }

        let locations = try resolvedLocations()
        try localFile.write(
            data,
            to: fileURL(for: sourceTaskID, in: locations.directory),
            durableRootURL: locations.durableRoot,
            excludeFromBackup: true
        )
    }

    func load(
        for sourceTaskID: UUID,
        currentDraft: TaskEditorDraft
    ) throws -> TaskEditorDraft? {
        guard currentDraft.taskID == sourceTaskID,
              currentDraft.baseline != nil else {
            throw TaskDraftRecoveryStoreError.invalidExistingTaskDraft
        }
        let locations = try resolvedLocations()
        let url = fileURL(for: sourceTaskID, in: locations.directory)

        return try localFile.withExclusiveAccess(through: locations.durableRoot) {
            guard let envelope = try readEnvelope(
                at: url,
                locations: locations
            ) else { return nil }

            guard envelope.schemaVersion == Self.currentSchemaVersion,
                  envelope.sourceTaskID == sourceTaskID,
                  envelope.draft.taskID == sourceTaskID,
                  envelope.draft.baseline != nil,
                  isExpired(envelope.savedAt) == false,
                  TaskDraftRecoveryCodec.hasSameRecoverableContent(
                    envelope.draft,
                    currentDraft
                  ) == false else {
                try removeFile(at: url, locations: locations)
                return nil
            }
            return envelope.draft
        }
    }

    func remove(for sourceTaskID: UUID) throws {
        let locations = try resolvedLocations()
        let url = fileURL(for: sourceTaskID, in: locations.directory)
        guard fileManager.fileExists(atPath: locations.directory.path) else {
            return
        }
        try removeFile(at: url, locations: locations)
    }

    /// Removes expired, corrupt, unsupported, or task/file-mismatched entries.
    @discardableResult
    func removeExpired() throws -> Int {
        let locations = try resolvedLocations()
        guard fileManager.fileExists(atPath: locations.directory.path) else {
            return 0
        }

        return try localFile.withExclusiveAccess(through: locations.durableRoot) {
            let candidates = try localFile.managedDirectoryContents(
                at: locations.directory,
                durableRootURL: locations.durableRoot
            ).filter { $0.pathExtension == "json" }
            var removedCount = 0
            for url in candidates {
                let envelope = try readEnvelope(
                    at: url,
                    locations: locations
                )
                let expectedName = envelope.map {
                    fileName(for: $0.sourceTaskID)
                }
                guard let envelope else {
                    removedCount += 1
                    continue
                }
                let shouldRemove =
                    envelope.schemaVersion != Self.currentSchemaVersion ||
                    envelope.draft.taskID != envelope.sourceTaskID ||
                    envelope.draft.baseline == nil ||
                    expectedName != url.lastPathComponent ||
                    isExpired(envelope.savedAt)
                guard shouldRemove else { continue }
                try removeFile(at: url, locations: locations)
                removedCount += 1
            }
            return removedCount
        }
    }

    func fileURL(for sourceTaskID: UUID) throws -> URL {
        fileURL(for: sourceTaskID, in: try resolvedLocations().directory)
    }

    func resolvedLocations() throws -> Locations {
        if let directoryURLOverride {
            return Locations(
                directory: directoryURLOverride.standardizedFileURL,
                durableRoot: (
                    durableRootURLOverride ??
                        directoryURLOverride.deletingLastPathComponent()
                ).standardizedFileURL
            )
        }

        if commandLineArguments.contains("--uitesting") {
            let root = fileManager.temporaryDirectory.standardizedFileURL
            return Locations(
                directory: root.appendingPathComponent(
                    "\(Self.directoryName)-\(processIdentifier)",
                    isDirectory: true
                ),
                durableRoot: root
            )
        }

        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).standardizedFileURL
        return Locations(
            directory: root.appendingPathComponent(
                Self.directoryName,
                isDirectory: true
            ),
            durableRoot: root
        )
    }

    private func fileURL(for sourceTaskID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(
            fileName(for: sourceTaskID),
            isDirectory: false
        )
    }

    func fileName(for sourceTaskID: UUID) -> String {
        "\(sourceTaskID.uuidString.lowercased()).json"
    }

    func removeFile(at url: URL, locations: Locations) throws {
        try localFile.removeIfPresent(
            at: url,
            durableRootURL: locations.durableRoot
        )
    }

    func readEnvelope(
        at url: URL,
        locations: Locations
    ) throws -> TaskDraftRecoveryEnvelope? {
        let data: Data
        do {
            guard let value = try localFile.read(
                upTo: maximumEncodedByteCount,
                from: url,
                durableRootURL: locations.durableRoot
            ) else { return nil }
            data = value
        } catch let error as DurableLocalFileReadError {
            switch error {
            case .exceedsMaximumByteCount:
                try removeFile(at: url, locations: locations)
                return nil
            }
        }
        do {
            return try TaskDraftRecoveryCodec.decode(data)
        } catch is DecodingError {
            try removeFile(at: url, locations: locations)
            return nil
        }
    }

    func isExpired(_ savedAt: Date) -> Bool {
        now().timeIntervalSince(savedAt) > retentionInterval
    }
}
