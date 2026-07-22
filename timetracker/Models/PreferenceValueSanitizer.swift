import Foundation

enum LLMPromptInstructionsValidationError: LocalizedError, Equatable {
    case controlCharacter
    case byteLimitExceeded(actual: Int, maximum: Int)

    var errorDescription: String? {
        switch self {
        case .controlCharacter:
            AppStrings.localized("settings.llm.taskPlanInstructions.error.controlCharacter")
        case let .byteLimitExceeded(actual, maximum):
            String.localizedStringWithFormat(
                AppStrings.localized("settings.llm.taskPlanInstructions.error.tooLongFormat"),
                Int64(actual),
                Int64(maximum)
            )
        }
    }
}

typealias LLMTaskPlanInstructionsValidationError = LLMPromptInstructionsValidationError

enum AppPreferenceValueSanitizer {
    static let maximumPomodoroPlanCount = 24
    static let maximumPomodoroPlanNameLength = 80
    static let maximumQuickStartTaskCount = 24
    static let maximumTodayHeatmapTaskCount = 64
    nonisolated static let maximumLLMModelCount = 256
    nonisolated static let maximumLLMModelIDByteCount = 256
    static let maximumLLMEndpointLength = 2_048
    static let maximumLLMPromptInstructionsByteCount = 4 * 1_024
    static let maximumLLMTaskPlanInstructionsByteCount = maximumLLMPromptInstructionsByteCount

    static func preferredColorScheme(_ value: String) -> String {
        ["system", "light", "dark"].contains(value) ? value : "system"
    }

    static func pomodoroMode(_ value: String) -> String {
        if let preset = PomodoroPreset(rawValue: value) {
            return preset.rawValue
        }
        switch value.lowercased() {
        case "classic": return PomodoroPreset.classic.rawValue
        case "deep": return PomodoroPreset.deep.rawValue
        case "quick": return PomodoroPreset.quick.rawValue
        default: return PomodoroPreset.classic.rawValue
        }
    }

    static func pomodoroPlans(_ values: [PomodoroPlan]) -> [PomodoroPlan] {
        var seen = Set<UUID>()
        var result: [PomodoroPlan] = []
        result.reserveCapacity(min(values.count, maximumPomodoroPlanCount))
        for value in values where seen.insert(value.id).inserted {
            result.append(value.normalized())
            if result.count == maximumPomodoroPlanCount { break }
        }
        return result
    }

    static func pomodoroPlanName(_ value: String) -> String {
        boundedTrimmed(value, maximumLength: maximumPomodoroPlanNameLength)
    }

    static func quickStartTaskIDs(_ values: [UUID]) -> [UUID] {
        orderedTaskIDs(values, maximumCount: maximumQuickStartTaskCount)
    }

    static func todayHeatmapTaskIDs(_ values: [UUID]) -> [UUID] {
        orderedTaskIDs(values, maximumCount: maximumTodayHeatmapTaskCount)
    }

    private static func orderedTaskIDs(
        _ values: [UUID],
        maximumCount: Int
    ) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        result.reserveCapacity(min(values.count, maximumCount))
        for value in values where seen.insert(value).inserted {
            result.append(value)
            if result.count == maximumCount { break }
        }
        return result
    }

    static func llmEndpoint(_ value: String) -> String {
        boundedTrimmed(value, maximumLength: maximumLLMEndpointLength)
    }

    nonisolated static func llmModelID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumLLMModelIDByteCount,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return ""
        }
        return trimmed
    }

    nonisolated static func llmModelIDs(_ values: [String]) -> [String] {
        var accumulator = LLMModelIDAccumulator()
        for value in values {
            accumulator.insert(value)
        }
        return accumulator.values
    }

    static func llmPromptInstructions(
        _ value: String,
        defaultInstructions: String
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let resolved = normalized.isEmpty
            ? defaultInstructions
            : normalized

        let containsUnsupportedControl = resolved.unicodeScalars.contains { scalar in
            guard CharacterSet.controlCharacters.contains(scalar) else { return false }
            return scalar.value != 9 && scalar.value != 10
        }
        guard !containsUnsupportedControl else {
            throw LLMPromptInstructionsValidationError.controlCharacter
        }

        let actualByteCount = resolved.utf8.count
        guard actualByteCount <= maximumLLMPromptInstructionsByteCount else {
            throw LLMPromptInstructionsValidationError.byteLimitExceeded(
                actual: actualByteCount,
                maximum: maximumLLMPromptInstructionsByteCount
            )
        }
        return resolved
    }

    static func llmPromptInstructions(
        _ value: String,
        for kind: LLMPromptKind
    ) throws -> String {
        try llmPromptInstructions(
            value,
            defaultInstructions: kind.defaultInstructions
        )
    }

    static func llmTaskPlanInstructions(_ value: String) throws -> String {
        try llmPromptInstructions(value, for: .taskPlan)
    }

    static func llmInboxSuggestionInstructions(_ value: String) throws -> String {
        try llmPromptInstructions(value, for: .inboxRouting)
    }

    static func llmChecklistVisualInstructions(_ value: String) throws -> String {
        try llmPromptInstructions(value, for: .checklistVisual)
    }

    private static func boundedTrimmed(_ value: String, maximumLength: Int) -> String {
        let bounded = String(value.prefix(maximumLength + 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(bounded.prefix(maximumLength))
    }

    nonisolated struct LLMModelIDAccumulator {
        private(set) var values: [String] = []
        private var retainedValues = Set<String>()

        /// Keeps the same sorted-prefix policy as persisted preferences. Extra
        /// identifiers are truncated rather than turning a valid response into
        /// an error, while memory remains bounded by `maximumLLMModelCount`.
        mutating func insert(_ value: String) {
            let normalized = AppPreferenceValueSanitizer.llmModelID(value)
            guard !normalized.isEmpty,
                  !retainedValues.contains(normalized) else {
                return
            }

            if values.count == AppPreferenceValueSanitizer.maximumLLMModelCount,
               let greatestRetainedValue = values.last,
               normalized > greatestRetainedValue {
                return
            }

            let insertionIndex = insertionIndex(for: normalized)
            values.insert(normalized, at: insertionIndex)
            retainedValues.insert(normalized)

            if values.count > AppPreferenceValueSanitizer.maximumLLMModelCount {
                let removedValue = values.removeLast()
                retainedValues.remove(removedValue)
            }
        }

        private func insertionIndex(for value: String) -> Int {
            var lowerBound = values.startIndex
            var upperBound = values.endIndex

            while lowerBound < upperBound {
                let midpoint = lowerBound + (upperBound - lowerBound) / 2
                if values[midpoint] < value {
                    lowerBound = midpoint + 1
                } else {
                    upperBound = midpoint
                }
            }
            return lowerBound
        }
    }
}
