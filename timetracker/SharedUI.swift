import SwiftData
import SwiftUI

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct TaskIcon: View {
    let task: TaskNode?
    var size: CGFloat = 38

    var body: some View {
        let tint = Color(hex: task?.colorHex) ?? .blue
        Image(systemName: task?.iconName ?? "checkmark.circle")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppLayout.iconRadius, style: .continuous))
    }
}

struct DurationLabel: View {
    let startedAt: Date
    let endedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let end = endedAt ?? context.date
            Text(DurationFormatter.clock(Int(end.timeIntervalSince(startedAt))))
        }
    }
}

struct EmptyStateRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

struct ForecastExplanationCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(.app("forecast.explainer.title"))
                    .font(.caption.weight(.semibold))
                Text(.app("forecast.explainer.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1)
        )
    }
}

struct ForecastInfoButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(AppStrings.localized("forecast.info.title"))
        .popover(isPresented: $isPresented) {
            ForecastInfoView()
                .frame(minWidth: 320, idealWidth: 420, maxWidth: 520, minHeight: 420)
        }
    }
}

struct ForecastInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    InfoGuideRow(
                        icon: "checklist",
                        title: AppStrings.localized("forecast.info.requirements.title"),
                        bodyText: AppStrings.localized("forecast.info.requirements.body")
                    )
                    InfoGuideRow(
                        icon: "function",
                        title: AppStrings.localized("forecast.info.formula.title"),
                        bodyText: AppStrings.localized("forecast.info.formula.body")
                    )
                    InfoGuideRow(
                        icon: "folder.badge.gearshape",
                        title: AppStrings.localized("forecast.info.children.title"),
                        bodyText: AppStrings.localized("forecast.info.children.body")
                    )
                    InfoGuideRow(
                        icon: "archivebox",
                        title: AppStrings.localized("forecast.info.history.title"),
                        bodyText: AppStrings.localized("forecast.info.history.body")
                    )
                }

                Section(AppStrings.localized("forecast.info.example.title")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.localized("forecast.info.example.body"))
                            .font(.subheadline)
                        ProgressView(value: 0.25)
                        HStack {
                            Label("1/4", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Text(AppStrings.localized("forecast.info.example.remaining"))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(AppStrings.localized("forecast.info.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct InfoGuideRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

struct ChecklistCompletionButton: View {
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChecklistCompletionMark(isCompleted: isCompleted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("editor.checklist.completed"))
    }
}

struct ChecklistCompletionMark: View {
    let isCompleted: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isCompleted ? Color.green : Color.secondary.opacity(0.45), lineWidth: 2)
                .background(Circle().fill(isCompleted ? Color.green : Color.clear))
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .animation(.snappy(duration: 0.18), value: isCompleted)
    }
}

enum AppColors {
    static let background = Color(platformColor: .systemGroupedBackground)
    #if os(macOS)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #else
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    #endif
    static let border = Color.primary.opacity(0.08)
    static let panelHeader = LinearGradient(
        colors: [Color.blue.opacity(0.10), Color.green.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(sanitized, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
extension PlatformColor {
    static var systemGroupedBackground: NSColor { NSColor.windowBackgroundColor }
}
#else
typealias PlatformColor = UIColor
#endif

#Preview {
    ContentView()
        .modelContainer(for: TimeTrackerModelRegistry.currentModels, inMemory: true)
}
