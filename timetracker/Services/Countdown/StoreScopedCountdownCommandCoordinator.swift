import Foundation
import SwiftData

struct CountdownMutationBaseline: Equatable, Sendable {
    let eventID: UUID
    let clientMutationID: UUID

    init(event: CountdownEvent) {
        eventID = event.id
        clientMutationID = event.clientMutationID
    }
}

enum StoreScopedCountdownMutationError: LocalizedError, Equatable {
    case eventUnavailable
    case eventChanged

    var errorDescription: String? {
        switch self {
        case .eventUnavailable:
            AppStrings.localized("settings.countdown.error.unavailable")
        case .eventChanged:
            AppStrings.localized("settings.countdown.error.changed")
        }
    }
}

/// Serializes countdown edits with the rest of the store mutation domain and
/// resolves the logical event only after the lock is held. A scene must not
/// write through an older SwiftData object after another scene has updated or
/// tombstoned the same logical event.
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
        baseline: CountdownMutationBaseline,
        title: String?,
        date: Date?
    ) throws {
        let normalizedTitle = try title.map(CountdownTitlePolicy.normalized)
        try mutate(baseline: baseline) { event, _ in
            if let normalizedTitle {
                event.title = normalizedTitle
            }
            if let date {
                event.date = date
            }
        }
    }

    func delete(baseline: CountdownMutationBaseline) throws {
        try mutate(baseline: baseline) { event, now in
            event.deletedAt = now
        }
    }

    private func mutate(
        baseline: CountdownMutationBaseline,
        operation: (CountdownEvent, Date) -> Void
    ) throws {
        try session.withFreshMutationContext { context in
            let eventID = baseline.eventID
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
            guard event.clientMutationID == baseline.clientMutationID else {
                throw StoreScopedCountdownMutationError.eventChanged
            }
            let now = nowProvider()
            operation(event, now)
            event.markMutated(at: now, deviceID: deviceID)
        }
    }
}
