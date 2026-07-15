import Foundation

enum AppPreferenceValueSanitizer {
    static let maximumPomodoroPlanCount = 24
    static let maximumPomodoroPlanNameLength = 80
    static let maximumQuickStartTaskCount = 24
    static let maximumLLMModelCount = 256
    static let maximumLLMModelIDByteCount = 256
    static let maximumLLMEndpointLength = 2_048

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
        var seen = Set<UUID>()
        var result: [UUID] = []
        result.reserveCapacity(min(values.count, maximumQuickStartTaskCount))
        for value in values where seen.insert(value).inserted {
            result.append(value)
            if result.count == maximumQuickStartTaskCount { break }
        }
        return result
    }

    static func llmEndpoint(_ value: String) -> String {
        boundedTrimmed(value, maximumLength: maximumLLMEndpointLength)
    }

    static func llmModelID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= maximumLLMModelIDByteCount,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return ""
        }
        return trimmed
    }

    static func llmModelIDs(_ values: [String]) -> [String] {
        var normalizedValues = Set<String>()
        for value in values {
            let normalized = llmModelID(value)
            if !normalized.isEmpty {
                normalizedValues.insert(normalized)
            }
        }
        let uniqueValues = normalizedValues.sorted()
        return Array(uniqueValues.prefix(maximumLLMModelCount))
    }

    private static func boundedTrimmed(_ value: String, maximumLength: Int) -> String {
        let bounded = String(value.prefix(maximumLength + 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(bounded.prefix(maximumLength))
    }
}
