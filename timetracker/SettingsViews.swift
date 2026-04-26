import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @AppStorage("PreferredColorScheme") private var preferredColorScheme = "system"
    @AppStorage("PomodoroDefaultMode") private var pomodoroDefaultMode = PomodoroPreset.classic.rawValue
    @AppStorage("DefaultFocusMinutes") private var defaultFocusMinutes = 25
    @AppStorage("DefaultBreakMinutes") private var defaultBreakMinutes = 5
    @AppStorage("DefaultPomodoroRounds") private var defaultPomodoroRounds = 1
    @AppStorage("AllowParallelTimers") private var allowParallelTimers = true
    @AppStorage("ShowGrossAndWallTogether") private var showGrossAndWallTogether = true
    @AppStorage("TimeTrackerCloudSyncEnabled") private var cloudSyncEnabled = true
    @State private var isResetConfirmationPresented = false
    @State private var isClearConfirmationPresented = false
    @State private var isOptimizeConfirmationPresented = false
    @State private var isExportPresented = false
    @State private var isCheckingSync = false
    @State private var syncCheckMessage: String?
    @State private var databaseOptimizationMessage: String?

    private var minuteFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 480
        return formatter
    }

    var body: some View {
        Form {
            Section {
                Picker(AppStrings.localized("settings.appearance"), selection: $preferredColorScheme) {
                    Text(.app("settings.appearance.system")).tag("system")
                    Text(.app("settings.appearance.light")).tag("light")
                    Text(.app("settings.appearance.dark")).tag("dark")
                }
                .pickerStyle(.segmented)

                Toggle(AppStrings.localized("settings.allowParallelTimers"), isOn: $allowParallelTimers)
                Toggle(AppStrings.localized("settings.showWallGross"), isOn: $showGrossAndWallTogether)
            } header: {
                SettingsHeader(symbol: "paintbrush.pointed.fill", title: AppStrings.localized("settings.displayTiming"))
            } footer: {
                Text(.app("settings.displayTiming.footer"))
            }

            Section {
                Picker(AppStrings.localized("settings.defaultMode"), selection: $pomodoroDefaultMode) {
                    ForEach(PomodoroPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .onChange(of: pomodoroDefaultMode) { _, newValue in
                    guard let preset = PomodoroPreset(rawValue: newValue), preset != .custom else { return }
                    defaultFocusMinutes = preset.focusMinutes
                    defaultBreakMinutes = preset.breakMinutes
                }

                TextField(AppStrings.localized("settings.focusMinutes"), value: $defaultFocusMinutes, formatter: minuteFormatter)
                TextField(AppStrings.localized("settings.breakMinutes"), value: $defaultBreakMinutes, formatter: minuteFormatter)
                TextField(AppStrings.localized("settings.defaultRounds"), value: $defaultPomodoroRounds, formatter: minuteFormatter)
            } header: {
                SettingsHeader(symbol: "timer", title: AppStrings.pomodoro)
            } footer: {
                Text(.app("settings.pomodoro.footer"))
            }

            Section {
                if store.countdownEvents.isEmpty {
                    Text(.app("settings.countdown.empty"))
                        .foregroundStyle(.secondary)
                }

                ForEach(store.countdownEvents) { event in
                    CountdownEventSettingsRow(
                        event: event,
                        onChangeTitle: { title in
                            store.updateCountdownEvent(event, title: title)
                        },
                        onChangeDate: { date in
                            store.updateCountdownEvent(event, date: date)
                        },
                        onDelete: {
                            store.deleteCountdownEvent(event)
                        }
                    )
                }

                Button {
                    store.addCountdownEvent()
                } label: {
                    Label(AppStrings.localized("settings.countdown.add"), systemImage: "plus")
                }
            } header: {
                SettingsHeader(symbol: "calendar.badge.clock", title: AppStrings.localized("settings.countdown"))
            } footer: {
                Text(.app("settings.countdown.footer"))
            }

            Section {
                Button {
                    isExportPresented = true
                } label: {
                    Label(AppStrings.localized("settings.exportCSV"), systemImage: "square.and.arrow.down")
                }

                Button {
                    store.presentManualTime()
                } label: {
                    Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
                }

                Button(role: .destructive) {
                    isOptimizeConfirmationPresented = true
                } label: {
                    Label(AppStrings.localized("settings.optimizeDatabase"), systemImage: "externaldrive.badge.checkmark")
                }
            } header: {
                SettingsHeader(symbol: "doc.text.fill", title: AppStrings.localized("settings.data"))
            } footer: {
                Text(.app("settings.data.footer"))
            }

            Section {
                Toggle(isOn: $cloudSyncEnabled) {
                    Label(AppStrings.localized("settings.icloud"), systemImage: "icloud")
                }
                .onChange(of: cloudSyncEnabled) { _, enabled in
                    if !enabled {
                        AppCloudSync.recordCloudKitDisabledByUser()
                    }
                }

                LabeledContent(
                    AppStrings.localized("settings.currentStorage"),
                    value: cloudSyncEnabled ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud")) : AppStrings.localized("settings.local")
                )

                Button {
                    isCheckingSync = true
                    Task {
                        await store.refreshCloudAccountStatus()
                        syncCheckMessage = store.syncStatus.accountStatus
                        isCheckingSync = false
                    }
                } label: {
                    Label(isCheckingSync ? AppStrings.localized("settings.checking") : AppStrings.localized("settings.checkSync"), systemImage: "arrow.clockwise")
                }
                .disabled(isCheckingSync)

                Button {
                    isCheckingSync = true
                    Task {
                        syncCheckMessage = await store.forceCloudSyncRefresh()
                        isCheckingSync = false
                    }
                } label: {
                    Label(AppStrings.localized("settings.forceSync"), systemImage: "arrow.clockwise.icloud")
                }
                .disabled(isCheckingSync)
            } header: {
                SettingsHeader(symbol: "icloud.fill", title: AppStrings.localized("settings.sync"))
            } footer: {
                Text(.app("settings.sync.footer"))
            }

            Section {
                LabeledContent(AppStrings.tasks, value: "\(store.tasks.count)")
                LabeledContent(AppStrings.localized("settings.timeRecords"), value: "\(store.allSegments.count)")
                LabeledContent(AppStrings.pomodoro, value: "\(store.pomodoroRuns.count)")
                LabeledContent(AppStrings.localized("settings.cloudAccount"), value: store.syncStatus.accountStatus)
                LabeledContent(AppStrings.localized("settings.icloudContainer"), value: store.syncStatus.containerIdentifier)
                Button(AppStrings.localized("settings.rebuildDemoData"), role: .destructive) {
                    isResetConfirmationPresented = true
                }
                Button(AppStrings.localized("settings.clearDemoData"), role: .destructive) {
                    isClearConfirmationPresented = true
                }
            } header: {
                SettingsHeader(symbol: "wrench.and.screwdriver.fill", title: AppStrings.localized("settings.maintenance"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppStrings.settings)
        .accessibilityIdentifier("settings.view")
        .fileExporter(
            isPresented: $isExportPresented,
            document: CSVExportDocument(text: store.csvExport()),
            contentType: .commaSeparatedText,
            defaultFilename: "time-tracker-export.csv"
        ) { result in
            if case let .failure(error) = result {
                store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(AppStrings.localized("dialog.rebuildDemo.title"), isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.rebuildDemo.confirm"), role: .destructive) {
                store.replaceWithDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.rebuildDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.clearDemo.title"), isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.clearDemo.confirm"), role: .destructive) {
                store.clearDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.clearDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.optimize.title"), isPresented: $isOptimizeConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.optimize.confirm"), role: .destructive) {
                let removedCount = store.optimizeDatabase()
                databaseOptimizationMessage = removedCount == 0 ? AppStrings.localized("dialog.optimize.none") : String(format: AppStrings.localized("dialog.optimize.removed"), removedCount)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.optimize.message"))
        }
        .alert(AppStrings.localized("alert.sync.title"), isPresented: syncCheckPresented) {
            Button(AppStrings.localized("common.ok")) {
                syncCheckMessage = nil
            }
        } message: {
            Text(syncCheckMessage ?? "")
        }
        .alert(AppStrings.localized("alert.optimize.title"), isPresented: optimizationMessagePresented) {
            Button(AppStrings.localized("common.ok")) {
                databaseOptimizationMessage = nil
            }
        } message: {
            Text(databaseOptimizationMessage ?? "")
        }
    }

    private var syncCheckPresented: Binding<Bool> {
        Binding {
            syncCheckMessage != nil
        } set: { isPresented in
            if !isPresented {
                syncCheckMessage = nil
            }
        }
    }

    private var optimizationMessagePresented: Binding<Bool> {
        Binding {
            databaseOptimizationMessage != nil
        } set: { isPresented in
            if !isPresented {
                databaseOptimizationMessage = nil
            }
        }
    }
}

struct SettingsHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
    }
}

struct CountdownEventSettingsRow: View {
    let event: CountdownEvent
    let onChangeTitle: (String) -> Void
    let onChangeDate: (Date) -> Void
    let onDelete: () -> Void

    private var titleBinding: Binding<String> {
        Binding {
            event.title
        } set: { value in
            onChangeTitle(value)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding {
            event.date
        } set: { value in
            onChangeDate(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppStrings.localized("settings.countdown.eventName"), text: titleBinding)
            HStack {
                DatePicker(AppStrings.localized("settings.countdown.date"), selection: dateBinding, displayedComponents: .date)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.gradient)
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    content
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
            }
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    var monospaced = false
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .foregroundStyle(isWarning ? .orange : .secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 164)
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let status: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .frame(width: 150, alignment: .leading)
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: Capsule())
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 164)
        }
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 18) {
            Text(title)
                .font(.subheadline)
                .frame(width: 220, alignment: .leading)
            Spacer()
            control
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 234)
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 50)
        }
    }
}
