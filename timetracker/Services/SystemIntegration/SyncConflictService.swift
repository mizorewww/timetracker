import CloudKit
import CoreData
import CryptoKit
import Foundation
import SwiftData

@MainActor
struct SyncConflictService {
    private static let stateFileName = "SyncConflictState.json"
    private static let stateDirectoryName = "TimeTrackerSync"
    private let stateURLOverride: URL?

    init(stateURL: URL? = nil) {
        self.stateURLOverride = stateURL
    }

    func bootstrap(context: ModelContext) throws -> SyncConflictPrompt? {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return nil }
        var state = try loadState()
        if let prompt = prompt(from: state) {
            return prompt
        }
        guard state.localSnapshot == nil else { return nil }

        let snapshot = try SyncDataSnapshot.capture(context: context)
        state.localSnapshot = snapshot
        state.localFingerprint = try snapshot.fingerprint()
        if !snapshot.hasProtectableUserContent {
            state.baseFingerprint = state.localFingerprint
        }
        try saveState(state)
        return nil
    }

    func recordLocalMutation(context: ModelContext) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return }
        var state = try loadState()
        guard state.pendingConflictID == nil else { return }
        let snapshot = try SyncDataSnapshot.capture(context: context)
        state.localSnapshot = snapshot
        state.localFingerprint = try snapshot.fingerprint()
        try saveState(state)
    }

    func handleCloudImport(context: ModelContext) throws -> SyncConflictPrompt? {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return nil }
        var state = try loadState()
        if let prompt = prompt(from: state) {
            return prompt
        }

        let cloudSnapshot = try SyncDataSnapshot.capture(context: context)
        let cloudFingerprint = try cloudSnapshot.fingerprint()
        guard let localSnapshot = state.localSnapshot,
              let localFingerprint = state.localFingerprint else {
            state.localSnapshot = cloudSnapshot
            state.localFingerprint = cloudFingerprint
            state.baseFingerprint = cloudFingerprint
            try saveState(state)
            return nil
        }

        if cloudFingerprint == localFingerprint {
            state.baseFingerprint = cloudFingerprint
            state.pendingCloudSnapshot = nil
            try saveState(state)
            return nil
        }

        if let baseFingerprint = state.baseFingerprint {
            if localFingerprint == baseFingerprint {
                state.localSnapshot = cloudSnapshot
                state.localFingerprint = cloudFingerprint
                state.baseFingerprint = cloudFingerprint
                try saveState(state)
                return nil
            }

            if cloudFingerprint != baseFingerprint {
                return try saveConflict(
                    localSnapshot: localSnapshot,
                    cloudSnapshot: cloudSnapshot,
                    state: &state
                )
            }
        } else if localSnapshot.hasProtectableUserContent {
            return try saveConflict(
                localSnapshot: localSnapshot,
                cloudSnapshot: cloudSnapshot,
                state: &state
            )
        } else {
            state.localSnapshot = cloudSnapshot
            state.localFingerprint = cloudFingerprint
            state.baseFingerprint = cloudFingerprint
            try saveState(state)
        }

        return nil
    }

    func markCloudExportAccepted(context: ModelContext) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return }
        var state = try loadState()
        guard state.pendingConflictID == nil else { return }
        let snapshot = try SyncDataSnapshot.capture(context: context)
        let fingerprint = try snapshot.fingerprint()
        state.localSnapshot = snapshot
        state.localFingerprint = fingerprint
        state.baseFingerprint = fingerprint
        try saveState(state)
    }

    func forceUploadLocalData(context: ModelContext) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else {
            throw SyncConflictError.cloudSyncUnavailable
        }
        var state = try loadState()
        let snapshot = try SyncDataSnapshot.capture(context: context)
        try snapshot.restoreAsLocalWinner(context: context)
        let exportedSnapshot = try SyncDataSnapshot.capture(context: context)
        let fingerprint = try exportedSnapshot.fingerprint()
        state.baseFingerprint = fingerprint
        state.localSnapshot = exportedSnapshot
        state.localFingerprint = fingerprint
        state.pendingConflictID = nil
        state.pendingDetectedAt = nil
        state.pendingCloudSnapshot = nil
        try saveState(state)
    }

    func acceptCurrentCloudData(context: ModelContext) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else {
            throw SyncConflictError.cloudSyncUnavailable
        }
        var state = try loadState()
        let snapshot = try SyncDataSnapshot.capture(context: context)
        let fingerprint = try snapshot.fingerprint()
        state.baseFingerprint = fingerprint
        state.localSnapshot = snapshot
        state.localFingerprint = fingerprint
        state.pendingConflictID = nil
        state.pendingDetectedAt = nil
        state.pendingCloudSnapshot = nil
        try saveState(state)
    }

    func resolve(_ resolution: SyncConflictResolution, context: ModelContext) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else { return }
        var state = try loadState()
        switch resolution {
        case .uploadLocal:
            guard let localSnapshot = state.localSnapshot else {
                throw SyncConflictError.localSnapshotMissing
            }
            try localSnapshot.restoreAsLocalWinner(context: context)
            let resolvedSnapshot = try SyncDataSnapshot.capture(context: context)
            let fingerprint = try resolvedSnapshot.fingerprint()
            state.localSnapshot = resolvedSnapshot
            state.localFingerprint = fingerprint
            state.baseFingerprint = fingerprint
        case .downloadCloud:
            let cloudSnapshot = try SyncDataSnapshot.capture(context: context)
            let fingerprint = try cloudSnapshot.fingerprint()
            state.localSnapshot = cloudSnapshot
            state.localFingerprint = fingerprint
            state.baseFingerprint = fingerprint
        }
        state.pendingConflictID = nil
        state.pendingDetectedAt = nil
        state.pendingCloudSnapshot = nil
        try saveState(state)
    }

    func prompt() -> SyncConflictPrompt? {
        guard let state = try? loadState() else { return nil }
        return prompt(from: state)
    }

    nonisolated static func isConflictLikeCloudError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           CKError.Code(rawValue: nsError.code) == .serverRecordChanged {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSPersistentStoreSaveConflictsError {
            return true
        }
        return nsError.localizedDescription.localizedCaseInsensitiveContains("conflict")
    }

    private func saveConflict(
        localSnapshot: SyncDataSnapshot,
        cloudSnapshot: SyncDataSnapshot,
        state: inout SyncConflictState
    ) throws -> SyncConflictPrompt {
        let conflictID = UUID()
        let detectedAt = Date()
        state.pendingConflictID = conflictID
        state.pendingDetectedAt = detectedAt
        state.pendingCloudSnapshot = cloudSnapshot
        try saveState(state)
        return SyncConflictPrompt(
            id: conflictID,
            detectedAt: detectedAt,
            localSummary: localSnapshot.localizedSummary,
            cloudSummary: cloudSnapshot.localizedSummary
        )
    }

    private func prompt(from state: SyncConflictState) -> SyncConflictPrompt? {
        guard let id = state.pendingConflictID,
              let detectedAt = state.pendingDetectedAt,
              let localSnapshot = state.localSnapshot,
              let cloudSnapshot = state.pendingCloudSnapshot else {
            return nil
        }
        return SyncConflictPrompt(
            id: id,
            detectedAt: detectedAt,
            localSummary: localSnapshot.localizedSummary,
            cloudSummary: cloudSnapshot.localizedSummary
        )
    }

    private func loadState() throws -> SyncConflictState {
        let url = try stateURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SyncConflictState()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SyncConflictState.self, from: data)
    }

    private func saveState(_ state: SyncConflictState) throws {
        let url = try stateURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }

    private func stateURL() throws -> URL {
        if let stateURLOverride {
            return stateURLOverride
        }
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL
            .appendingPathComponent(Self.stateDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.stateFileName)
    }
}

