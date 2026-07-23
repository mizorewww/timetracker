import Foundation
import Testing
@testable import timetracker

struct TodayHeatmapRecurrenceProjectionTests {
    @Test @MainActor
    func validRelationshipsMapOwnersContributorsAndStableSelection() {
        let template = task(title: "Daily push-ups")
        let rule = recurrenceRule(templateTaskID: template.id)
        let firstOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-22"
        )
        let secondOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-23"
        )
        let firstGenerated = task(
            id: firstOccurrence.generatedTaskID,
            title: "First occurrence",
            parentID: template.id
        )
        let secondGenerated = task(
            id: secondOccurrence.generatedTaskID,
            title: "Second occurrence",
            parentID: template.id
        )
        let ordinaryChild = task(
            title: "Ordinary child",
            parentID: template.id
        )
        let unknownTaskID = UUID()
        let projection = projection(
            tasks: [
                template,
                firstGenerated,
                secondGenerated,
                ordinaryChild,
            ],
            rules: [rule],
            occurrences: [secondOccurrence, firstOccurrence]
        )

        #expect(
            projection.ownerTaskID(for: firstGenerated.id) == template.id
        )
        #expect(
            projection.ownerTaskID(for: secondGenerated.id) == template.id
        )
        #expect(
            projection.ownerTaskID(for: ordinaryChild.id) == ordinaryChild.id
        )
        #expect(
            projection.generatedTaskIDsByTemplateTaskID[template.id] ==
                Set([firstGenerated.id, secondGenerated.id])
        )
        #expect(
            projection.canonicalTaskIDs([
                ordinaryChild.id,
                secondGenerated.id,
                template.id,
                firstGenerated.id,
                unknownTaskID,
                ordinaryChild.id,
            ]) == [
                ordinaryChild.id,
                template.id,
                unknownTaskID,
            ]
        )
        #expect(
            projection.renderableTaskIDs([
                ordinaryChild.id,
                secondGenerated.id,
                unknownTaskID,
            ]) == [
                ordinaryChild.id,
                template.id,
            ]
        )
        #expect(
            projection.selectableTaskIDs(from: [
                template.id,
                firstGenerated.id,
                secondGenerated.id,
                ordinaryChild.id,
                unknownTaskID,
            ]) == Set([template.id, ordinaryChild.id])
        )
    }

    @Test @MainActor
    func movedGeneratedTaskStillUsesOccurrenceOwner() {
        let template = task(title: "Daily writing")
        let unrelatedParent = task(title: "Moved destination")
        let rule = recurrenceRule(templateTaskID: template.id)
        let generatedOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-23"
        )
        let movedGenerated = task(
            id: generatedOccurrence.generatedTaskID,
            title: "Today's writing",
            parentID: unrelatedParent.id
        )
        let projection = projection(
            tasks: [template, unrelatedParent, movedGenerated],
            rules: [rule],
            occurrences: [generatedOccurrence]
        )

        #expect(
            projection.ownerTaskID(for: movedGenerated.id) == template.id
        )
        #expect(
            projection.generatedTaskIDsByTemplateTaskID[template.id] ==
                Set([movedGenerated.id])
        )
        #expect(
            projection.canonicalTaskIDs([movedGenerated.id]) == [template.id]
        )
    }

    @Test @MainActor
    func incompleteRelationshipPreservesSelectionButDoesNotRender() {
        let template = task(title: "Daily reading")
        let rule = recurrenceRule(templateTaskID: template.id)
        let generatedOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-23"
        )
        let generated = task(
            id: generatedOccurrence.generatedTaskID,
            title: "Today's reading",
            parentID: template.id
        )
        let ordinaryTask = task(title: "Ordinary")
        let unknownTaskID = UUID()
        let projection = projection(
            tasks: [template, generated, ordinaryTask],
            rules: [rule],
            occurrences: [generatedOccurrence],
            incompleteGeneratedTaskIDs: [generated.id]
        )

        #expect(projection.ownerTaskID(for: generated.id) == generated.id)
        #expect(
            projection.generatedTaskIDsByTemplateTaskID[template.id] == nil
        )
        #expect(
            projection.canonicalTaskIDs([
                generated.id,
                template.id,
                unknownTaskID,
            ]) == [
                generated.id,
                template.id,
                unknownTaskID,
            ]
        )
        #expect(
            projection.renderableTaskIDs([
                generated.id,
                template.id,
                ordinaryTask.id,
                unknownTaskID,
            ]) == [ordinaryTask.id]
        )
        #expect(
            projection.selectableTaskIDs(from: [
                template.id,
                generated.id,
                ordinaryTask.id,
            ]) == Set([ordinaryTask.id])
        )
    }

    @Test @MainActor
    func corruptLWWWinnerAndStagedMissingRuleFailClosed() {
        let template = task(title: "Daily practice")
        let rule = recurrenceRule(templateTaskID: template.id)
        let validOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-23",
            updatedAt: date(10)
        )
        let expectedGenerated = task(
            id: validOccurrence.generatedTaskID,
            title: "Expected generated",
            parentID: template.id
        )
        let wrongGenerated = task(
            title: "Wrong generated",
            parentID: template.id
        )
        let corruptWinner = occurrence(
            rule: rule,
            dayKey: "2026-07-23",
            updatedAt: date(20)
        )
        corruptWinner.generatedTaskID = wrongGenerated.id
        let corruptProjection = projection(
            tasks: [template, expectedGenerated, wrongGenerated],
            rules: [rule],
            occurrences: [validOccurrence, corruptWinner]
        )

        #expect(
            corruptProjection.generatedTaskIDsByTemplateTaskID[template.id] ==
                nil
        )
        #expect(
            corruptProjection.ownerTaskID(for: expectedGenerated.id) ==
                expectedGenerated.id
        )
        #expect(
            corruptProjection.renderableTaskIDs([
                template.id,
                expectedGenerated.id,
                wrongGenerated.id,
            ]).isEmpty
        )
        #expect(
            corruptProjection.selectableTaskIDs(from: [
                template.id,
                expectedGenerated.id,
                wrongGenerated.id,
            ]).isEmpty
        )

        let stagedProjection = projection(
            tasks: [template, expectedGenerated],
            rules: [],
            occurrences: [validOccurrence]
        )
        #expect(
            stagedProjection.generatedTaskIDsByTemplateTaskID[template.id] ==
                nil
        )
        #expect(
            stagedProjection.canonicalTaskIDs([expectedGenerated.id]) ==
                [expectedGenerated.id]
        )
        #expect(
            stagedProjection.renderableTaskIDs([
                template.id,
                expectedGenerated.id,
            ]).isEmpty
        )
    }

    @Test @MainActor
    func mismatchedOccurrenceBlocksItsCanonicalRuleTemplate() {
        let template = task(title: "Canonical template")
        let wrongTemplate = task(title: "Conflicting template")
        let rule = recurrenceRule(templateTaskID: template.id)
        let conflictingOccurrence = occurrence(
            rule: rule,
            dayKey: "2026-07-23"
        )
        conflictingOccurrence.templateTaskID = wrongTemplate.id
        let generated = task(
            id: conflictingOccurrence.generatedTaskID,
            title: "Generated occurrence",
            parentID: template.id
        )
        let projection = projection(
            tasks: [template, wrongTemplate, generated],
            rules: [rule],
            occurrences: [conflictingOccurrence]
        )

        #expect(
            projection.generatedTaskIDsByTemplateTaskID[template.id] == nil
        )
        #expect(
            projection.renderableTaskIDs([
                template.id,
                wrongTemplate.id,
                generated.id,
            ]).isEmpty
        )
        #expect(
            projection.selectableTaskIDs(from: [
                template.id,
                wrongTemplate.id,
                generated.id,
            ]).isEmpty
        )
    }
}

