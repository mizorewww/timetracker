import Foundation

extension SyncDataSnapshot {
    func validateRestoreSemantics() throws {
        try validateRawValues()
        try validatePomodoroValues()
        try validatePreferenceValues()
        try validateSessionRelationships()
        try validateInboxSuggestionRelationships()
        try validateTaskProgressSemantics()
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
            guard LegacyTaskStatusRaw.acceptedValues.contains(record.statusRaw) else {
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
        for record in inboxSuggestions
        where InboxSuggestionDestinationKind(rawValue: record.destinationKindRaw) == nil {
            throw SyncDataSnapshotPreflightError.invalidRawValue(
                table: .inboxSuggestions,
                id: record.id,
                field: "destinationKindRaw",
                value: record.destinationKindRaw
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
                case .preferredColorScheme,
                     .pomodoroDefaultMode,
                     .todayHeatmapPeriod,
                     .llmEndpoint,
                     .llmSelectedModel:
                    isValid = decodes(String.self, from: data)
                case .llmInboxSuggestionInstructions,
                     .llmChecklistVisualInstructions,
                     .llmTaskPlanInstructions:
                    isValid = (
                        try? PreferenceJSON.canonicalValueJSON(
                            for: key,
                            from: record.valueJSON
                        )
                    ) != nil
                case .defaultFocusMinutes, .defaultBreakMinutes, .defaultPomodoroRounds:
                    isValid = decodes(Int.self, from: data)
                case .pomodoroPlans:
                    isValid = decodes([PomodoroPlan].self, from: data)
                case .allowParallelTimers, .showGrossAndWallTogether:
                    isValid = decodes(Bool.self, from: data)
                case .quickStartTaskIDs,
                     .todayHeatmapTaskIDs,
                     .llmAvailableModelIDs:
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
            // A title edit intentionally rotates the item's revision and keeps the
            // previous revision's suggestion as a tombstone. The physical item ID
            // still proves the shared logical context, but revisions may differ.
            guard suggestionIdentity.contextID == itemIdentity.contextID else {
                throw SyncDataSnapshotPreflightError.inconsistentInboxSuggestionIdentity(
                    id: suggestion.id,
                    inboxItemID: suggestion.inboxItemID
                )
            }
        }

        let inboxItemIDs = Set(inboxItems.map(\.id))
        var committedResultByCommandKey: [String: (payloadFingerprint: String, inboxItemID: UUID)] = [:]
        for receipt in inboxCaptureReceipts ?? [] {
            guard inboxItemIDs.contains(receipt.inboxItemID) else {
                throw SyncDataSnapshotPreflightError.inconsistentInboxCaptureReceipt(
                    id: receipt.id,
                    inboxItemID: receipt.inboxItemID
                )
            }
            guard receipt.deletedAt == nil else { continue }
            let result = (
                payloadFingerprint: receipt.payloadFingerprint,
                inboxItemID: receipt.inboxItemID
            )
            if let existing = committedResultByCommandKey[receipt.commandKey],
               (existing.payloadFingerprint != result.payloadFingerprint ||
                   existing.inboxItemID != result.inboxItemID) {
                throw SyncDataSnapshotPreflightError.inconsistentInboxCaptureCommandKey(
                    commandKey: receipt.commandKey
                )
            }
            committedResultByCommandKey[receipt.commandKey] = result
        }
    }
}
