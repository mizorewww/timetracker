import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AppBuildInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? AppStrings.appName
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionSummary: String {
        "\(version) (\(buildNumber))"
    }

    static var gitBranch: String {
        buildInfo["GitBranch"] ?? "unknown"
    }

    static var gitCommit: String {
        buildInfo["GitCommitShort"] ?? "unknown"
    }

    static var buildDate: String {
        buildInfo["BuildDate"] ?? "unknown"
    }

    static var isDirtyBuild: Bool {
        buildInfo["GitDirty"] == "true"
    }

    private static let buildInfo: [String: String] = {
        guard let url = Bundle.main.url(forResource: "AppBuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = object as? [String: String] else {
            return [:]
        }
        return dictionary
    }()
}

struct AppIconImage: View {
    var body: some View {
        Group {
            #if os(macOS)
            if let image = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: image)
                    .resizable()
            } else {
                fallback
            }
            #else
            if let image = UIImage.appIcon {
                Image(uiImage: image)
                    .resizable()
            } else {
                fallback
            }
            #endif
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.blue.gradient)
            .overlay {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

#if os(iOS)
private extension UIImage {
    static var appIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconName = iconFiles.last else {
            return nil
        }

        return UIImage(named: iconName)
    }
}
#endif