private extension TodayHeatmapRecurrenceProjectionTests {
    @MainActor
    func projection(
        tasks: [TaskNode],
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence],
        incompleteTemplateTaskIDs: Set<UUID> = [],
        incompleteGeneratedTaskIDs: Set<UUID> = []
    ) -> TodayHeatmapRecurrenceProjection {
        TodayHeatmapRecurrenceProjection(
            taskByID: tasks.reduce(into: [:]) { $0[$1.id] = $1 },
            recurrenceRules: rules,
            recurrenceOccurrences: occurrences,
            incompleteTemplateTaskIDs: incompleteTemplateTaskIDs,
            incompleteGeneratedTaskIDs: incompleteGeneratedTaskIDs
        )
    }

    @MainActor
    func task(
        id: UUID = UUID(),
        title: String,
        parentID: UUID? = nil
    ) -> TaskNode {
        let task = TaskNode(
            title: title,
            parentID: parentID,
            deviceID: "test"
        )
        task.id = id
        task.createdAt = date(0)
        task.updatedAt = date(0)
        task.clientMutationID = id
        return task
    }

    @MainActor
    func recurrenceRule(templateTaskID: UUID) -> TaskRecurrenceRule {
        let rule = TaskRecurrenceRule(
            templateTaskID: templateTaskID,
            startDayKey: "2026-07-22",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "test"
        )
        rule.createdAt = date(0)
        rule.updatedAt = date(0)
        rule.clientMutationID = rule.id
        return rule
    }

    @MainActor
    func occurrence(
        rule: TaskRecurrenceRule,
        dayKey: String,
        updatedAt: Date? = nil
    ) -> TaskRecurrenceOccurrence {
        let occurrence = TaskRecurrenceOccurrence(
            ruleID: rule.id,
            templateTaskID: rule.templateTaskID,
            occurrenceDayKey: dayKey,
            timeZoneIdentifier: rule.timeZoneIdentifier,
            deviceID: "test"
        )
        occurrence.createdAt = date(0)
        occurrence.updatedAt = updatedAt ?? date(0)
        occurrence.clientMutationID = occurrence.id
        return occurrence
    }

    func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + offset)
    }
}
