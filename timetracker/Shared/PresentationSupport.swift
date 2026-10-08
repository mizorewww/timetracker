import Foundation

/// Byte-bounds and clock helpers shared by every system-surface snapshot payload
/// (widget, watch, Live Activity). Each surface keeps its own limit *constants*
/// (AD-004 bounds stay); only the helper implementations live here.
nonisolated enum SystemSurfaceTextBounds {
    static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }

    static func isBounded(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        value.utf8.count <= maximumUTF8Bytes
    }

    static func isValidStyleValue(_ value: String?, maximumUTF8Bytes: Int) -> Bool {
        guard let value else { return true }
        return isBounded(value, maximumUTF8Bytes: maximumUTF8Bytes)
    }

    static func boundedUTF8Prefix(_ value: String, maximumUTF8Bytes: Int) -> String {
        guard value.utf8.count > maximumUTF8Bytes else { return value }
        var result = ""
        var byteCount = 0
        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumUTF8Bytes else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }

    static func boundedProjectedStyleValue(
        _ value: String?,
        maximumUTF8Bytes: Int
    ) -> String? {
        value.map { boundedUTF8Prefix($0, maximumUTF8Bytes: maximumUTF8Bytes) }
    }

    static func textByteCount(
        title: String,
        path: String,
        colorHex: String?,
        iconName: String?
    ) -> Int {
        title.utf8.count + path.utf8.count +
            (colorHex?.utf8.count ?? 0) + (iconName?.utf8.count ?? 0)
    }

    static func boundedTimerStart(
        _ startedAt: Date,
        generatedAt: Date,
        maximumActiveTimerAge: TimeInterval
    ) -> Date {
        guard isFinite(startedAt), isFinite(generatedAt) else { return generatedAt }
        return min(
            max(startedAt, generatedAt.addingTimeInterval(-maximumActiveTimerAge)),
            generatedAt
        )
    }
}

nonisolated enum ElapsedClockFormatter {
    static func padded(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let second = safeSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, second)
        }
        return String(format: "%02d:%02d", minutes, second)
    }

    static func compact(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let safeSeconds = max(0, seconds)
        let pattern: Duration.TimeFormatStyle.Pattern = safeSeconds >= 3600
            ? .hourMinuteSecond
            : .minuteSecond
        return formatted(safeSeconds, pattern: pattern, locale: locale)
    }

    static func full(
        _ seconds: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(
            max(0, seconds),
            pattern: .hourMinuteSecond,
            locale: locale
        )
    }

    private static func formatted(
        _ seconds: Int,
        pattern: Duration.TimeFormatStyle.Pattern,
        locale: Locale
    ) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: pattern).locale(locale)
        )
    }
}

nonisolated struct HexColorComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

nonisolated enum HexColorParser {
    static func normalized(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false
        else {
            return nil
        }
        if value.hasPrefix("#") {
            value.removeFirst()
        }
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6,
              UInt32(value, radix: 16) != nil
        else {
            return nil
        }
        return value.uppercased()
    }

    static func components(for value: String?) -> HexColorComponents? {
        guard let normalized = normalized(value),
              let rgb = UInt32(normalized, radix: 16)
        else {
            return nil
        }
        return HexColorComponents(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
