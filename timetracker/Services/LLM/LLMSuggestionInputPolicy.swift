import Foundation

nonisolated struct LLMInboxSuggestionPreparedInput: Equatable, Sendable {
    let inboxTitle: String
    let taskCandidates: [LLMTaskCandidate]
    let categoryCandidates: [LLMCategoryCandidate]
    let modelID: String
}

nonisolated struct LLMInboxSuggestionCandidates: Codable, Equatable, Sendable {
    let tasks: [LLMTaskCandidate]
    let categories: [LLMCategoryCandidate]

    var isEmpty: Bool {
        tasks.isEmpty && categories.isEmpty
    }
}

nonisolated struct LLMChecklistVisualSuggestionPreparedInput: Equatable, Sendable {
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let modelID: String
}

nonisolated enum LLMSuggestionInputPolicy {
    // AI provenance is persisted in sync snapshot compact fields. Keep this
    // producer limit aligned with the restore contract so locally-created
    // suggestions always remain restorable.
    static let maximumModelIDByteCount = 256
    static let maximumReasonByteCount = 512
    static let maximumEndpointByteCount = 4 * 1024
    static let maximumAPIKeyByteCount = 8 * 1024
    static let maximumTaskIDByteCount = 64

    static func prepare(
        inboxTitle: String,
        taskCandidates: [LLMTaskCandidate],
        categoryCandidates: [LLMCategoryCandidate],
        modelID: String
    ) -> LLMInboxSuggestionPreparedInput {
        let completeCandidates = completeDestinationCandidates(
            tasks: taskCandidates,
            categories: categoryCandidates
        )
        return LLMInboxSuggestionPreparedInput(
            inboxTitle: normalizedText(inboxTitle),
            taskCandidates: completeCandidates.tasks,
            categoryCandidates: completeCandidates.categories,
            modelID: AppPreferenceValueSanitizer.llmModelID(modelID)
        )
    }

    static func prepareChecklistVisual(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        modelID: String
    ) -> LLMChecklistVisualSuggestionPreparedInput {
        LLMChecklistVisualSuggestionPreparedInput(
            checklistTitle: normalizedText(checklistTitle),
            taskTitle: normalizedText(taskTitle),
            taskPath: normalizedText(taskPath),
            modelID: AppPreferenceValueSanitizer.llmModelID(modelID)
        )
    }

    static func completeCandidates(
        _ candidates: [LLMTaskCandidate]
    ) -> [LLMTaskCandidate] {
        completeDestinationCandidates(
            tasks: candidates,
            categories: []
        ).tasks
    }

    static func completeCategoryCandidates(
        _ candidates: [LLMCategoryCandidate]
    ) -> [LLMCategoryCandidate] {
        completeDestinationCandidates(
            tasks: [],
            categories: candidates
        ).categories
    }

    /// Normalizes, de-duplicates, and deterministically orders the complete
    /// destination tables without dropping facts to fit a client-side budget.
    static func completeDestinationCandidates(
        tasks: [LLMTaskCandidate],
        categories: [LLMCategoryCandidate]
    ) -> LLMInboxSuggestionCandidates {
        LLMInboxSuggestionCandidates(
            tasks: uniqueRankedTasks(tasks).map(\.candidate),
            categories: uniqueRankedCategories(categories).map(\.candidate)
        )
    }

    static func sanitizedReason(_ reason: String) -> String {
        boundedTrimmedUTF8(reason, maximumByteCount: maximumReasonByteCount)
    }

    static func sanitizedSuggestedIcon(_ iconName: String) -> String {
        let normalized = normalizedText(iconName)
        return SymbolCatalog.symbolNameSet.contains(normalized)
            ? normalized
            : ChecklistVisualSanitizer.defaultIcon
    }

    static func sanitizedSuggestedColor(_ colorHex: String, fallback: String) -> String {
        let candidates = [
            normalizedText(colorHex),
            fallback,
            ChecklistVisualSanitizer.defaultColor,
        ]
        return candidates
            .lazy
            .compactMap(TaskColorPalette.normalizedHex)
            .first { TaskColorPalette.hexValues.contains($0) } ??
            ChecklistVisualSanitizer.defaultColor
    }

    static func sanitizedDestinationID(_ destinationID: String) -> UUID? {
        let trimmed = destinationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumTaskIDByteCount else { return nil }
        return UUID(uuidString: trimmed)
    }

    static func sanitizedTaskID(_ taskID: String) -> UUID? {
        sanitizedDestinationID(taskID)
    }

    static func boundedTrimmedUTF8(_ value: String, maximumByteCount: Int) -> String {
        guard maximumByteCount > 0 else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count > maximumByteCount else { return trimmed }

        var result = ""
        result.reserveCapacity(maximumByteCount)
        var byteCount = 0
        for character in trimmed {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct RankedCandidate {
        let candidate: LLMTaskCandidate
        let pathKey: String
        let titleKey: String
    }

    private struct RankedCategoryCandidate {
        let candidate: LLMCategoryCandidate
        let titleKey: String
    }

    private static func uniqueRankedTasks(
        _ candidates: [LLMTaskCandidate]
    ) -> [RankedCandidate] {
        let ranked = candidates.compactMap(normalizedCandidate).sorted(by: candidateSortsBefore)
        var acceptedIDs = Set<UUID>()
        return ranked.filter { acceptedIDs.insert($0.candidate.id).inserted }
    }

    private static func uniqueRankedCategories(
        _ candidates: [LLMCategoryCandidate]
    ) -> [RankedCategoryCandidate] {
        let ranked = candidates
            .compactMap(normalizedCategoryCandidate)
            .sorted(by: categoryCandidateSortsBefore)
        var acceptedIDs = Set<UUID>()
        return ranked.filter { acceptedIDs.insert($0.candidate.id).inserted }
    }

    private static func normalizedCandidate(_ candidate: LLMTaskCandidate) -> RankedCandidate? {
        let title = normalizedText(candidate.title)
        guard !title.isEmpty else { return nil }
        let normalizedPath = normalizedText(candidate.path)
        let path = normalizedPath.isEmpty ? title : normalizedPath
        let normalized = LLMTaskCandidate(
            id: candidate.id,
            title: title,
            path: path,
            iconName: ChecklistVisualSanitizer.sanitizedIcon(
                candidate.iconName
            ),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(
                candidate.colorHex
            )
        )
        return RankedCandidate(
            candidate: normalized,
            pathKey: path.lowercased(),
            titleKey: title.lowercased()
        )
    }

    private static func candidateSortsBefore(_ lhs: RankedCandidate, _ rhs: RankedCandidate) -> Bool {
        if lhs.pathKey != rhs.pathKey {
            return lhs.pathKey < rhs.pathKey
        }
        if lhs.candidate.path != rhs.candidate.path {
            return lhs.candidate.path < rhs.candidate.path
        }
        if lhs.titleKey != rhs.titleKey {
            return lhs.titleKey < rhs.titleKey
        }
        if lhs.candidate.title != rhs.candidate.title {
            return lhs.candidate.title < rhs.candidate.title
        }
        if lhs.candidate.iconName != rhs.candidate.iconName {
            return lhs.candidate.iconName < rhs.candidate.iconName
        }
        if lhs.candidate.colorHex != rhs.candidate.colorHex {
            return lhs.candidate.colorHex < rhs.candidate.colorHex
        }
        return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
    }

    private static func normalizedCategoryCandidate(
        _ candidate: LLMCategoryCandidate
    ) -> RankedCategoryCandidate? {
        let title = normalizedText(candidate.title)
        guard !title.isEmpty else { return nil }
        return RankedCategoryCandidate(
            candidate: LLMCategoryCandidate(
                id: candidate.id,
                title: title,
                iconName: ChecklistVisualSanitizer.sanitizedIcon(
                    candidate.iconName
                ),
                colorHex: ChecklistVisualSanitizer.sanitizedColor(
                    candidate.colorHex
                )
            ),
            titleKey: title.lowercased()
        )
    }

    private static func categoryCandidateSortsBefore(
        _ lhs: RankedCategoryCandidate,
        _ rhs: RankedCategoryCandidate
    ) -> Bool {
        if lhs.titleKey != rhs.titleKey {
            return lhs.titleKey < rhs.titleKey
        }
        if lhs.candidate.title != rhs.candidate.title {
            return lhs.candidate.title < rhs.candidate.title
        }
        if lhs.candidate.iconName != rhs.candidate.iconName {
            return lhs.candidate.iconName < rhs.candidate.iconName
        }
        if lhs.candidate.colorHex != rhs.candidate.colorHex {
            return lhs.candidate.colorHex < rhs.candidate.colorHex
        }
        return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
