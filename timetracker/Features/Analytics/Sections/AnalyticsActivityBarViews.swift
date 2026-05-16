import SwiftUI

struct HourTaskActivityBar: View {
    let point: HourTaskActivity
    let availableHeight: CGFloat
    private let sliceSpacing: CGFloat = 1
    private let cornerRadius: CGFloat = 4

    private var minSliceHeight: CGFloat {
        max(5, min(8, availableHeight * 0.05))
    }

    private var visibleSliceCount: Int {
        let activeSliceCount = point.slices.filter { $0.seconds > 0 }.count
        let capacity = HourStackLayoutEngine.maxVisibleSliceCount(
            availableHeight: Double(max(0, availableHeight)),
            minSliceHeight: Double(minSliceHeight)
        )
        return min(activeSliceCount, capacity)
    }

    private var contentHeight: CGFloat {
        let sliceCount = CGFloat(max(visibleSliceCount - 1, 0))
        return max(0, availableHeight - sliceCount * sliceSpacing)
    }

    private var renderedSlices: [RenderedHourTaskSlice] {
        let inputs = point.slices.map { HourStackLayoutInput(id: $0.id, seconds: $0.seconds) }
        let layouts = HourStackLayoutEngine.layout(
            inputs: inputs,
            availableHeight: Double(max(0, contentHeight)),
            minSliceHeight: Double(minSliceHeight),
            maxItems: visibleSliceCount
        )
        let slicesByID = point.slices.reduce(into: [UUID: HourTaskSlice]()) { result, slice in
            result[slice.id] = slice
        }
        return layouts.compactMap { layout in
            guard let slice = slicesByID[layout.id] else { return nil }
            return RenderedHourTaskSlice(slice: slice, height: CGFloat(layout.height))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if point.totalSeconds > 0, renderedSlices.isEmpty == false {
                VStack(spacing: sliceSpacing) {
                    ForEach(Array(renderedSlices.reversed())) { rendered in
                        Rectangle()
                            .fill(rendered.slice.color)
                            .frame(height: rendered.height)
                    }
                }
                .frame(height: availableHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .help("\(String(format: "%02d:00", point.hour)) \(DurationFormatter.compact(point.totalSeconds))")
    }
}

private struct RenderedHourTaskSlice: Identifiable {
    let slice: HourTaskSlice
    let height: CGFloat

    var id: UUID { slice.id }
}

struct AnalyticsLegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
