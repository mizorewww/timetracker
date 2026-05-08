import Foundation

struct HourStackLayoutInput: Equatable {
    let id: UUID
    let seconds: Int
}

struct HourStackLayoutItem: Identifiable, Equatable {
    let id: UUID
    let height: Double
}

enum HourStackLayoutEngine {
    static func maxVisibleSliceCount(availableHeight: Double, minSliceHeight: Double) -> Int {
        guard availableHeight > 0, minSliceHeight > 0 else { return 0 }
        return max(1, Int(floor(availableHeight / minSliceHeight)) - 1)
    }

    static func layout(
        inputs: [HourStackLayoutInput],
        availableHeight: Double,
        minSliceHeight: Double,
        maxItems: Int? = nil
    ) -> [HourStackLayoutItem] {
        let sorted = inputs
            .filter { $0.seconds > 0 }
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.seconds > rhs.seconds
            }
        guard availableHeight > 0, minSliceHeight > 0, !sorted.isEmpty else { return [] }

        let capacity = maxItems ?? maxVisibleSliceCount(availableHeight: availableHeight, minSliceHeight: minSliceHeight)
        let visible = Array(sorted.prefix(capacity))
        let effectiveMinSliceHeight = min(minSliceHeight, availableHeight / Double(max(visible.count, 1)))
        let totalSeconds = max(1, visible.reduce(0) { $0 + $1.seconds })
        var heights = visible.map { input in
            availableHeight * Double(input.seconds) / Double(totalSeconds)
        }

        var deficit = 0.0
        for index in heights.indices where heights[index] < effectiveMinSliceHeight {
            deficit += effectiveMinSliceHeight - heights[index]
            heights[index] = effectiveMinSliceHeight
        }

        while deficit > 0.0001 {
            guard let donorIndex = heights.indices
                .filter({ heights[$0] > effectiveMinSliceHeight })
                .max(by: { heights[$0] < heights[$1] })
            else {
                break
            }
            let take = min(deficit, heights[donorIndex] - effectiveMinSliceHeight)
            heights[donorIndex] -= take
            deficit -= take
        }

        return zip(visible, heights).map { input, height in
            HourStackLayoutItem(id: input.id, height: height)
        }
    }
}
