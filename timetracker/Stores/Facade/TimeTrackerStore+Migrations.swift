import Foundation
import SwiftData

extension TimeTrackerStore {
    func migrateLegacyCountdownEventsIfNeeded(context: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: "CountdownEventsMigratedToSwiftData"),
              let json = UserDefaults.standard.string(forKey: "CountdownEventsJSON") else {
            return
        }

        let existing = try context.fetch(FetchDescriptor<CountdownEvent>())
        guard existing.isEmpty else {
            UserDefaults.standard.set(true, forKey: "CountdownEventsMigratedToSwiftData")
            return
        }

        for legacy in LegacyCountdownEvent.decode(json) {
            context.insert(
                CountdownEvent(
                    title: legacy.title,
                    date: legacy.date,
                    deviceID: DeviceIdentity.current
                )
            )
        }
        try context.save()
        UserDefaults.standard.set(true, forKey: "CountdownEventsMigratedToSwiftData")
    }
}

private struct LegacyCountdownEvent: Codable {
    var title: String
    var date: Date

    static func decode(_ json: String) -> [LegacyCountdownEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = json.data(using: .utf8),
              let events = try? decoder.decode([LegacyCountdownEvent].self, from: data) else {
            return []
        }
        return events.sorted { $0.date < $1.date }
    }
}
