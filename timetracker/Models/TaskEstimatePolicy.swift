import Foundation

enum TaskEstimatePolicy {
    static let minuteRange = 0...600
    static let maximumSeconds = minuteRange.upperBound * 60

    static func normalized(seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return min(seconds, maximumSeconds)
    }

    static func seconds(fromMinutes minutes: Int?) -> Int? {
        guard let minutes else { return nil }
        let normalizedMinutes = minutes.clamped(to: minuteRange)
        return normalizedMinutes == 0 ? nil : normalizedMinutes * 60
    }
}
