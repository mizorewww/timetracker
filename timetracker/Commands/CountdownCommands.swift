import Foundation
import SwiftData

@MainActor
struct CountdownCommandHandler {
    @discardableResult
    func add(context: ModelContext, deviceID: String = DeviceIdentity.current) throws -> CountdownEvent {
        let event = CountdownEvent(
            title: AppStrings.localized("task.newEvent"),
            date: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
            deviceID: deviceID
        )
        context.insert(event)
        try context.save()
        return event
    }

    func update(_ event: CountdownEvent, title: String? = nil, date: Date? = nil, context: ModelContext, now: Date = Date()) throws {
        if let title {
            event.title = title
        }
        if let date {
            event.date = date
        }
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.save()
    }

    func softDelete(_ event: CountdownEvent, context: ModelContext, now: Date = Date()) throws {
        event.deletedAt = now
        event.updatedAt = now
        event.clientMutationID = UUID()
        try context.save()
    }
}
