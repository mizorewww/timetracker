import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DesktopModalLayer: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ZStack {
            if let draft = store.taskEditorDraft {
                modalBackdrop
                TaskEditorPanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.taskEditorDraft = nil },
                    onSave: { store.saveTaskDraft($0) }
                )
                .frame(width: 500, height: 560)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            } else if let draft = store.manualTimeDraft {
                modalBackdrop
                ManualTimePanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.manualTimeDraft = nil },
                    onSave: { store.saveManualTimeDraft($0) }
                )
                .frame(width: 620, height: 520)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            } else if let draft = store.segmentEditorDraft {
                modalBackdrop
                SegmentEditorPanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.segmentEditorDraft = nil },
                    onSave: { store.saveSegmentDraft($0) },
                    onDelete: { store.deleteSegment($0) }
                )
                .frame(width: 620, height: 560)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.taskEditorDraft?.id)
        .animation(.easeOut(duration: 0.16), value: store.manualTimeDraft?.id)
        .animation(.easeOut(duration: 0.16), value: store.segmentEditorDraft?.id)
    }

    private var modalBackdrop: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .onTapGesture {
                store.taskEditorDraft = nil
                store.manualTimeDraft = nil
                store.segmentEditorDraft = nil
            }
    }
}

struct TaskEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.taskEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveTaskDraft(draft)
                dismiss()
            }
        )
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @State private var isSymbolPickerPresented = false
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void

    private let colors = ["1677FF", "16A34A", "7C3AED", "F97316", "EF4444", "0EA5E9", "64748B"]

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section(AppStrings.localized("editor.task.info")) {
                        TextField(AppStrings.localized("editor.task.name"), text: $draft.title)

                        Picker(AppStrings.localized("editor.task.status"), selection: $draft.status) {
                            ForEach(TaskStatus.allCases, id: \.self) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker(AppStrings.localized("editor.task.parent"), selection: parentBinding) {
                            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
                            ForEach(store.tasks.filter { $0.id != draft.taskID }, id: \.id) { task in
                                Text(indentedTitle(task)).tag(Optional(task.id))
                            }
                        }

                        DisclosureGroup(AppStrings.localized("editor.task.advanced")) {
                            Picker(AppStrings.localized("editor.task.kind"), selection: $draft.kind) {
                                Text(.app("editor.task.kind.task")).tag(TaskNodeKind.task)
                                Text(.app("editor.task.kind.project")).tag(TaskNodeKind.project)
                                Text(.app("editor.task.kind.folder")).tag(TaskNodeKind.folder)
                            }
                            Text(.app("editor.task.kind.footer"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(.app("editor.task.symbolColor"))
                            Spacer()
                            Button {
                                isSymbolPickerPresented = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.iconName)
                                        .foregroundStyle(Color(hex: draft.colorHex) ?? .blue)
                                    Text(.app("common.choose"))
                                }
                            }
                            #if os(macOS)
                            .popover(isPresented: $isSymbolPickerPresented) {
                                SymbolAndColorPicker(
                                    symbols: SymbolCatalog.symbolNames,
                                    searchKeywords: SymbolCatalog.searchKeywords,
                                    colors: colors,
                                    symbolName: $draft.iconName,
                                    colorHex: $draft.colorHex
                                )
                                .frame(width: 460, height: 520)
                            }
                            #endif
                        }
                    }

                    Section(AppStrings.localized("editor.task.plan")) {
                        Stepper(value: estimatedMinutesBinding, in: 0...600, step: 15) {
                            LabeledContent(AppStrings.localized("editor.task.estimate"), value: draft.estimatedMinutes.map { String(format: AppStrings.localized("common.minutes"), $0) } ?? AppStrings.localized("editor.task.notSet"))
                        }

                        Toggle(AppStrings.localized("editor.task.setDue"), isOn: $draft.hasDueDate)
                        if draft.hasDueDate {
                            DatePicker(AppStrings.localized("editor.task.due"), selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section(AppStrings.localized("editor.task.notes")) {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 88)
                    }
                }
                .formStyle(.grouped)

                #if os(macOS)
                Divider()
                HStack {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
                .padding(16)
                .background(.thinMaterial)
                #endif
            }
            .navigationTitle(draft.taskID == nil ? AppStrings.localized("editor.task.newTitle") : AppStrings.localized("editor.task.editTitle"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
                #endif
            }
            #if os(iOS)
            .sheet(isPresented: $isSymbolPickerPresented) {
                NavigationStack {
                    SymbolAndColorPicker(
                        symbols: SymbolCatalog.symbolNames,
                        searchKeywords: SymbolCatalog.searchKeywords,
                        colors: colors,
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                    .navigationTitle(AppStrings.localized("editor.symbol.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppStrings.done) {
                                isSymbolPickerPresented = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            #endif
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var parentTitle: String {
        guard let parentID = draft.parentID, let task = store.task(for: parentID) else {
            return AppStrings.localized("editor.task.rootTitle")
        }
        return store.path(for: task)
    }

    private var parentBinding: Binding<UUID?> {
        Binding {
            draft.parentID
        } set: { value in
            draft.parentID = value
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            draft.estimatedMinutes ?? 0
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }

}

struct ManualTimeSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: ManualTimeDraft

    var body: some View {
        ManualTimePanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.manualTimeDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveManualTimeDraft(draft)
                dismiss()
            }
        )
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: SegmentEditorDraft

    var body: some View {
        SegmentEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.segmentEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveSegmentDraft(draft)
                dismiss()
            },
            onDelete: { segmentID in
                store.deleteSegment(segmentID)
                dismiss()
            }
        )
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: SegmentEditorDraft
    let onCancel: () -> Void
    let onSave: (SegmentEditorDraft) -> Void
    let onDelete: (UUID) -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: SegmentEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SegmentEditorDraft) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(.app("segment.edit.title"))
                        .font(.title2.bold())
                    Text(.app("segment.edit.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }
            .padding(18)

            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: taskBinding) {
                        Text(.app("segment.choose")).tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }

                    LabeledContent(AppStrings.localized("segment.source"), value: draft.source.rawValue)
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle(AppStrings.localized("segment.active"), isOn: $draft.isActive)
                    if !draft.isActive {
                        DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent(AppStrings.localized("segment.duration")) {
                            Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                        }
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("segment.note.placeholder"), text: $draft.note)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete(draft.segmentID)
                    } label: {
                        Label(AppStrings.localized("segment.softDelete"), systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(AppStrings.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(AppStrings.localized("common.save")) {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.taskID == nil || (!draft.isActive && draft.endedAt <= draft.startedAt))
            }
            .padding(18)
            .background(.thinMaterial)
        }
        .background(AppColors.background)
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}

struct SymbolAndColorPicker: View {
    let symbols: [String]
    let searchKeywords: [String: [String]]
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var searchText = ""

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return symbols }
        return symbols.filter { symbol in
            symbol.localizedCaseInsensitiveContains(searchText) ||
            (searchKeywords[symbol]?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.app("editor.symbol.sfSymbols"))
                    .font(.headline)
                Spacer()
                Text("\(filteredSymbols.count) / \(symbols.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField(AppStrings.localized("editor.symbol.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(symbolName == symbol ? .white : (Color(hex: colorHex) ?? .blue))
                                .frame(width: 38, height: 38)
                                .background(symbolName == symbol ? (Color(hex: colorHex) ?? .blue) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            Text(.app("editor.symbol.color"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum SymbolCatalog {
    static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
                  !names.isEmpty else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    private static func resourceURLs(fileName: String, extension ext: String) -> [URL] {
        let bundled: [URL] = [
            fileName == "symbol_order" ? Bundle.main.url(forResource: "SFSymbolOrder", withExtension: ext) : nil,
            fileName == "symbol_search" ? Bundle.main.url(forResource: "SFSymbolSearch", withExtension: ext) : nil
        ].compactMap(\.self)

        let system = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources"
        ].map {
            URL(fileURLWithPath: $0).appendingPathComponent(fileName).appendingPathExtension(ext)
        }

        return bundled + system
    }

    private static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "pause.fill", "stop.fill", "plus", "magnifyingglass"
    ]
}

struct ManualTimePanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: ManualTimeDraft
    let onCancel: () -> Void
    let onSave: (ManualTimeDraft) -> Void

    init(store: TimeTrackerStore, initialDraft: ManualTimeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ManualTimeDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(.app("manual.title"))
                        .font(.title2.bold())
                    Text(.app("manual.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }
            .padding(18)

            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: taskBinding) {
                        Text(.app("segment.choose")).tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                    LabeledContent(AppStrings.localized("segment.duration")) {
                        Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("manual.note.placeholder"), text: $draft.note)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(AppStrings.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(AppStrings.localized("common.save")) {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.taskID == nil || draft.endedAt <= draft.startedAt)
            }
            .padding(18)
            .background(.thinMaterial)
        }
        .background(AppColors.background)
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}

struct FormSectionBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .appCard(padding: 14)
    }
}
