import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PersistenceRecoveryView: View {
    @State private var didCopyDiagnostics = false
    #if os(macOS)
    @State private var dataFolderError: String?
    #endif

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
                    Label(
                        AppStrings.localized(
                            didCopyDiagnostics
                                ? "persistence.diagnosticsCopied"
                                : "persistence.copyDiagnostics"
                        ),
                        systemImage: didCopyDiagnostics ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)

                #if os(macOS)
                Button(action: openDataFolder) {
                    Label(AppStrings.localized("persistence.openDataFolder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label(AppStrings.localized("persistence.quit"), systemImage: "power")
                }
                .buttonStyle(.borderedProminent)
                #endif
            }

            #if os(macOS)
            if let dataFolderError {
                Text(dataFolderError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            #endif
        }
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func copyDiagnostics() {
        let text = safety.diagnosticReport(
            persistenceMode: AppCloudSync.persistenceMode,
            storeURL: AppCloudSync.persistentStoreURL
        )
        #if os(macOS)
        NSPasteboard.general.clearContents()
        didCopyDiagnostics = NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        didCopyDiagnostics = true
        #endif
    }

    #if os(macOS)
    private func openDataFolder() {
        let directory = AppCloudSync.persistentStoreURL.deletingLastPathComponent()
        guard NSWorkspace.shared.open(directory) else {
            dataFolderError = AppStrings.localized("persistence.openDataFolderFailed")
            return
        }
        dataFolderError = nil
    }
    #endif
}
