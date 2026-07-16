import SwiftUI

struct SegmentEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSceneFeedbackRouter.self) private var feedbackRouter
    @State private var recoveryError: SegmentEditorRecoveryError?
    @State private var currentDraft: SegmentEditorDraft

    init(store: TimeTrackerStore, initialDraft: SegmentEditorDraft) {
        self.store = store
        _currentDraft = State(initialValue: initialDraft)
    }

    var body: some View {
        SegmentEditorPanel(
            store: store,
            initialDraft: currentDraft,
            onCancel: dismiss.callAsFunction,
            onSave: save,
            onDelete: delete
        )
        .id(currentDraft.id)
        .platformSheetFrame(width: 620, height: 620)
        .presentationDetents([.large])
        .alert(
            recoveryError?.title ?? "",
            isPresented: recoveryPresentation,
            presenting: recoveryError
        ) { recovery in
            if recovery == .stale {
                Button(
                    AppStrings.localized("segment.editor.reload"),
                    role: .destructive
                ) {
                    reloadLatestDraft()
                }
            }
            Button(
                AppStrings.localized("segment.editor.discardAndClose"),
                role: .destructive
            ) {
                dismiss()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: { recovery in
            Text(recovery.message)
        }
    }

    private var recoveryPresentation: Binding<Bool> {
        Binding {
            recoveryError != nil
        } set: { isPresented in
            if isPresented == false {
                recoveryError = nil
            }
        }
    }

    private func save(_ draft: SegmentEditorDraft) {
        do {
            try store.commitSegmentDraft(draft)
            dismiss()
        } catch {
            handleMutationFailure(error, titleKey: "segment.save.error.title")
        }
    }

    private func delete(_ draft: SegmentEditorDraft) {
        do {
            try store.commitSegmentDeletion(
                draft.segmentID,
                expectedBaseline: draft.baseline
            )
            dismiss()
        } catch {
            handleMutationFailure(error, titleKey: "segment.delete.error.title")
        }
    }

    private func handleMutationFailure(_ error: Error, titleKey: String) {
        if let recovery = SegmentEditorRecoveryError(error) {
            try? store.refreshSegmentEditorReadModels()
            recoveryError = recovery
            return
        }
        feedbackRouter.present(
            title: AppStrings.localized(titleKey),
            message: error.localizedDescription
        )
    }

    private func reloadLatestDraft() {
        do {
            try store.refreshSegmentEditorReadModels()
            guard let segment = store.allSegments.first(where: {
                $0.id == currentDraft.segmentID && $0.deletedAt == nil
            }), let latestDraft = store.segmentEditorDraft(for: segment) else {
                feedbackRouter.present(
                    title: AppStrings.localized("segment.editor.deleted.title"),
                    message: AppStrings.localized("segment.editor.deleted.message")
                )
                dismiss()
                return
            }
            currentDraft = latestDraft
            recoveryError = nil
        } catch {
            feedbackRouter.present(
                title: AppStrings.localized("segment.editor.reload.error.title"),
                message: error.localizedDescription
            )
        }
    }
}
