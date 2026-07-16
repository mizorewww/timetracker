import Foundation

struct OverlapAnalyticsParticipant: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct OverlapAnalyticsPoint: Identifiable {
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
