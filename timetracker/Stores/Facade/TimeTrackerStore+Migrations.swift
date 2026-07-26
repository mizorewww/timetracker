import Foundation
import SwiftData

extension TimeTrackerStore {
    func migrateLegacyCountdownEventsIfNeeded(
        context: ModelContext,
        defaults: UserDefaults = AppDefaults.shared,
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
        let canonicalExisting = existing.deduplicatedByID()
        var existingIDs = Set(canonicalExisting.map(\.id))
        var availableFingerprintCounts = Dictionary(
            grouping: canonicalExisting,
            by: { LegacyCountdownFingerprint($0) }
        ).mapValues(\.count)

        for legacy in try LegacyCountdownMigrationPolicy.decode(json) {
            if let id = legacy.id {
                guard existingIDs.insert(id).inserted else { continue }
            } else {
                let fingerprint = LegacyCountdownFingerprint(legacy)
                if let count = availableFingerprintCounts[fingerprint], count > 0 {
                    availableFingerprintCounts[fingerprint] = count - 1
                    continue
                }
            }
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
    static let maximumPayloadByteCount = 256 * 1024
    static let maximumEventCount = 256
    static let maximumTitleByteCount = 4 * 1024
    static let earliestSupportedDate = Date(timeIntervalSince1970: -2_208_988_800)
    static let latestSupportedDate = Date(timeIntervalSince1970: 7_289_654_400)

    static func decode(_ json: String) throws -> [LegacyCountdownEvent] {
        guard json.utf8.count <= maximumPayloadByteCount else {
            throw LegacyCountdownPayloadError.payloadTooLarge
        }
        guard let data = json.data(using: .utf8) else {
            throw LegacyCountdownPayloadError.invalidPayload
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(LegacyCountdownPayload.self, from: data)
            return payload.events.sorted { $0.date < $1.date }
        } catch let error as LegacyCountdownPayloadError {
            throw error
        } catch {
            throw LegacyCountdownPayloadError.invalidPayload
        }
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
           count > LegacyCountdownMigrationPolicy.maximumEventCount
        {
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
                  event.id.map({ seenIDs.insert($0).inserted }) ?? true
            else {
                continue
            }
            decoded.append(event)
        }
        events = decoded
    }
}

private enum LegacyCountdownPayloadError: LocalizedError {
    case payloadTooLarge
    case tooManyEvents
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .payloadTooLarge:
            AppStrings.localized("migration.countdown.error.payloadTooLarge")
        case .tooManyEvents:
            AppStrings.localized("migration.countdown.error.tooManyEvents")
        case .invalidPayload:
            AppStrings.localized("migration.countdown.error.invalidPayload")
        }
    }
}

private struct LegacyCountdownFingerprint: Hashable {
    let title: String
    let date: Date

    init(_ event: CountdownEvent) {
        title = event.title
        date = event.date
    }

    init(_ event: LegacyCountdownEvent) {
        title = event.title
        date = event.date
    }
}
