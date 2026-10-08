import Foundation

nonisolated struct OverlapAnalyticsParticipant: Identifiable, Equatable, Comparable, Sendable {
    let id: UUID
    let title: String

    static func < (lhs: OverlapAnalyticsParticipant, rhs: OverlapAnalyticsParticipant) -> Bool {
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

nonisolated struct OverlapAnalyticsPoint: Identifiable, Equatable, Sendable {
    let start: Date
    let end: Date
    let concurrentSegmentCount: Int
    let participantCount: Int
    let visibleParticipants: [OverlapAnalyticsParticipant]
    let wallDurationSeconds: Int
    let excessDurationSeconds: Int

    var id: Date {
        start
    }

    var hiddenParticipantCount: Int {
        max(0, participantCount - visibleParticipants.count)
    }
}
