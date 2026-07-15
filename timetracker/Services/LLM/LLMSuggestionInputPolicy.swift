import Foundation

nonisolated struct LLMInboxSuggestionPreparedInput: Equatable, Sendable {
    let inboxTitle: String
    let candidates: [LLMTaskCandidate]
    let modelID: String
}

nonisolated struct LLMChecklistVisualSuggestionPreparedInput: Equatable, Sendable {
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let modelID: String
}

nonisolated enum LLMSuggestionInputPolicy {
    static let maximumCandidateCount = 48
    static let maximumCandidateJSONByteCount = 16 * 1_024
    static let maximumInboxTitleByteCount = 512
    static let maximumChecklistTitleByteCount = 512
    static let maximumTaskTitleByteCount = 512
    static let maximumTaskPathByteCount = 1_024
    static let maximumCandidateTitleByteCount = 256
    static let maximumCandidatePathByteCount = 512
    static let maximumIconNameByteCount = 128
    static let maximumColorByteCount = 32
    // AI provenance is persisted in sync snapshot compact fields. Keep this
    // producer limit aligned with the restore contract so locally-created
    // suggestions always remain restorable.
    static let maximumModelIDByteCount = 256
    static let maximumReasonByteCount = 512
    static let maximumPromptByteCount = 24 * 1_024
    static let maximumRequestBodyByteCount = 32 * 1_024
    static let maximumEndpointByteCount = 4 * 1_024
    static let maximumAPIKeyByteCount = 8 * 1_024
    static let maximumTaskIDByteCount = 64

    static func prepare(
        inboxTitle: String,
        candidates: [LLMTaskCandidate],
        modelID: String
    ) -> LLMInboxSuggestionPreparedInput {
        LLMInboxSuggestionPreparedInput(
            inboxTitle: boundedTrimmedUTF8(
                inboxTitle,
                maximumByteCount: maximumInboxTitleByteCount
            ),
            candidates: boundedCandidates(candidates),
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
        let ranked = candidates.compactMap(normalizedCandidate).sorted(by: candidateSortsBefore)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var accepted: [LLMTaskCandidate] = []
        accepted.reserveCapacity(min(ranked.count, maximumCandidateCount))
        var acceptedIDs = Set<UUID>()
        var encodedByteCount = 2 // Opening and closing array delimiters.

        for rankedCandidate in ranked {
            guard accepted.count < maximumCandidateCount else { break }
            let candidate = rankedCandidate.candidate
            guard !acceptedIDs.contains(candidate.id),
                  let encoded = try? encoder.encode(candidate) else {
                continue
            }
            let separatorByteCount = accepted.isEmpty ? 0 : 1
            guard encodedByteCount + separatorByteCount + encoded.count <= maximumCandidateJSONByteCount else {
                continue
            }
            acceptedIDs.insert(candidate.id)
            accepted.append(candidate)
            encodedByteCount += separatorByteCount + encoded.count
        }
        return accepted
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
        ChecklistVisualSanitizer.sanitizedColor(
            boundedTrimmedUTF8(colorHex, maximumByteCount: maximumColorByteCount),
            fallback: fallback
        )
    }

    static func sanitizedTaskID(_ taskID: String) -> UUID? {
        let trimmed = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumTaskIDByteCount else { return nil }
        return UUID(uuidString: trimmed)
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
        if lhs.pathKey != rhs.pathKey { return lhs.pathKey < rhs.pathKey }
        if lhs.candidate.path != rhs.candidate.path { return lhs.candidate.path < rhs.candidate.path }
        if lhs.titleKey != rhs.titleKey { return lhs.titleKey < rhs.titleKey }
        if lhs.candidate.title != rhs.candidate.title { return lhs.candidate.title < rhs.candidate.title }
        return lhs.candidate.id.uuidString < rhs.candidate.id.uuidString
    }
}
