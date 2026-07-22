import Foundation

enum PreferenceJSONError: Error, Equatable, LocalizedError {
    case invalidValue
    case payloadTooLarge
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidValue:
            AppStrings.localized("preference.error.invalidValue")
        case .payloadTooLarge:
            AppStrings.localized("preference.error.payloadTooLarge")
        case .encodingFailed:
            AppStrings.localized("preference.error.encodingFailed")
        }
    }
}

enum PreferenceJSON {
    static let maximumPayloadByteCount = 256 * 1_024

    /// Compatibility helper for non-persistence call sites and fixtures.
    /// Persistence boundaries must use `encodeChecked` or canonicalize the
    /// result so an encoding failure can never be stored as JSON `null`.
    static func encode<T: Encodable>(_ value: T) -> String {
        (try? encodeChecked(value)) ?? "null"
    }

    static func encodeChecked<T: Encodable>(_ value: T) throws -> String {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw PreferenceJSONError.encodingFailed
        }
        guard data.count <= maximumPayloadByteCount else {
            throw PreferenceJSONError.payloadTooLarge
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw PreferenceJSONError.encodingFailed
        }
        return string
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String, default defaultValue: T) -> T {
        (try? decodeChecked(type, from: json)) ?? defaultValue
    }

    static func decodeChecked<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard json.utf8.count <= maximumPayloadByteCount else {
            throw PreferenceJSONError.payloadTooLarge
        }
        guard let data = json.data(using: .utf8) else {
            throw PreferenceJSONError.invalidValue
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw PreferenceJSONError.invalidValue
        }
    }

    /// Validates a preference against its declared type and re-encodes its
    /// normalized value. This is the only accepted path for persisted writes.
    static func canonicalValueJSON(
        for key: AppPreferenceKey,
        from valueJSON: String
    ) throws -> String {
        switch key {
        case .preferredColorScheme:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.preferredColorScheme(value))
        case .pomodoroDefaultMode:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.pomodoroMode(value))
        case .defaultFocusMinutes, .defaultBreakMinutes:
            let value = try decodeChecked(Int.self, from: valueJSON)
            return try encodeChecked(value.clamped(to: 1...480))
        case .defaultPomodoroRounds:
            let value = try decodeChecked(Int.self, from: valueJSON)
            return try encodeChecked(value.clamped(to: 1...24))
        case .pomodoroPlans:
            let value = try decodeChecked([PomodoroPlan].self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.pomodoroPlans(value))
        case .allowParallelTimers, .showGrossAndWallTogether:
            let value = try decodeChecked(Bool.self, from: valueJSON)
            return try encodeChecked(value)
        case .quickStartTaskIDs:
            let value = try decodeChecked([String].self, from: valueJSON)
            let identifiers = AppPreferenceValueSanitizer.quickStartTaskIDs(
                value.compactMap(UUID.init(uuidString:))
            )
            return try encodeChecked(identifiers.map(\.uuidString))
        case .todayHeatmapTaskIDs:
            let value = try decodeChecked([String].self, from: valueJSON)
            let identifiers = AppPreferenceValueSanitizer.todayHeatmapTaskIDs(
                value.compactMap(UUID.init(uuidString:))
            )
            return try encodeChecked(identifiers.map(\.uuidString))
        case .llmEndpoint:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.llmEndpoint(value))
        case .llmSelectedModel:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.llmModelID(value))
        case .llmAvailableModelIDs:
            let value = try decodeChecked([String].self, from: valueJSON)
            return try encodeChecked(AppPreferenceValueSanitizer.llmModelIDs(value))
        case .llmInboxSuggestionInstructions:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(
                try AppPreferenceValueSanitizer.llmInboxSuggestionInstructions(value)
            )
        case .llmChecklistVisualInstructions:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(
                try AppPreferenceValueSanitizer.llmChecklistVisualInstructions(value)
            )
        case .llmTaskPlanInstructions:
            let value = try decodeChecked(String.self, from: valueJSON)
            return try encodeChecked(
                try AppPreferenceValueSanitizer.llmTaskPlanInstructions(value)
            )
        }
    }
}