private enum SyncConflictError: LocalizedError {
    case localSnapshotMissing
    case cloudSyncUnavailable

    var errorDescription: String? {
        switch self {
        case .localSnapshotMissing:
            return AppStrings.localized("sync.conflict.error.localSnapshotMissing")
        case .cloudSyncUnavailable:
            return AppStrings.localized("sync.conflict.error.cloudUnavailable")
        }
    }
}

private struct SyncConflictState: Codable {
    var baseFingerprint: String?
    var localSnapshot: SyncDataSnapshot?
    var localFingerprint: String?
    var pendingConflictID: UUID?
    var pendingDetectedAt: Date?
    var pendingCloudSnapshot: SyncDataSnapshot?
}

private struct SyncDataSnapshot: Codable, Equatable {
    var tasks: [TaskRecord] = []
    var taskCategories: [TaskCategoryRecord] = []
    var taskCategoryAssignments: [TaskCategoryAssignmentRecord] = []
    var sessions: [TimeSessionRecord] = []
    var segments: [TimeSegmentRecord] = []
    var pomodoroRuns: [PomodoroRunRecord] = []
    var countdownEvents: [CountdownEventRecord] = []
    var syncedPreferences: [SyncedPreferenceRecord] = []
    var checklistItems: [ChecklistItemRecord] = []
    var checklistItemVisuals: [ChecklistItemVisualRecord] = []
    var inboxItems: [InboxItemRecord] = []
    var inboxSuggestions: [InboxSuggestionRecord] = []

