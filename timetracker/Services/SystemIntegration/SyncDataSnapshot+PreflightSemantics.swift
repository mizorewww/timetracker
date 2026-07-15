import Foundation

extension SyncDataSnapshot {
    func validateRestoreSemantics() throws {
        try validateRawValues()
        try validatePomodoroValues()
        try validatePreferenceValues()
        try validateSessionRelationships()
        try validateInboxSuggestionRelationships()
    }

    private func validateRawValues() throws {
        for record in tasks {
            guard record.kindRaw == "task" else {
                throw SyncDataSnapshotPreflightError.invalidRawValue(
                    table: .tasks,
                    id: record.id,
                    field: "kindRaw",
                    value: record.kindRaw
                )
            }
            guard TaskStatus(rawValue: record.statusRaw) != nil else {
                throw SyncDataSnapshotPreflightError.invalidRawValue(
                    table: .tasks,
                    id: record.id,
                    field: "statusRaw",
                    value: record.statusRaw
                )
            }
        }

        for record in sessions where TimeSessionSource(rawValue: record.sourceRaw) == nil {
            throw SyncDataSnapshotPreflightError.invalidRawValue(
                table: .sessions,
                id: record.id,
                field: "sourceRaw",
                value: record.sourceRaw
            )
        }
        for record in segments where TimeSessionSource(rawValue: record.sourceRaw) == nil {
            throw SyncDataSnapshotPreflightError.invalidRawValue(
                table: .segments,
                id: record.id,
                field: "sourceRaw",
                value: record.sourceRaw
            )
        }
        for record in pomodoroRuns where PomodoroState(rawValue: record.stateRaw) == nil {
            throw SyncDataSnapshotPreflightError.invalidRawValue(
                table: .pomodoroRuns,
                id: record.id,
                field: "stateRaw",
                value: record.stateRaw
            )
        }
    }

    private func validatePomodoroValues() throws {
        for record in pomodoroRuns {
            try require(
                record.focusSecondsPlanned,
                in: 1...28_800,
                recordID: record.id,
                field: "focusSecondsPlanned"
            )
            try require(
                record.breakSecondsPlanned,
                in: 1...28_800,
                recordID: record.id,
                field: "breakSecondsPlanned"
            )
            if let longBreakSecondsPlanned = record.longBreakSecondsPlanned {
                try require(
                    longBreakSecondsPlanned,
                    in: 1...28_800,
                    recordID: record.id,
                    field: "longBreakSecondsPlanned"
                )
            }
            try require(record.targetRounds, in: 1...24, recordID: record.id, field: "targetRounds")
            try require(
                record.completedFocusRounds,
                in: 0...record.targetRounds,
                recordID: record.id,
                field: "completedFocusRounds"
            )
        }
    }

    private func require(
        _ value: Int,
        in range: ClosedRange<Int>,
        recordID: UUID,
        field: String
    ) throws {
        guard range.contains(value) else {
            throw SyncDataSnapshotPreflightError.invalidInteger(
                table: .pomodoroRuns,
                id: recordID,
                field: field,
                value: value,
                allowed: "\(range.lowerBound)...\(range.upperBound)"
            )
        }
    }

    private func validatePreferenceValues() throws {
        for record in syncedPreferences {
            guard !record.key.isEmpty,
                  !record.key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw SyncDataSnapshotPreflightError.invalidPreferenceKey(id: record.id, key: record.key)
            }
            let data = Data(record.valueJSON.utf8)
            guard SyncedPreferenceService.shouldSyncKey(record.key) else { continue }
            let isValid: Bool
            if let key = AppPreferenceKey(rawValue: record.key) {
                switch key {
                case .preferredColorScheme, .pomodoroDefaultMode, .llmEndpoint, .llmSelectedModel:
                    isValid = decodes(String.self, from: data)
                case .defaultFocusMinutes, .defaultBreakMinutes, .defaultPomodoroRounds:
                    isValid = decodes(Int.self, from: data)
                case .pomodoroPlans:
                    isValid = decodes([PomodoroPlan].self, from: data)
                case .allowParallelTimers, .showGrossAndWallTogether:
                    isValid = decodes(Bool.self, from: data)
                case .quickStartTaskIDs, .llmAvailableModelIDs:
                    isValid = decodes([String].self, from: data)
                }
            } else {
                isValid = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
            }
            guard isValid else {
                throw SyncDataSnapshotPreflightError.invalidPreferenceValue(id: record.id, key: record.key)
            }
        }
    }

    private func decodes<Value: Decodable>(_ type: Value.Type, from data: Data) -> Bool {
        (try? JSONDecoder().decode(type, from: data)) != nil
    }

    private func validateSessionRelationships() throws {
        let sessionTaskByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.taskID) })
        for record in segments {
            guard let sessionTaskID = sessionTaskByID[record.sessionID] else { continue }
            guard sessionTaskID == record.taskID else {
                throw SyncDataSnapshotPreflightError.inconsistentSessionTask(
                    table: .segments,
                    id: record.id,
                    sessionID: record.sessionID,
                    expectedTaskID: sessionTaskID,
                    actualTaskID: record.taskID
                )
            }
        }
        for record in pomodoroRuns {
            guard let sessionID = record.sessionID,
                  let sessionTaskID = sessionTaskByID[sessionID] else { continue }
            guard sessionTaskID == record.taskID else {
                throw SyncDataSnapshotPreflightError.inconsistentSessionTask(
                    table: .pomodoroRuns,
                    id: record.id,
                    sessionID: sessionID,
                    expectedTaskID: sessionTaskID,
                    actualTaskID: record.taskID
                )
            }
        }
    }

    private func validateInboxSuggestionRelationships() throws {
        let itemIdentityByID = inboxItems.reduce(into: [UUID: InboxSuggestionIdentity]()) { result, item in
            result[item.id] = InboxSuggestionIdentity(
                contextID: item.suggestionContextID ?? item.id,
                revisionID: item.suggestionRevisionID ?? item.id
            )
        }
        for suggestion in inboxSuggestions {
            guard let itemIdentity = itemIdentityByID[suggestion.inboxItemID] else {
                continue
            }
            let suggestionIdentity = InboxSuggestionIdentity(
                contextID: suggestion.inboxItemContextID ?? itemIdentity.contextID,
                revisionID: suggestion.inboxItemRevisionID ?? itemIdentity.revisionID
            )
            guard suggestionIdentity == itemIdentity else {
                throw SyncDataSnapshotPreflightError.inconsistentInboxSuggestionIdentity(
                    id: suggestion.id,
                    inboxItemID: suggestion.inboxItemID
                )
            }
        }
    }
}
