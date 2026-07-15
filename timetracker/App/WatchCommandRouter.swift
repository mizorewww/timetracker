import Foundation

/// Routes Watch commands to a live scene without retaining that scene's store.
///
/// WatchConnectivity owns one process-wide callback while SwiftUI can create
/// multiple scenes. This registry selects the most recently active scene and
/// removes the callback when no scene remains, allowing the bridge to durably
/// queue commands during startup and scene teardown.
@MainActor
final class WatchCommandRouter {
    static let shared = WatchCommandRouter()

    private final class StoreReference {
        weak var value: TimeTrackerStore?

        init(_ value: TimeTrackerStore) {
            self.value = value
        }
    }

    private struct Route {
        let store: StoreReference
        let registrationOrder: UInt64
        var activationOrder: UInt64
        var isActive: Bool
    }

    private var routes: [UUID: Route] = [:]
    private var nextOrder: UInt64 = 0

    #if os(iOS) && canImport(WatchConnectivity)
    private var isBridgeHandlerInstalled = false
    #endif

    private init() {}

    func register(store: TimeTrackerStore, isActive: Bool) -> UUID {
        removeReleasedStores()
        nextOrder &+= 1
        let registrationID = UUID()
        routes[registrationID] = Route(
            store: StoreReference(store),
            registrationOrder: nextOrder,
            activationOrder: isActive ? nextOrder : 0,
            isActive: isActive
        )
        reconcileBridgeHandler()
        return registrationID
    }

    func update(registrationID: UUID, isActive: Bool) {
        removeReleasedStores()
        guard var route = routes[registrationID] else { return }
        route.isActive = isActive
        if isActive {
            nextOrder &+= 1
            route.activationOrder = nextOrder
        }
        routes[registrationID] = route
    }

    func unregister(registrationID: UUID) {
        routes[registrationID] = nil
        removeReleasedStores()
        reconcileBridgeHandler()
    }

    private func route(_ command: WatchTimerCommand) -> WatchCommandResult {
        removeReleasedStores()
        let target = preferredRoute?.store.value
        guard let target else {
            reconcileBridgeHandler()
            return .failed(commandID: command.id, failureCode: "sceneUnavailable")
        }
        return target.handleWatchCommand(command)
    }

    private var preferredRoute: Route? {
        let liveRoutes = routes.values.filter { $0.store.value != nil }
        return liveRoutes
            .filter(\.isActive)
            .max { $0.activationOrder < $1.activationOrder }
            ?? liveRoutes.max { $0.registrationOrder < $1.registrationOrder }
    }

    private func removeReleasedStores() {
        routes = routes.filter { $0.value.store.value != nil }
    }

    private func reconcileBridgeHandler() {
        #if os(iOS) && canImport(WatchConnectivity)
        if routes.isEmpty {
            guard isBridgeHandlerInstalled else { return }
            WatchConnectivityBridge.shared.commandHandler = nil
            isBridgeHandlerInstalled = false
        } else {
            guard !isBridgeHandlerInstalled else { return }
            WatchConnectivityBridge.shared.commandHandler = { [weak self] command in
                self?.route(command)
                    ?? .failed(commandID: command.id, failureCode: "routerUnavailable")
            }
            isBridgeHandlerInstalled = true
        }
        #endif
    }
}
