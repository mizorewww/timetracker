import SwiftUI

#if os(macOS)
private struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ManualTimeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartTimerActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartPomodoroActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newTaskAction: (() -> Void)? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }

    var manualTimeAction: (() -> Void)? {
        get { self[ManualTimeActionKey.self] }
        set { self[ManualTimeActionKey.self] = newValue }
    }

    var startTimerAction: (() -> Void)? {
        get { self[StartTimerActionKey.self] }
        set { self[StartTimerActionKey.self] = newValue }
    }

    var startPomodoroAction: (() -> Void)? {
        get { self[StartPomodoroActionKey.self] }
        set { self[StartPomodoroActionKey.self] = newValue }
    }

    var refreshAction: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}
#endif
