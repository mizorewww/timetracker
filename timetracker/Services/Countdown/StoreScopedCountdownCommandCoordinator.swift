import Foundation
import SwiftData

enum StoreScopedCountdownMutationError: LocalizedError, Equatable {
    case eventUnavailable

    var errorDescription: String? {
        switch self {
        case .eventUnavailable:
            AppStrings.localized("settings.countdown.error.unavailable")
        }
    }
}

/// Serializes countdown edits with the rest of the store mutation domain and
/// resolves the logical event by ID only after the lock is held, so a scene
/// never writes through an older SwiftData object or revives a tombstone.
@MainActor
struct StoreScopedCountdownCommandCoordinator {
    let session: StoreMutationSession
    let deviceID: String
    let nowProvider: () -> Date

    init(
        session: StoreMutationSession,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func add() throws {
        let title = try CountdownTitlePolicy.normalized(AppStrings.localized("task.newEvent"))
        try session.withFreshMutationContext { context in
            context.insert(CountdownEvent(
                title: title,
                date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                deviceID: deviceID
            ))
        }
    }

    func update(
        eventID: UUID,
        title: String?,
        date: Date?
    ) throws {
        let normalizedTitle = try title.map(CountdownTitlePolicy.normalized)
        try mutate(eventID: eventID) { event, _ in
            if let normalizedTitle {
                event.title = normalizedTitle
            }
            if let date {
                event.date = date
            }
        }
    }

    func delete(eventID: UUID) throws {
        try mutate(eventID: eventID) { event, now in
            event.deletedAt = now
        }
    }

    private func mutate(
        eventID: UUID,
        operation: (CountdownEvent, Date) -> Void
    ) throws {
        try session.withFreshMutationContext { context in
            let descriptor = FetchDescriptor<CountdownEvent>(
                predicate: #Predicate { $0.id == eventID }
            )
            guard let event = try context.fetch(descriptor)
                .deduplicatedByID()
                .first,
                event.deletedAt == nil
            else {
                throw StoreScopedCountdownMutationError.eventUnavailable
            }
            let now = nowProvider()
            operation(event, now)
            event.markMutated(at: now, deviceID: deviceID)
        }
    }
}
