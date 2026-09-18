import Foundation
import UserNotifications
import UIKit

// MARK: - AppPushService.Notifications namespace

extension AppPushService {

    /// Notification permission, foreground display control, click handling, and management.
    @MainActor
    public enum Notifications {

        // MARK: - Permission

        /// Request OS notification permission. On grant, registers with APNs.
        /// - Parameter fallbackToSettings: If true and permission is denied, opens app Settings.
        public static func requestPermission(fallbackToSettings: Bool = false) {
            if fallbackToSettings {
                Task {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .denied {
                        await MainActor.run {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        return
                    }
                    await MainActor.run { AppPushService.requestPermission() }
                }
            } else {
                AppPushService.requestPermission()
            }
        }

        /// Request provisional (quiet) authorization — iOS 12+.
        /// Notifications appear silently in Notification Center without prompting the user.
        /// Higher acceptance rate than full permission dialog. Upgrade later with requestPermission().
        public static func registerForProvisionalAuthorization() {
            // requestAuthorization completion is called on an arbitrary background thread.
            // Hop back to @MainActor before touching any SDK state or UIKit.
            UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .badge]) { granted, error in
                Task { @MainActor in
                    if let error {
                        AppPushService.log("Provisional auth failed: \(error.localizedDescription)", level: .error)
                        return
                    }
                    AppPushService.log("Provisional authorization \(granted ? "granted" : "denied").", level: .info)
                    if granted {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }

        /// Whether notifications are currently permitted (`.authorized`, `.provisional`,
        /// or `.ephemeral`). Synchronous — served from a cache that is refreshed on
        /// launch, on every app foreground, and after each permission request.
        /// For reactive updates use `addPermissionObserver(_:)`.
        public static var permission: Bool {
            NotificationPermission(AppPushService.shared.cachedAuthorizationStatus).isGranted
        }

        /// The native OS authorization status (synchronous, cached).
        public static var permissionNative: NotificationPermission {
            NotificationPermission(AppPushService.shared.cachedAuthorizationStatus)
        }

        /// Whether `requestPermission()` would show the system dialog (status is
        /// `.notDetermined`). Synchronous, cached.
        public static var canRequestPermission: Bool {
            AppPushService.shared.cachedAuthorizationStatus == .notDetermined
        }

        /// Force-refresh the cached permission state from the OS and return the
        /// current granted value. The cache also refreshes automatically on launch
        /// and on every app foreground, so this is rarely needed.
        @discardableResult
        public static func refreshPermission() async -> Bool {
            await withCheckedContinuation { continuation in
                AppPushService.refreshPermissionCache { continuation.resume(returning: permission) }
            }
        }

        // MARK: - Permission Observer

        /// Add an observer that fires whenever notification permission changes
        /// (user grants, denies, or changes in Settings).
        public static func addPermissionObserver(_ observer: NotificationPermissionObserver) {
            AppPushService.shared.permissionObservers.append(observer)
        }

        public static func removePermissionObserver(_ observer: NotificationPermissionObserver) {
            AppPushService.shared.permissionObservers.removeAll { $0 === observer }
        }

        // MARK: - Foreground Lifecycle Listener

        /// Add a listener to control notification display when app is in foreground.
        /// Call event.preventDefault() inside the listener to suppress the system banner.
        /// If not prevented, banner + badge + sound are shown (default behaviour).
        public static func addForegroundLifecycleListener(_ listener: NotificationLifecycleListener) {
            AppPushService.shared.foregroundListeners.append(listener)
        }

        public static func removeForegroundLifecycleListener(_ listener: NotificationLifecycleListener) {
            AppPushService.shared.foregroundListeners.removeAll { $0 === listener }
        }

        // MARK: - Click Listener

        /// Add a listener that fires when the user taps a notification or an action button.
        /// `event.result.actionId` is nil for a body tap; non-nil for a specific action button.
        public static func addClickListener(_ listener: NotificationClickListener) {
            AppPushService.shared.clickListeners.append(listener)
        }

        public static func removeClickListener(_ listener: NotificationClickListener) {
            AppPushService.shared.clickListeners.removeAll { $0 === listener }
        }

        // MARK: - Management

        /// Remove all delivered notifications from Notification Center and lock screen.
        public static func clearAllNotifications() {
            AppPushService.clearAllNotifications()
        }

        /// Remove a specific delivered notification by its identifier.
        public static func removeNotification(withIdentifier identifier: String) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            AppPushService.log("Notification removed: \(identifier)", level: .debug)
        }

        /// Remove multiple notifications by their identifiers.
        public static func removeNotifications(withIdentifiers identifiers: [String]) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }
}