    var hasProtectableUserContent: Bool {
        !tasks.isEmpty ||
        !taskCategories.isEmpty ||
        !sessions.isEmpty ||
        !segments.isEmpty ||
        !pomodoroRuns.isEmpty ||
        !countdownEvents.isEmpty ||
        !checklistItems.isEmpty ||
        !checklistItemVisuals.isEmpty ||
        !inboxItems.isEmpty ||
        !inboxSuggestions.isEmpty
    }

    var localizedSummary: String {
        String(
            format: AppStrings.localized("sync.conflict.summary"),
            tasks.filter { $0.deletedAt == nil }.count,
            segments.filter { $0.deletedAt == nil }.count,
            pomodoroRuns.filter { $0.deletedAt == nil }.count,
            checklistItems.filter { $0.deletedAt == nil }.count,
            inboxItems.filter { $0.deletedAt == nil }.count
        )
    }

    @MainActor
    static func capture(context: ModelContext) throws -> SyncDataSnapshot {
        SyncDataSnapshot(
            tasks: try context.fetch(FetchDescriptor<TaskNode>()).map(TaskRecord.init).sortedByID(),
            taskCategories: try context.fetch(FetchDescriptor<TaskCategory>()).map(TaskCategoryRecord.init).sortedByID(),
            taskCategoryAssignments: try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(TaskCategoryAssignmentRecord.init).sortedByID(),
            sessions: try context.fetch(FetchDescriptor<TimeSession>()).map(TimeSessionRecord.init).sortedByID(),
            segments: try context.fetch(FetchDescriptor<TimeSegment>()).map(TimeSegmentRecord.init).sortedByID(),
            pomodoroRuns: try context.fetch(FetchDescriptor<PomodoroRun>()).map(PomodoroRunRecord.init).sortedByID(),
            countdownEvents: try context.fetch(FetchDescriptor<CountdownEvent>()).map(CountdownEventRecord.init).sortedByID(),
            syncedPreferences: try context.fetch(FetchDescriptor<SyncedPreference>()).map(SyncedPreferenceRecord.init).sortedByID(),
            checklistItems: try context.fetch(FetchDescriptor<ChecklistItem>()).map(ChecklistItemRecord.init).sortedByID(),
            checklistItemVisuals: try context.fetch(FetchDescriptor<ChecklistItemVisual>()).map(ChecklistItemVisualRecord.init).sortedByID(),
            inboxItems: try context.fetch(FetchDescriptor<InboxItem>()).map(InboxItemRecord.init).sortedByID(),
            inboxSuggestions: try context.fetch(FetchDescriptor<InboxSuggestion>()).map(InboxSuggestionRecord.init).sortedByID()
        )
    }

