import Foundation

// MARK: - AOAPushNotifications

/// ObjC-compatible facade for AppsOnAirPush.Notifications.
@objc(AOAPushNotifications)
public final class AOAPushNotifications: NSObject {

    private override init() {}

    // MARK: - Permission requests

    /// Request OS notification permission (no fallback to Settings).
    @objc @MainActor
    public static func requestPermission() {
        AppsOnAirPush.Notifications.requestPermission(fallbackToSettings: false)
    }

    /// Request OS notification permission, optionally opening Settings if already denied.
    @objc @MainActor
    public static func requestPermission(fallbackToSettings: Bool) {
        AppsOnAirPush.Notifications.requestPermission(fallbackToSettings: fallbackToSettings)
    }

    /// Request provisional (quiet) authorization — iOS 12+.
    @objc @MainActor
    public static func registerForProvisionalAuthorization() {
        AppsOnAirPush.Notifications.registerForProvisionalAuthorization()
    }

    // MARK: - Permission state (synchronous, cached)

    /// Whether notifications are currently permitted.
    @objc @MainActor
    public static var permission: Bool {
        AppsOnAirPush.Notifications.permission
    }

    /// The native OS authorization status (cached).
    @objc @MainActor
    public static var permissionNative: AOANotificationPermission {
        AppsOnAirPush.Notifications.permissionNative.aoaValue
    }

    /// Whether `requestPermission()` would show the system dialog.
    @objc @MainActor
    public static var canRequestPermission: Bool {
        AppsOnAirPush.Notifications.canRequestPermission
    }

    /// Force-refresh the cached permission state and return the current value.
    @objc
    public static func refreshPermission(completion: @escaping @Sendable (Bool) -> Void) {
        Task { @MainActor in
            completion(await AppsOnAirPush.Notifications.refreshPermission())
        }
    }

    // MARK: - Permission Observer

    /// Add an observer for permission changes.
    @objc @MainActor
    public static func addPermissionObserver(_ observer: any AOANotificationPermissionObserver) {
        let storage = AOABridgeStorage.shared
        if storage.permissionAdapters.object(forKey: observer) == nil {
            let bridge = AOAPermissionObserverBridge(observer)
            storage.permissionAdapters.setObject(bridge, forKey: observer)
            AppsOnAirPush.Notifications.addPermissionObserver(bridge)
        }
    }

    /// Remove a previously added permission observer.
    @objc @MainActor
    public static func removePermissionObserver(_ observer: any AOANotificationPermissionObserver) {
        let storage = AOABridgeStorage.shared
        if let bridge = storage.permissionAdapters.object(forKey: observer) {
            AppsOnAirPush.Notifications.removePermissionObserver(bridge)
            storage.permissionAdapters.removeObject(forKey: observer)
        }
    }

    // MARK: - Foreground Lifecycle Listener

    /// Add a foreground lifecycle listener.
    @objc @MainActor
    public static func addForegroundLifecycleListener(_ listener: any AOANotificationLifecycleListener) {
        let storage = AOABridgeStorage.shared
        if storage.lifecycleAdapters.object(forKey: listener) == nil {
            let bridge = AOALifecycleListenerBridge(listener)
            storage.lifecycleAdapters.setObject(bridge, forKey: listener)
            AppsOnAirPush.Notifications.addForegroundLifecycleListener(bridge)
        }
    }

    /// Remove a previously added foreground lifecycle listener.
    @objc @MainActor
    public static func removeForegroundLifecycleListener(_ listener: any AOANotificationLifecycleListener) {
        let storage = AOABridgeStorage.shared
        if let bridge = storage.lifecycleAdapters.object(forKey: listener) {
            AppsOnAirPush.Notifications.removeForegroundLifecycleListener(bridge)
            storage.lifecycleAdapters.removeObject(forKey: listener)
        }
    }

    // MARK: - Click Listener

    /// Add a notification click listener.
    @objc @MainActor
    public static func addClickListener(_ listener: any AOANotificationClickListener) {
        let storage = AOABridgeStorage.shared
        if storage.clickAdapters.object(forKey: listener) == nil {
            let bridge = AOAClickListenerBridge(listener)
            storage.clickAdapters.setObject(bridge, forKey: listener)
            AppsOnAirPush.Notifications.addClickListener(bridge)
        }
    }

    /// Remove a previously added click listener.
    @objc @MainActor
    public static func removeClickListener(_ listener: any AOANotificationClickListener) {
        let storage = AOABridgeStorage.shared
        if let bridge = storage.clickAdapters.object(forKey: listener) {
            AppsOnAirPush.Notifications.removeClickListener(bridge)
            storage.clickAdapters.removeObject(forKey: listener)
        }
    }

    // MARK: - Notification management

    /// Remove all delivered notifications from Notification Center.
    @objc @MainActor
    public static func clearAllNotifications() {
        AppsOnAirPush.Notifications.clearAllNotifications()
    }

    /// Remove a specific delivered notification by its identifier.
    @objc @MainActor
    public static func removeNotification(withIdentifier identifier: String) {
        AppsOnAirPush.Notifications.removeNotification(withIdentifier: identifier)
    }

    /// Remove multiple delivered notifications by their identifiers.
    @objc @MainActor
    public static func removeNotifications(withIdentifiers identifiers: [String]) {
        AppsOnAirPush.Notifications.removeNotifications(withIdentifiers: identifiers)
    }
}
