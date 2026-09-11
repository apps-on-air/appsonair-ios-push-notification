import Foundation

// MARK: - AOAPushBackgroundSync

/// ObjC-compatible facade for AppsOnAirBackgroundSync.
@objc(AOAPushBackgroundSync)
public final class AOAPushBackgroundSync: NSObject {

    private override init() {}

    /// The BGTask identifier registered in BGTaskSchedulerPermittedIdentifiers.
    @objc
    public static var taskIdentifier: String {
        AppsOnAirBackgroundSync.taskIdentifier
    }

    /// Register BGTask handlers. Must be called before the app finishes launching.
    @objc
    public static func registerHandlers() {
        AppsOnAirBackgroundSync.registerHandlers()
    }

    /// Submit a BGAppRefreshTaskRequest with a custom minimum delay (in seconds).
    @objc
    public static func scheduleIfNeeded(minimumDelay: TimeInterval) {
        AppsOnAirBackgroundSync.scheduleIfNeeded(minimumDelay: minimumDelay)
    }

    /// Submit a BGAppRefreshTaskRequest with the default 15-minute minimum delay.
    @objc
    public static func scheduleIfNeeded() {
        AppsOnAirBackgroundSync.scheduleIfNeeded()
    }

    /// Cancel any pending background sync request.
    @objc
    public static func cancelPending() {
        AppsOnAirBackgroundSync.cancelPending()
    }
}
