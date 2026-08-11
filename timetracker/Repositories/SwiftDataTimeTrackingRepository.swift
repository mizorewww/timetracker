import Foundation
import SwiftData

@MainActor
final class SwiftDataTimeTrackingRepository {
    let context: ModelContext
    let deviceID: String
    let nowProvider: () -> Date

    init(
        context: ModelContext,
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
        self.nowProvider = nowProvider
    }
}
