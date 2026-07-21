extension TaskEditorSession {
    func setQuantityGoal(
        _ quantityGoal: TaskQuantityGoalDraft?
    ) {
        draft.confirmsQuantityProgressReset = false
        draft.quantityGoal = quantityGoal
    }

    func confirmQuantityGoalRemoval() {
        guard draft.quantityGoal != nil else { return }
        draft.quantityGoal = nil
        draft.confirmsQuantityProgressReset = true
    }
}
