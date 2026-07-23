import Foundation

/// A value-only recurrence index for Today Heatmap configuration and
/// aggregation. The projection intentionally retains no SwiftData models so a
/// store can cache it between task-index rebuilds.
nonisolated struct TodayHeatmapRecurrenceProjection: Equatable, Sendable {
    static let empty = TodayHeatmapRecurrenceProjection(
        ownerTaskIDByGeneratedTaskID: [:],
        generatedTaskIDsByTemplateTaskID: [:],
        renderableTaskIDSet: [],
        pickerExcludedTaskIDs: []
    )

    let generatedTaskIDsByTemplateTaskID: [UUID: Set<UUID>]

    private let ownerTaskIDByGeneratedTaskID: [UUID: UUID]
    private let renderableTaskIDSet: Set<UUID>
    private let pickerExcludedTaskIDs: Set<UUID>

    @MainActor
    init(
        taskByID: [UUID: TaskNode],
        recurrenceRules: [TaskRecurrenceRule],
        recurrenceOccurrences: [TaskRecurrenceOccurrence],
        incompleteTemplateTaskIDs: Set<UUID>,
        incompleteGeneratedTaskIDs: Set<UUID>
    ) {
        let validTaskIDs = Set(taskByID.compactMap { taskID, task in
            taskID == task.id && task.deletedAt == nil ? taskID : nil
        })
        var blockedTaskIDs = incompleteTemplateTaskIDs
            .union(incompleteGeneratedTaskIDs)
            .intersection(validTaskIDs)
        var invalidTaskIDs = Set<UUID>()

        let visibleRules = recurrenceRules.latestByID().values.filter {
            $0.deletedAt == nil
        }
        var validRuleByID: [UUID: TaskRecurrenceRule] = [:]
        for rule in visibleRules {
            let hasCanonicalIdentity = rule.id ==
                TaskProgressIdentity.recurrenceRuleID(
                    templateTaskID: rule.templateTaskID
                )
            let hasValidConfiguration =
                TaskRecurrenceCadence(rawValue: rule.cadenceRaw) != nil &&
                TaskRecurrenceDayKey.isCanonical(rule.startDayKey) &&
                TimeZone(identifier: rule.timeZoneIdentifier) != nil &&
                rule.timeZoneIdentifier.utf8.count <=
                    TaskRecurrencePolicy.maximumTimeZoneIdentifierByteCount
            let hasValidTemplate =
                validTaskIDs.contains(rule.templateTaskID) &&
                blockedTaskIDs.contains(rule.templateTaskID) == false
            guard hasCanonicalIdentity,
                  hasValidConfiguration,
                  hasValidTemplate else {
                if validTaskIDs.contains(rule.templateTaskID),
                   blockedTaskIDs.contains(rule.templateTaskID) == false {
                    invalidTaskIDs.insert(rule.templateTaskID)
                }
                continue
            }
            validRuleByID[rule.id] = rule
        }

        struct Candidate {
            let templateTaskID: UUID
            let generatedTaskID: UUID
        }

        let visibleOccurrences = recurrenceOccurrences.latestByID().values
            .filter { $0.deletedAt == nil }
        var candidates: [Candidate] = []
        var pickerExcludedTaskIDs = incompleteGeneratedTaskIDs
            .intersection(validTaskIDs)

        for occurrence in visibleOccurrences {
            let expectedOccurrenceID =
                TaskProgressIdentity.recurrenceOccurrenceID(
                    ruleID: occurrence.ruleID,
                    dayKey: occurrence.occurrenceDayKey
                )
            let expectedGeneratedTaskID =
                TaskProgressIdentity.generatedTaskID(
                    ruleID: occurrence.ruleID,
                    dayKey: occurrence.occurrenceDayKey
                )
            if validTaskIDs.contains(occurrence.generatedTaskID) {
                pickerExcludedTaskIDs.insert(occurrence.generatedTaskID)
            }
            if validTaskIDs.contains(expectedGeneratedTaskID) {
                pickerExcludedTaskIDs.insert(expectedGeneratedTaskID)
            }

            let participants = [
                occurrence.templateTaskID,
                occurrence.generatedTaskID,
                expectedGeneratedTaskID,
            ].filter(validTaskIDs.contains)
            let relationshipIsIncomplete = participants.contains {
                blockedTaskIDs.contains($0)
            }
            guard let rule = validRuleByID[occurrence.ruleID],
                  occurrence.id == expectedOccurrenceID,
                  occurrence.generatedTaskID == expectedGeneratedTaskID,
                  occurrence.templateTaskID == rule.templateTaskID,
                  occurrence.timeZoneIdentifier == rule.timeZoneIdentifier,
                  TaskRecurrenceDayKey.isCanonical(
                    occurrence.occurrenceDayKey
                  ),
                  TimeZone(identifier: occurrence.timeZoneIdentifier) != nil,
                  occurrence.occurrenceDayKey >= rule.startDayKey,
                  occurrence.templateTaskID != occurrence.generatedTaskID,
                  validTaskIDs.contains(occurrence.templateTaskID),
                  validTaskIDs.contains(occurrence.generatedTaskID),
                  relationshipIsIncomplete == false else {
                if relationshipIsIncomplete {
                    blockedTaskIDs.formUnion(participants)
                } else {
                    invalidTaskIDs.formUnion(participants)
                }
                continue
            }
            candidates.append(
                Candidate(
                    templateTaskID: occurrence.templateTaskID,
                    generatedTaskID: occurrence.generatedTaskID
                )
            )
        }

        let claimsByGeneratedTaskID = Dictionary(
            grouping: candidates,
            by: \.generatedTaskID
        )
        for claims in claimsByGeneratedTaskID.values where claims.count != 1 {
            invalidTaskIDs.formUnion(claims.map(\.generatedTaskID))
            invalidTaskIDs.formUnion(claims.map(\.templateTaskID))
        }

        let candidateTemplateTaskIDs = Set(candidates.map(\.templateTaskID))
        let candidateGeneratedTaskIDs = Set(candidates.map(\.generatedTaskID))
        invalidTaskIDs.formUnion(
            candidateTemplateTaskIDs.intersection(candidateGeneratedTaskIDs)
        )

        var previousInvalidTaskIDs: Set<UUID>
        repeat {
            previousInvalidTaskIDs = invalidTaskIDs
            for candidate in candidates where
                invalidTaskIDs.contains(candidate.templateTaskID) ||
                invalidTaskIDs.contains(candidate.generatedTaskID) {
                invalidTaskIDs.insert(candidate.templateTaskID)
                invalidTaskIDs.insert(candidate.generatedTaskID)
            }
        } while invalidTaskIDs != previousInvalidTaskIDs

        var ownerTaskIDByGeneratedTaskID: [UUID: UUID] = [:]
        var generatedTaskIDsByTemplateTaskID: [UUID: Set<UUID>] = [:]
        for candidate in candidates {
            guard blockedTaskIDs.contains(candidate.templateTaskID) == false,
                  blockedTaskIDs.contains(candidate.generatedTaskID) == false,
                  invalidTaskIDs.contains(candidate.templateTaskID) == false,
                  invalidTaskIDs.contains(candidate.generatedTaskID) == false,
                  claimsByGeneratedTaskID[candidate.generatedTaskID]?.count == 1
            else {
                continue
            }
            ownerTaskIDByGeneratedTaskID[candidate.generatedTaskID] =
                candidate.templateTaskID
            generatedTaskIDsByTemplateTaskID[
                candidate.templateTaskID,
                default: []
            ].insert(candidate.generatedTaskID)
        }

        self.init(
            ownerTaskIDByGeneratedTaskID: ownerTaskIDByGeneratedTaskID,
            generatedTaskIDsByTemplateTaskID:
                generatedTaskIDsByTemplateTaskID,
            renderableTaskIDSet: validTaskIDs
                .subtracting(blockedTaskIDs)
                .subtracting(invalidTaskIDs),
            pickerExcludedTaskIDs: pickerExcludedTaskIDs
        )
    }

    func ownerTaskID(for taskID: UUID) -> UUID {
        ownerTaskIDByGeneratedTaskID[taskID] ?? taskID
    }

    /// Maps valid generated occurrences to their template while retaining
    /// unknown, incomplete, and corrupt IDs verbatim for preference recovery.
    func canonicalTaskIDs(_ taskIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return taskIDs.compactMap { taskID in
            let canonicalTaskID = ownerTaskID(for: taskID)
            return seen.insert(canonicalTaskID).inserted
                ? canonicalTaskID
                : nil
        }
    }

    /// Returns canonical IDs that currently have a complete, visible task and
    /// recurrence graph. Hidden IDs stay in preferences but do not produce
    /// Heatmap cards until their graph becomes complete.
    func renderableTaskIDs(_ taskIDs: [UUID]) -> [UUID] {
        canonicalTaskIDs(taskIDs).filter(renderableTaskIDSet.contains)
    }

    /// Filters a caller-provided picker eligibility set. Generated occurrences
    /// remain direct-work tasks elsewhere, but Heatmap configuration belongs to
    /// their stable recurrence template.
    func selectableTaskIDs(from taskIDs: Set<UUID>) -> Set<UUID> {
        taskIDs
            .intersection(renderableTaskIDSet)
            .subtracting(pickerExcludedTaskIDs)
    }

    private init(
        ownerTaskIDByGeneratedTaskID: [UUID: UUID],
        generatedTaskIDsByTemplateTaskID: [UUID: Set<UUID>],
        renderableTaskIDSet: Set<UUID>,
        pickerExcludedTaskIDs: Set<UUID>
    ) {
        self.ownerTaskIDByGeneratedTaskID = ownerTaskIDByGeneratedTaskID
        self.generatedTaskIDsByTemplateTaskID =
            generatedTaskIDsByTemplateTaskID
        self.renderableTaskIDSet = renderableTaskIDSet
        self.pickerExcludedTaskIDs = pickerExcludedTaskIDs
    }
}
