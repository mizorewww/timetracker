import Foundation
import SwiftData

extension TimeTrackerStore {
    func migrateLegacyCountdownEventsIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard !defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey) else {
            defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.payloadKey)
            return
        }
        guard let json = defaults.string(forKey: LegacyCountdownMigrationPolicy.payloadKey) else {
            return
        }

        let existing = try context.fetch(FetchDescriptor<CountdownEvent>())
        guard existing.isEmpty else {
            finishLegacyCountdownMigration(defaults: defaults)
            return
        }

        for legacy in LegacyCountdownMigrationPolicy.decode(json) {
            let event = CountdownEvent(
                title: legacy.title,
                date: legacy.date,
                deviceID: deviceID
            )
            if let id = legacy.id {
                event.id = id
            }
            context.insert(event)
        }
        try context.save()
        finishLegacyCountdownMigration(defaults: defaults)
    }

    private func finishLegacyCountdownMigration(defaults: UserDefaults) {
        defaults.set(true, forKey: LegacyCountdownMigrationPolicy.migrationKey)
        defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.payloadKey)
    }
}

enum LegacyCountdownMigrationPolicy {
    static let payloadKey = "CountdownEventsJSON"
    static let migrationKey = "CountdownEventsMigratedToSwiftData"
    static let maximumPayloadByteCount = 256 * 1_024
    static let maximumEventCount = 256
    static let maximumTitleByteCount = 4 * 1_024
    static let earliestSupportedDate = Date(timeIntervalSince1970: -2_208_988_800)
    static let latestSupportedDate = Date(timeIntervalSince1970: 7_289_654_400)

    static func decode(_ json: String) -> [LegacyCountdownEvent] {
        guard json.utf8.count <= maximumPayloadByteCount,
              let data = json.data(using: .utf8) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(LegacyCountdownPayload.self, from: data) else {
            return []
        }
        return payload.events.sorted { $0.date < $1.date }
    }

    static func accepts(_ event: LegacyCountdownEvent) -> Bool {
        event.title.utf8.count <= maximumTitleByteCount &&
            event.date >= earliestSupportedDate &&
            event.date < latestSupportedDate &&
            event.date.timeIntervalSinceReferenceDate.isFinite
    }
}

struct LegacyCountdownEvent: Decodable {
    let id: UUID?
    let title: String
    let date: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.contains(.id) ? try container.decode(UUID.self, forKey: .id) : nil
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
    }
}

private struct LegacyCountdownPayload: Decodable {
    let events: [LegacyCountdownEvent]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        if let count = container.count,
           count > LegacyCountdownMigrationPolicy.maximumEventCount {
            throw LegacyCountdownPayloadError.tooManyEvents
        }

        var decoded: [LegacyCountdownEvent] = []
        var seenIDs: Set<UUID> = []
        var sourceCount = 0
        while !container.isAtEnd {
            guard sourceCount < LegacyCountdownMigrationPolicy.maximumEventCount else {
                throw LegacyCountdownPayloadError.tooManyEvents
            }
            sourceCount += 1
            let elementDecoder = try container.superDecoder()
            guard let event = try? LegacyCountdownEvent(from: elementDecoder),
                  LegacyCountdownMigrationPolicy.accepts(event),
                  event.id.map({ seenIDs.insert($0).inserted }) ?? true else {
                continue
            }
            decoded.append(event)
        }
        events = decoded
    }
}

private enum LegacyCountdownPayloadError: Error { case tooManyEvents }
