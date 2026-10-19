import Foundation
import SwiftData

enum CountdownTitleValidationError: LocalizedError, Equatable {
    case empty
    case exceedsByteLimit
    case containsControlCharacters

    var errorDescription: String? {
        switch self {
        case .empty:
            AppStrings.localized("settings.countdown.title.error.empty")
        case .exceedsByteLimit:
            AppStrings.localized("settings.countdown.title.error.tooLong")
        case .containsControlCharacters:
            AppStrings.localized("settings.countdown.title.error.controlCharacters")
        }
    }
}

enum CountdownTitlePolicy {
    static let maximumUTF8ByteCount = PersistedFieldLimits.maximumTitleByteCount

    static func normalized(_ title: String) throws -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw CountdownTitleValidationError.empty
        }
        guard !normalizedTitle.unicodeScalars.contains(where: invalidScalarSet.contains) else {
            throw CountdownTitleValidationError.containsControlCharacters
        }
        guard normalizedTitle.utf8.count <= maximumUTF8ByteCount else {
            throw CountdownTitleValidationError.exceedsByteLimit
        }
        return normalizedTitle
    }

    private static let invalidScalarSet = CharacterSet.controlCharacters.union(.newlines)
}
