import Foundation

enum DurationFormatter {
    nonisolated static func compact(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let safeSeconds = max(0, seconds)
        let wholeMinutes = safeSeconds / 60
        let duration = Duration.seconds(wholeMinutes * 60)
        return duration.formatted(
            .units(
                allowed: [.hours, .minutes],
                width: .abbreviated,
                maximumUnitCount: 2
            )
            .locale(locale)
        )
    }

    nonisolated static func chart(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let safeSeconds = max(0, seconds)
        guard safeSeconds < 60 else {
            return compact(safeSeconds, locale: locale)
        }
        return Duration.seconds(safeSeconds).formatted(
            .units(
                allowed: [.seconds],
                width: .abbreviated,
                maximumUnitCount: 1
            )
            .locale(locale)
        )
    }

    nonisolated static func chartAxis(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let safeSeconds = max(0, seconds)
        guard safeSeconds % 60 != 0 else {
            return chart(safeSeconds, locale: locale)
        }
        return Duration.seconds(safeSeconds).formatted(
            .units(
                allowed: [.minutes, .seconds],
                width: .abbreviated,
                maximumUnitCount: 2
            )
            .locale(locale)
        )
    }

    nonisolated static func clock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let second = safeSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, second)
        }
        return String(format: "%02d:%02d", minutes, second)
    }

    nonisolated static func spoken(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .units(
                allowed: [.hours, .minutes, .seconds],
                width: .wide,
                maximumUnitCount: 3
            )
            .locale(locale)
        )
    }
}

enum TimeDisplayFormatter {
    nonisolated static func hourMinute(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .hour()
            .minute()
        )
    }

    nonisolated static func monthDayHourMinute(
        _ date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
            .month(.abbreviated)
            .day()
            .hour()
            .minute()
        )
    }
}
