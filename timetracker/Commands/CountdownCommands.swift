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
    static let maximumUTF8ByteCount = SyncDataSnapshotRestoreLimits.maximumTitleByteCount

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

@MainActor
struct CountdownCommandHandler {
    @discardableResult
    func add(context: ModelContext, deviceID: String = DeviceIdentity.current) throws -> CountdownEvent {
        let title = try CountdownTitlePolicy.normalized(AppStrings.localized("task.newEvent"))
        let event = CountdownEvent(
            title: title,
            date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            deviceID: deviceID
        )
        context.insert(event)
        try context.saveAfterMutationStep()
        return event
    }

    func update(_ event: CountdownEvent, title: String? = nil, date: Date? = nil, context: ModelContext, now: Date = Date()) throws {
        let normalizedTitle = try title.map(CountdownTitlePolicy.normalized)

        if let normalizedTitle {
            event.title = normalizedTitle
        }
        if let date {
            event.date = date
        }
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func softDelete(_ event: CountdownEvent, context: ModelContext, now: Date = Date()) throws {
        event.deletedAt = now
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }
}
