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
    static let maximumCandidateCount = 48
    // Candidate JSON is embedded as a JSON string in the outer chat request.
    // Leave enough headroom for the second escaping pass and fixed prompt data.
    static let maximumCandidateJSONByteCount = 12 * 1024
    static let maximumInboxTitleByteCount = 512
    static let maximumChecklistTitleByteCount = 512
    static let maximumTaskTitleByteCount = 512
    static let maximumTaskPathByteCount = 1024
    static let maximumCandidateTitleByteCount = 256
    static let maximumCandidatePathByteCount = 512
    static let maximumIconNameByteCount = 128
    static let maximumColorByteCount = 32
    // AI provenance is persisted in sync snapshot compact fields. Keep this
    // producer limit aligned with the restore contract so locally-created
    // suggestions always remain restorable.
    static let maximumModelIDByteCount = 256
    static let maximumReasonByteCount = 512
    static let maximumPromptByteCount = 24 * 1024
    // The prompt is embedded as a JSON string in the outer request. A valid
    // prompt made entirely of quotes or backslashes can nearly double during
    // that second encoding pass, so keep a bounded envelope with enough room
    // for the full prompt plus the fixed system message and request metadata.
    static let maximumRequestBodyByteCount = 64 * 1024
    static let maximumEndpointByteCount = 4 * 1024
    static let maximumAPIKeyByteCount = 8 * 1024
    static let maximumTaskIDByteCount = 64

    static func prepare(
        inboxTitle: String,
        taskCandidates: [LLMTaskCandidate],
        categoryCandidates: [LLMCategoryCandidate],
        modelID: String
    ) -> LLMInboxSuggestionPreparedInput {
        let boundedCandidates = boundedDestinationCandidates(
            tasks: taskCandidates,
            categories: categoryCandidates
        )
        return LLMInboxSuggestionPreparedInput(
            inboxTitle: boundedTrimmedUTF8(
                inboxTitle,
                maximumByteCount: maximumInboxTitleByteCount
            ),
            taskCandidates: boundedCandidates.tasks,
            categoryCandidates: boundedCandidates.categories,
            modelID: boundedTrimmedUTF8(
                modelID,
                maximumByteCount: maximumModelIDByteCount
            )
        )
    }

    static func prepareChecklistVisual(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        modelID: String
    ) -> LLMChecklistVisualSuggestionPreparedInput {
        LLMChecklistVisualSuggestionPreparedInput(
            checklistTitle: boundedTrimmedUTF8(
                checklistTitle,
                maximumByteCount: maximumChecklistTitleByteCount
            ),
            taskTitle: boundedTrimmedUTF8(
                taskTitle,
                maximumByteCount: maximumTaskTitleByteCount
            ),
            taskPath: boundedTrimmedUTF8(
                taskPath,
                maximumByteCount: maximumTaskPathByteCount
            ),
            modelID: boundedTrimmedUTF8(
                modelID,
                maximumByteCount: maximumModelIDByteCount
            )
        )
    }

    static func boundedCandidates(_ candidates: [LLMTaskCandidate]) -> [LLMTaskCandidate] {
        boundedDestinationCandidates(tasks: candidates, categories: []).tasks
    }

    static func boundedCategoryCandidates(
        _ candidates: [LLMCategoryCandidate]
    ) -> [LLMCategoryCandidate] {
        boundedDestinationCandidates(tasks: [], categories: candidates).categories
    }

    /// Applies one shared count and encoded-byte budget to both destination
    /// tables. Categories are considered before tasks in every round so an
    /// available category cannot be displaced by a full task window.
    static func boundedDestinationCandidates(
        tasks: [LLMTaskCandidate],
        categories: [LLMCategoryCandidate]
    ) -> LLMInboxSuggestionCandidates {
        let rankedTasks = uniqueRankedTasks(tasks)
        let rankedCategories = uniqueRankedCategories(categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var acceptedTasks: [LLMTaskCandidate] = []
        var acceptedCategories: [LLMCategoryCandidate] = []
        acceptedTasks.reserveCapacity(min(rankedTasks.count, maximumCandidateCount))
        acceptedCategories.reserveCapacity(min(rankedCategories.count, maximumCandidateCount))
        var taskIndex = 0
        var categoryIndex = 0

        func canAccept(
            tasks: [LLMTaskCandidate],
            categories: [LLMCategoryCandidate]
        ) -> Bool {
            guard tasks.count + categories.count <= maximumCandidateCount else {
                return false
            }
            let payload = LLMInboxSuggestionCandidates(
                tasks: tasks,
                categories: categories
            )
            guard let data = try? encoder.encode(payload) else { return false }
            return data.count <= maximumCandidateJSONByteCount
        }

        while taskIndex < rankedTasks.count || categoryIndex < rankedCategories.count {
            guard acceptedTasks.count + acceptedCategories.count < maximumCandidateCount else {
                break
            }

            if categoryIndex < rankedCategories.count {
                let candidate = rankedCategories[categoryIndex].candidate
                categoryIndex += 1
                let proposed = acceptedCategories + [candidate]
                if canAccept(tasks: acceptedTasks, categories: proposed) {
                    acceptedCategories = proposed
                }
            }

            guard acceptedTasks.count + acceptedCategories.count < maximumCandidateCount else {
                break
            }

            if taskIndex < rankedTasks.count {
                let candidate = rankedTasks[taskIndex].candidate
                taskIndex += 1
                let proposed = acceptedTasks + [candidate]
                if canAccept(tasks: proposed, categories: acceptedCategories) {
                    acceptedTasks = proposed
                }
            }
        }

        return LLMInboxSuggestionCandidates(
            tasks: acceptedTasks,
            categories: acceptedCategories
        )
    }

    static func sanitizedReason(_ reason: String) -> String {
        boundedTrimmedUTF8(reason, maximumByteCount: maximumReasonByteCount)
    }

    static func sanitizedSuggestedIcon(_ iconName: String) -> String {
        let bounded = boundedTrimmedUTF8(
            iconName,
            maximumByteCount: maximumIconNameByteCount
        )
        return SymbolCatalog.aiSuggestionSymbolNameSet.contains(bounded)
            ? bounded
            : ChecklistVisualSanitizer.defaultIcon
    }

    static func sanitizedSuggestedColor(_ colorHex: String, fallback: String) -> String {
        let candidates = [
            boundedTrimmedUTF8(colorHex, maximumByteCount: maximumColorByteCount),
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
        let title = boundedTrimmedUTF8(
            candidate.title,
            maximumByteCount: maximumCandidateTitleByteCount
        )
        guard !title.isEmpty else { return nil }
        let boundedPath = boundedTrimmedUTF8(
            candidate.path,
            maximumByteCount: maximumCandidatePathByteCount
        )
        let path = boundedPath.isEmpty ? title : boundedPath
        let boundedIcon = boundedTrimmedUTF8(
            candidate.iconName,
            maximumByteCount: maximumIconNameByteCount
        )
        let boundedColor = boundedTrimmedUTF8(
            candidate.colorHex,
            maximumByteCount: maximumColorByteCount
        )
        let normalized = LLMTaskCandidate(
            id: candidate.id,
            title: title,
            path: path,
            iconName: ChecklistVisualSanitizer.sanitizedIcon(boundedIcon),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(boundedColor)
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
        let title = boundedTrimmedUTF8(
            candidate.title,
            maximumByteCount: maximumCandidateTitleByteCount
        )
        guard !title.isEmpty else { return nil }
        let boundedIcon = boundedTrimmedUTF8(
            candidate.iconName,
            maximumByteCount: maximumIconNameByteCount
        )
        let boundedColor = boundedTrimmedUTF8(
            candidate.colorHex,
            maximumByteCount: maximumColorByteCount
        )
        return RankedCategoryCandidate(
            candidate: LLMCategoryCandidate(
                id: candidate.id,
                title: title,
                iconName: ChecklistVisualSanitizer.sanitizedIcon(boundedIcon),
                colorHex: ChecklistVisualSanitizer.sanitizedColor(boundedColor)
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
}
