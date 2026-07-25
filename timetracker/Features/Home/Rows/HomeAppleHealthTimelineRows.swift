#if os(iOS)
import SwiftUI

extension TimeTrackerStore {
    var shouldShowAppleHealthTimelineStatusInline: Bool {
        switch appleHealthTimelineState {
        case let .content(_, _, itemCount):
            itemCount == 0
        case .disabled, .unavailable, .ready, .requesting, .loading,
             .noReadableData, .failed:
            true
        }
    }
}

struct AppleHealthTimelineAccessRow: View {
    let store: TimeTrackerStore

    var body: some View {
        Group {
            switch store.appleHealthTimelineState {
            case .disabled:
                Button {
                    Task {
                        await store.showAppleHealthInTimeline()
                    }
                } label: {
                    Label(
                        AppStrings.localized("health.timeline.showAction"),
                        systemImage: "figure.run"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)

            case .unavailable:
                status(
                    title: AppStrings.localized("health.timeline.unavailable.title"),
                    message: AppStrings.localized("health.timeline.unavailable.message"),
                    systemImage: "heart.slash",
                    tint: .secondary
                )

            case .requesting:
                progressStatus(
                    AppStrings.localized("health.timeline.requesting")
                )

            case .loading:
                progressStatus(
                    AppStrings.localized("health.timeline.loading")
                )

            case .ready:
                actionStatus(
                    title: AppStrings.localized("health.timeline.ready.title"),
                    message: AppStrings.localized("health.timeline.ready.message"),
                    actionTitle: AppStrings.localized(
                        "health.timeline.reviewAccess"
                    ),
                    action: {
                        Task {
                            await store.refreshAppleHealthTimeline()
                        }
                    }
                )

            case .noReadableData:
                actionStatus(
                    title: AppStrings.localized("health.timeline.empty.title"),
                    message: AppStrings.localized("health.timeline.empty.message"),
                    actionTitle: AppStrings.localized("health.timeline.reviewAccess"),
                    action: requestAccessAndRefresh
                )

            case let .failed(message):
                actionStatus(
                    title: AppStrings.localized("health.timeline.failed.title"),
                    message: message,
                    actionTitle: AppStrings.localized("action.retry"),
                    action: requestAccessAndRefresh
                )

            case .content:
                EmptyView()
            }
        }
        .accessibilityIdentifier("home.timeline.appleHealth")
    }

    private func progressStatus(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func actionStatus(
        title: String,
        message: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            status(
                title: title,
                message: message,
                systemImage: "heart.text.clipboard",
                tint: .pink
            )
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        }
    }

    private func requestAccessAndRefresh() {
        Task {
            await store.showAppleHealthInTimeline()
        }
    }

    private func status(
        title: String,
        message: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