    func fingerprint() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func restoreAsLocalWinner(context: ModelContext, now: Date = Date()) throws {
        let deviceID = DeviceIdentity.current
        try restoreTasks(context: context, now: now, deviceID: deviceID)
        try restoreTaskCategories(context: context, now: now, deviceID: deviceID)
        try restoreTaskCategoryAssignments(context: context, now: now, deviceID: deviceID)
        try restoreSessions(context: context, now: now, deviceID: deviceID)
        try restoreSegments(context: context, now: now, deviceID: deviceID)
        try restorePomodoroRuns(context: context, now: now, deviceID: deviceID)
        try restoreCountdownEvents(context: context, now: now, deviceID: deviceID)
        try restoreSyncedPreferences(context: context, now: now, deviceID: deviceID)
        try restoreChecklistItems(context: context, now: now, deviceID: deviceID)
        try restoreChecklistItemVisuals(context: context, now: now, deviceID: deviceID)
        try restoreInboxItems(context: context, now: now, deviceID: deviceID)
        try restoreInboxSuggestions(context: context, now: now, deviceID: deviceID)
        try context.save()
    }

    private func restoreTasks(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskNode>()).map { ($0.id, $0) })
        for task in existing.values where !tasks.map(\.id).contains(task.id) {
            task.deletedAt = now
            task.updatedAt = now
            task.deviceID = deviceID
            task.clientMutationID = UUID()
        }
        for record in tasks {
            let model = existing[record.id] ?? TaskNode(title: record.title, parentID: record.parentID, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.kindRaw = record.kindRaw
            model.parentID = record.parentID
            model.sortOrder = record.sortOrder
            model.path = record.path
            model.depth = record.depth
            model.statusRaw = record.statusRaw
            model.colorHex = record.colorHex
            model.iconName = record.iconName
            model.estimatedSeconds = record.estimatedSeconds
            model.dueAt = record.dueAt
            model.notes = record.notes
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.archivedAt = record.archivedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreTaskCategories(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskCategory>()).map { ($0.id, $0) })
        let snapshotIDs = Set(taskCategories.map(\.id))
        for category in existing.values where !snapshotIDs.contains(category.id) {
            category.deletedAt = now
            category.updatedAt = now
            category.deviceID = deviceID
            category.clientMutationID = UUID()
        }
        for record in taskCategories {
            let model = existing[record.id] ?? TaskCategory(title: record.title, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.colorHex = record.colorHex
            model.iconName = record.iconName
            model.includesInForecast = record.includesInForecast
            model.sortOrder = record.sortOrder
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreTaskCategoryAssignments(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).map { ($0.id, $0) })
        let snapshotIDs = Set(taskCategoryAssignments.map(\.id))
        for assignment in existing.values where !snapshotIDs.contains(assignment.id) {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.deviceID = deviceID
            assignment.clientMutationID = UUID()
        }
        for record in taskCategoryAssignments {
            let model = existing[record.id] ?? TaskCategoryAssignment(taskID: record.taskID, categoryID: record.categoryID, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.categoryID = record.categoryID
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreSessions(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TimeSession>()).map { ($0.id, $0) })
        let snapshotIDs = Set(sessions.map(\.id))
        for session in existing.values where !snapshotIDs.contains(session.id) {
            session.deletedAt = now
            session.updatedAt = now
            session.deviceID = deviceID
            session.clientMutationID = UUID()
        }
        for record in sessions {
            let model = existing[record.id] ?? TimeSession(taskID: record.taskID, source: TimeSessionSource(rawValue: record.sourceRaw) ?? .timer, deviceID: deviceID, startedAt: record.startedAt)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.titleSnapshot = record.titleSnapshot
            model.sourceRaw = record.sourceRaw
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.note = record.note
            model.deviceID = deviceID
            model.clientMutationID = UUID()
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
        }
    }

    private func restoreSegments(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TimeSegment>()).map { ($0.id, $0) })
        let snapshotIDs = Set(segments.map(\.id))
        for segment in existing.values where !snapshotIDs.contains(segment.id) {
            segment.deletedAt = now
            segment.updatedAt = now
            segment.deviceID = deviceID
        }
        for record in segments {
            let model = existing[record.id] ?? TimeSegment(sessionID: record.sessionID, taskID: record.taskID, source: TimeSessionSource(rawValue: record.sourceRaw) ?? .timer, deviceID: deviceID, startedAt: record.startedAt, endedAt: record.endedAt)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.sessionID = record.sessionID
            model.taskID = record.taskID
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.sourceRaw = record.sourceRaw
            model.deviceID = deviceID
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
        }
    }

    private func restorePomodoroRuns(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<PomodoroRun>()).map { ($0.id, $0) })
        let snapshotIDs = Set(pomodoroRuns.map(\.id))
        for run in existing.values where !snapshotIDs.contains(run.id) {
            run.deletedAt = now
            run.updatedAt = now
            run.deviceID = deviceID
            run.clientMutationID = UUID()
        }
        for record in pomodoroRuns {
            let model = existing[record.id] ?? PomodoroRun(taskID: record.taskID, focus: record.focusSecondsPlanned, breakSeconds: record.breakSecondsPlanned, targetRounds: record.targetRounds, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.sessionID = record.sessionID
            model.focusSecondsPlanned = record.focusSecondsPlanned
            model.breakSecondsPlanned = record.breakSecondsPlanned
            model.longBreakSecondsPlanned = record.longBreakSecondsPlanned
            model.stateRaw = record.stateRaw
            model.startedAt = record.startedAt
            model.endedAt = record.endedAt
            model.completedFocusRounds = record.completedFocusRounds
            model.targetRounds = record.targetRounds
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreCountdownEvents(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<CountdownEvent>()).map { ($0.id, $0) })
        let snapshotIDs = Set(countdownEvents.map(\.id))
        for event in existing.values where !snapshotIDs.contains(event.id) {
            event.deletedAt = now
            event.updatedAt = now
            event.deviceID = deviceID
            event.clientMutationID = UUID()
        }
        for record in countdownEvents {
            let model = existing[record.id] ?? CountdownEvent(title: record.title, date: record.date, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.date = record.date
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreSyncedPreferences(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SyncedPreference>()).map { ($0.id, $0) })
        let snapshotIDs = Set(syncedPreferences.map(\.id))
        for preference in existing.values where !snapshotIDs.contains(preference.id) {
            preference.deletedAt = now
            preference.updatedAt = now
            preference.deviceID = deviceID
            preference.clientMutationID = UUID()
        }
        for record in syncedPreferences {
            let model = existing[record.id] ?? SyncedPreference(key: record.key, valueJSON: record.valueJSON, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.key = record.key
            model.valueJSON = record.valueJSON
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreChecklistItems(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ChecklistItem>()).map { ($0.id, $0) })
        let snapshotIDs = Set(checklistItems.map(\.id))
        for item in existing.values where !snapshotIDs.contains(item.id) {
            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        for record in checklistItems {
            let model = existing[record.id] ?? ChecklistItem(taskID: record.taskID, title: record.title, isCompleted: record.isCompleted, sortOrder: record.sortOrder, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.taskID = record.taskID
            model.title = record.title
            model.isCompleted = record.isCompleted
            model.sortOrder = record.sortOrder
            model.completedAt = record.completedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreChecklistItemVisuals(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ChecklistItemVisual>()).map { ($0.id, $0) })
        let snapshotIDs = Set(checklistItemVisuals.map(\.id))
        for visual in existing.values where !snapshotIDs.contains(visual.id) {
            visual.deletedAt = now
            visual.updatedAt = now
            visual.deviceID = deviceID
            visual.clientMutationID = UUID()
        }
        for record in checklistItemVisuals {
            let model = existing[record.id] ?? ChecklistItemVisual(checklistItemID: record.checklistItemID, iconName: record.iconName, colorHex: record.colorHex, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.checklistItemID = record.checklistItemID
            model.iconName = record.iconName
            model.colorHex = record.colorHex
            model.suggestionTitleSnapshot = record.suggestionTitleSnapshot
            model.suggestionModelID = record.suggestionModelID
            model.suggestionGeneratedAt = record.suggestionGeneratedAt
            model.userEditedAt = record.userEditedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreInboxItems(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<InboxItem>()).map { ($0.id, $0) })
        let snapshotIDs = Set(inboxItems.map(\.id))
        for item in existing.values where !snapshotIDs.contains(item.id) {
            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        for record in inboxItems {
            let model = existing[record.id] ?? InboxItem(title: record.title, isCompleted: record.isCompleted, sortOrder: record.sortOrder, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.title = record.title
            model.notes = record.notes
            model.isCompleted = record.isCompleted
            model.sortOrder = record.sortOrder
            model.completedAt = record.completedAt
            model.suggestedTaskID = record.suggestedTaskID
            model.suggestionReason = record.suggestionReason
            model.suggestionGeneratedAt = record.suggestionGeneratedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }

    private func restoreInboxSuggestions(context: ModelContext, now: Date, deviceID: String) throws {
        var existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<InboxSuggestion>()).map { ($0.id, $0) })
        let snapshotIDs = Set(inboxSuggestions.map(\.id))
        for suggestion in existing.values where !snapshotIDs.contains(suggestion.id) {
            suggestion.deletedAt = now
            suggestion.updatedAt = now
            suggestion.deviceID = deviceID
            suggestion.clientMutationID = UUID()
        }
        for record in inboxSuggestions {
            let model = existing[record.id] ?? InboxSuggestion(inboxItemID: record.inboxItemID, taskID: record.taskID, reason: record.reason, iconName: record.iconName, colorHex: record.colorHex, modelID: record.modelID, titleSnapshot: record.titleSnapshot, generatedAt: record.generatedAt, deviceID: deviceID)
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.inboxItemID = record.inboxItemID
            model.taskID = record.taskID
            model.reason = record.reason
            model.iconName = record.iconName
            model.colorHex = record.colorHex
            model.modelID = record.modelID
            model.titleSnapshot = record.titleSnapshot
            model.generatedAt = record.generatedAt
            model.createdAt = record.createdAt
            model.updatedAt = max(record.updatedAt, now)
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = UUID()
        }
    }
}

private protocol SyncSnapshotRecord {
    var id: UUID { get }
}

private extension Array where Element: SyncSnapshotRecord {
    func sortedByID() -> [Element] {
        sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

private struct TaskRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let kindRaw: String
    let parentID: UUID?
    let sortOrder: Double
    let path: String
    let depth: Int
    let statusRaw: String
    let colorHex: String?
    let iconName: String?
    let estimatedSeconds: Int?
    let dueAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let deletedAt: Date?

    init(_ model: TaskNode) {
        id = model.id
        title = model.title
        kindRaw = model.kindRaw
        parentID = model.parentID
        sortOrder = model.sortOrder
        path = model.path
        depth = model.depth
        statusRaw = model.statusRaw
        colorHex = model.colorHex
        iconName = model.iconName
        estimatedSeconds = model.estimatedSeconds
        dueAt = model.dueAt
        notes = model.notes
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        archivedAt = model.archivedAt
        deletedAt = model.deletedAt
    }
}

private struct TaskCategoryRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let colorHex: String?
    let iconName: String?
    let includesInForecast: Bool
    let sortOrder: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategory) {
        id = model.id
        title = model.title
        colorHex = model.colorHex
        iconName = model.iconName
        includesInForecast = model.includesInForecast
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct TaskCategoryAssignmentRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let taskID: UUID
    let categoryID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategoryAssignment) {
        id = model.id
        taskID = model.taskID
        categoryID = model.categoryID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct TimeSessionRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let taskID: UUID
    let titleSnapshot: String?
    let sourceRaw: String
    let startedAt: Date
    let endedAt: Date?
    let note: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TimeSession) {
        id = model.id
        taskID = model.taskID
        titleSnapshot = model.titleSnapshot
        sourceRaw = model.sourceRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        note = model.note
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct TimeSegmentRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let sourceRaw: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TimeSegment) {
        id = model.id
        sessionID = model.sessionID
        taskID = model.taskID
        startedAt = model.startedAt
        endedAt = model.endedAt
        sourceRaw = model.sourceRaw
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct PomodoroRunRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let taskID: UUID
    let sessionID: UUID?
    let focusSecondsPlanned: Int
    let breakSecondsPlanned: Int
    let longBreakSecondsPlanned: Int?
    let stateRaw: String
    let startedAt: Date?
    let endedAt: Date?
    let completedFocusRounds: Int
    let targetRounds: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: PomodoroRun) {
        id = model.id
        taskID = model.taskID
        sessionID = model.sessionID
        focusSecondsPlanned = model.focusSecondsPlanned
        breakSecondsPlanned = model.breakSecondsPlanned
        longBreakSecondsPlanned = model.longBreakSecondsPlanned
        stateRaw = model.stateRaw
        startedAt = model.startedAt
        endedAt = model.endedAt
        completedFocusRounds = model.completedFocusRounds
        targetRounds = model.targetRounds
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct CountdownEventRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let date: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: CountdownEvent) {
        id = model.id
        title = model.title
        date = model.date
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct SyncedPreferenceRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let key: String
    let valueJSON: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: SyncedPreference) {
        id = model.id
        key = model.key
        valueJSON = model.valueJSON
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct ChecklistItemRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let taskID: UUID
    let title: String
    let isCompleted: Bool
    let sortOrder: Double
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: ChecklistItem) {
        id = model.id
        taskID = model.taskID
        title = model.title
        isCompleted = model.isCompleted
        sortOrder = model.sortOrder
        completedAt = model.completedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct ChecklistItemVisualRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let checklistItemID: UUID
    let iconName: String
    let colorHex: String
    let suggestionTitleSnapshot: String?
    let suggestionModelID: String?
    let suggestionGeneratedAt: Date?
    let userEditedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: ChecklistItemVisual) {
        id = model.id
        checklistItemID = model.checklistItemID
        iconName = model.iconName
        colorHex = model.colorHex
        suggestionTitleSnapshot = model.suggestionTitleSnapshot
        suggestionModelID = model.suggestionModelID
        suggestionGeneratedAt = model.suggestionGeneratedAt
        userEditedAt = model.userEditedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct InboxItemRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let notes: String?
    let isCompleted: Bool
    let sortOrder: Double
    let completedAt: Date?
    let suggestedTaskID: UUID?
    let suggestionReason: String?
    let suggestionGeneratedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: InboxItem) {
        id = model.id
        title = model.title
        notes = model.notes
        isCompleted = model.isCompleted
        sortOrder = model.sortOrder
        completedAt = model.completedAt
        suggestedTaskID = model.suggestedTaskID
        suggestionReason = model.suggestionReason
        suggestionGeneratedAt = model.suggestionGeneratedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

private struct InboxSuggestionRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let inboxItemID: UUID
    let taskID: UUID
    let reason: String?
    let iconName: String
    let colorHex: String
    let modelID: String?
    let titleSnapshot: String
    let generatedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: InboxSuggestion) {
        id = model.id
        inboxItemID = model.inboxItemID
        taskID = model.taskID
        reason = model.reason
        iconName = model.iconName
        colorHex = model.colorHex
        modelID = model.modelID
        titleSnapshot = model.titleSnapshot
        generatedAt = model.generatedAt
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
