import SwiftUI

struct WatchCommandFailureRow: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let title: String
    let result: WatchCommandResult
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.status.failureSystemImage)
                    .font(.headline)
                    .foregroundStyle(result.status.failureTint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(3)
                        .privacySensitive()
                        .redacted(reason: isLuminanceReduced ? .placeholder : [])
                    Text(result.status.failureMessageKey)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    retryButton
                    discardButton
                }
                VStack(spacing: 6) {
                    retryButton
                    discardButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Label("watch.command.retry", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }

    private var discardButton: some View {
        Button(action: onDiscard) {
            Text("watch.command.discard")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

private extension WatchCommandResultStatus {
    var failureMessageKey: LocalizedStringKey {
        switch self {
        case .missingTask: "watch.commandFailure.missingTask"
        case .missingSegment: "watch.commandFailure.missingSegment"
        case .invalid: "watch.commandFailure.invalid"
        case .failed: "watch.commandFailure.failed"
        case .timeout: "watch.commandFailure.timeout"
        case .success, .duplicate: "watch.commandFailure.resolved"
        }
    }

    var failureSystemImage: String {
        switch self {
        case .timeout: "clock.badge.exclamationmark"
        case .missingTask, .missingSegment: "questionmark.circle.fill"
        case .invalid, .failed: "exclamationmark.triangle.fill"
        case .success, .duplicate: "checkmark.circle.fill"
        }
    }

    var failureTint: Color {
        switch self {
        case .timeout, .missingTask, .missingSegment: .orange
        case .invalid, .failed: .red
        case .success, .duplicate: .green
        }
    }
}

enum WatchSyncStatus: Equatable {
    case waitingForFirstSnapshot
    case sending
    case queued
    case stale
    case connectionError

    var titleKey: LocalizedStringKey {
        switch self {
        case .waitingForFirstSnapshot: "watch.status.waiting"
        case .sending: "watch.status.sending"
        case .queued: "watch.status.queued"
        case .stale: "watch.status.stale"
        case .connectionError: "watch.status.error"
        }
    }

    var messageKey: LocalizedStringKey {
        switch self {
        case .waitingForFirstSnapshot: "watch.status.waiting.message"
        case .sending: "watch.status.sending.message"
        case .queued: "watch.status.queued.message"
        case .stale: "watch.status.stale.message"
        case .connectionError: "watch.status.error.message"
        }
    }

    var systemImage: String {
        switch self {
        case .waitingForFirstSnapshot: "iphone.and.arrow.forward"
        case .sending: "arrow.up.circle"
        case .queued: "tray.and.arrow.up"
        case .stale: "exclamationmark.clock"
        case .connectionError: "wifi.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .waitingForFirstSnapshot, .sending: .blue
        case .queued, .stale: .yellow
        case .connectionError: .red
        }
    }

    var showsLastUpdated: Bool {
        self == .stale || self == .connectionError
    }
}

struct WatchStatusRow: View {
    let status: WatchSyncStatus
    let snapshotDate: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.systemImage)
                .font(.headline)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(status.titleKey)
                    .font(.caption.weight(.semibold))
                Text(status.messageKey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if status.showsLastUpdated {
                    HStack(spacing: 3) {
                        Text("watch.status.lastUpdated")
                        Text(snapshotDate, style: .relative)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct WatchIconTile: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 40)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct WatchEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .accessibilityElement(children: .combine)
    }
}
