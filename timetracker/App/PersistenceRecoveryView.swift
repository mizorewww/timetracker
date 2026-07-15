import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PersistenceRecoveryView: View {
    let safety: PersistenceWriteSafety

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: safety.symbolName)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(safety.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(safety.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Text(AppStrings.localized("persistence.readOnly.footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: copyDiagnostics) {
                    Label(AppStrings.localized("persistence.copyDiagnostics"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                #if os(macOS)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(AppStrings.localized("persistence.quit"), systemImage: "power")
                }
                .buttonStyle(.borderedProminent)
                #endif
            }
        }
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func copyDiagnostics() {
        let text = "\(safety.title)\n\(safety.message)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
