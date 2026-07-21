import Foundation

extension TimeTrackerStore {
    func taskQuantityProgressReadState(
        for taskID: UUID
    ) -> TaskQuantityProgressReadState {
        _ = taskReadModelRevision
        guard taskIDsWithIncompleteQuantityProgress.contains(taskID) == false
        else {
            return .incomplete
        }
        if let snapshot = TaskQuantityProgressService().snapshot(
            taskID: taskID,
            goals: taskQuantityGoals,
            entries: taskQuantityEntries,
            isRecordingAllowed: trackableTaskIDs.contains(taskID)
        ) {
            return .available(snapshot)
        }

        return hasVisibleQuantityClaim(taskID: taskID)
            ? .incomplete
            : .none
    }

    func taskQuantityProgressReadState(
        for taskID: UUID,
        expectedGoalMutationID: UUID?
    ) -> TaskQuantityProgressReadState {
        switch taskQuantityProgressReadState(for: taskID) {
        case .none:
            return expectedGoalMutationID == nil ? .none : .incomplete
        case .incomplete:
            return .incomplete
        case .available(let snapshot):
            return snapshot.goalBaseline.clientMutationID ==
                expectedGoalMutationID
                ? .available(snapshot)
                : .incomplete
        }
    }

    func taskQuantityProgress(
        for taskID: UUID
    ) -> TaskQuantityProgressSnapshot? {
        switch taskQuantityProgressReadState(for: taskID) {
        case .available(let snapshot):
            return snapshot
        case .none, .incomplete:
            return nil
        }
    }

    func taskQuantityDetail(
        for taskID: UUID
    ) -> TaskQuantityDetailReadModel {
        _ = taskReadModelRevision
        guard taskIDsWithIncompleteQuantityProgress.contains(taskID) == false
        else {
            return .incomplete
        }
        guard let validated = TaskQuantityProgressService()
            .validatedSnapshot(
                taskID: taskID,
                goals: taskQuantityGoals,
                entries: taskQuantityEntries,
                isRecordingAllowed: trackableTaskIDs.contains(taskID)
            ) else {
            return hasVisibleQuantityClaim(taskID: taskID)
                ? .incomplete
                : .none
        }
        guard taskIDsWithIncompleteRecurrence.contains(taskID) == false
        else {
            return .incomplete
        }
        guard let role = taskQuantityRecurrenceRole(taskID: taskID) else {
            return .incomplete
        }
        return .available(
            TaskQuantityDetailSnapshot(
                progress: validated.progress,
                entries: validated.entries,
                recurrenceRole: role
            )
        )
    }

    func taskQuantityEntries(for taskID: UUID) -> [TaskQuantityEntry] {
        _ = taskReadModelRevision
        return taskQuantityEntries.filter { $0.taskID == taskID }
    }

    func taskQuantityGoalBaseline(
        for taskID: UUID
    ) -> TaskQuantityGoalMutationBaseline? {
        taskQuantityProgress(for: taskID)?.goalBaseline
    }

    private func hasVisibleQuantityClaim(taskID: UUID) -> Bool {
        let expectedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: taskID
        )
        return taskQuantityGoals.contains {
            $0.deletedAt == nil &&
                ($0.taskID == taskID || $0.id == expectedGoalID)
        } || taskQuantityEntries.contains {
            $0.deletedAt == nil &&
                ($0.taskID == taskID ||
                    $0.quantityGoalID == expectedGoalID)
        }
    }

    private func taskQuantityRecurrenceRole(
        taskID: UUID
    ) -> TaskQuantityRecurrenceRole? {
        let occurrences = taskRecurrenceOccurrences.filter {
            $0.deletedAt == nil && $0.generatedTaskID == taskID
        }
        let isTemplate = taskRecurrenceRules.contains {
            $0.deletedAt == nil && $0.templateTaskID == taskID
        } || taskRecurrenceOccurrences.contains {
            $0.deletedAt == nil && $0.templateTaskID == taskID
        }
        guard occurrences.count <= 1,
              occurrences.isEmpty || isTemplate == false else {
            return nil
        }
        guard let occurrence = occurrences.first else {
            return isTemplate ? .template : .ordinary
        }
        let expectedOccurrenceID = TaskProgressIdentity
            .recurrenceOccurrenceID(
                ruleID: occurrence.ruleID,
                dayKey: occurrence.occurrenceDayKey
            )
        let expectedGeneratedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: occurrence.ruleID,
            dayKey: occurrence.occurrenceDayKey
        )
        guard occurrence.id == expectedOccurrenceID,
              occurrence.generatedTaskID == expectedGeneratedTaskID,
              let localDate = TaskRecurrenceDayKey.date(
                  from: occurrence.occurrenceDayKey,
                  timeZoneIdentifier: occurrence.timeZoneIdentifier
              ) else {
            return nil
        }
        return .generated(
            TaskRecurrenceOccurrenceSnapshot(
                id: occurrence.id,
                templateTaskID: occurrence.templateTaskID,
                dayKey: occurrence.occurrenceDayKey,
                timeZoneIdentifier: occurrence.timeZoneIdentifier,
                localDate: localDate
            )
        )
    }
}
