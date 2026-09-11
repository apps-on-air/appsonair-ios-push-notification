import Foundation
import UIKit
import UserNotifications

// MARK: - AOAPush

/// ObjC-compatible facade for AppsOnAirPush.
///
/// Exposes all top-level SDK methods as a flat ObjC class.
/// Use in Objective-C: `[AOAPush initializeWithDebug:YES swizzle:YES]`
@objc(AOAPush)
public final class AOAPush: NSObject {

    private override init() {}

    // MARK: - Initialize (ObjC can't see Swift default parameters)
    // `initialize` is reserved by the ObjC runtime — NSObject subclasses cannot define
    // a Swift func named `initialize` at all (even with a renamed @objc selector).
    // Swift function names are `initializeSDK` / `initializeWithDebug` / `initializeWithDebugAndSwizzle`;
    // the @objc(...) attribute pins the ObjC-visible selector to the expected names.

    /// Initialize the SDK with default settings (debug=false, swizzle=true).
    /// ObjC: `[AOAPush initializeSDK]`
    @objc(initializeSDK) @MainActor
    public static func initializeSDK() {
        AppsOnAirPush.initialize(debug: false, swizzle: true)
    }

    /// Initialize the SDK with a debug flag (swizzle=true).
    /// ObjC: `[AOAPush initializeWithDebug:YES]`
    @objc(initializeWithDebug:) @MainActor
    public static func initializeWithDebug(_ debug: Bool) {
        AppsOnAirPush.initialize(debug: debug, swizzle: true)
    }

    /// Initialize the SDK with full control over debug and swizzle options.
    /// ObjC: `[AOAPush initializeWithDebug:YES swizzle:YES]`
    @objc(initializeWithDebug:swizzle:) @MainActor
    public static func initializeWithDebug(_ debug: Bool, swizzle: Bool) {
        AppsOnAirPush.initialize(debug: debug, swizzle: swizzle)
    }

    // MARK: - Listener

    /// Set the push event listener. Pass nil to remove the current listener.
    @objc @MainActor
    public static func setListener(_ listener: (any AOAPushListener)?) {
        let storage = AOABridgeStorage.shared
        guard let listener else {
            storage.pushListenerAdapter = nil
            AppsOnAirPush.setListener(nil)
            return
        }
        let bridge = AOAPushListenerBridge(listener)
        storage.pushListenerAdapter = bridge
        AppsOnAirPush.setListener(bridge)
    }

    // MARK: - Device / Subscription identity

    /// A stable unique ID for this device, stored in Keychain.
    @objc @MainActor
    public static var deviceId: String {
        AppsOnAirPush.deviceId
    }

    /// Backend-assigned subscription ID. Nil until the backend assigns one.
    @objc @MainActor
    public static var subscriptionId: String? {
        AppsOnAirPush.subscriptionId
    }

    /// Manually set the subscription ID received from your backend.
    @objc @MainActor
    public static func setSubscriptionId(_ id: String) {
        AppsOnAirPush.setSubscriptionId(id)
    }

    // MARK: - Test Device

    /// Mark / unmark this device as a test device.
    @objc @MainActor
    public static var isTestDevice: Bool {
        get { AppsOnAirPush.isTestDevice }
        set { AppsOnAirPush.isTestDevice = newValue }
    }

    // MARK: - APNs Environment

    /// The APNs environment detected from the app's entitlements.
    @objc @MainActor
    public static var apnsEnvironment: AOAAPNsEnvironment {
        AppsOnAirPush.apnsEnvironment.aoaValue
    }

    // MARK: - Permission

    /// Request OS notification permission.
    @objc @MainActor
    public static func requestPermission() {
        AppsOnAirPush.requestPermission()
    }

    // MARK: - Login / Logout

    /// Link this device to an identified user.
    @objc @MainActor
    public static func login(_ externalId: String) {
        AppsOnAirPush.login(externalId)
    }

    /// Unlink this device from the identified user. Reverts to anonymous state.
    @objc @MainActor
    public static func logout() {
        AppsOnAirPush.logout()
    }

    // MARK: - Consent

    /// Whether explicit consent is required before the SDK sends data.
    @objc @MainActor
    public static var consentRequired: Bool {
        get { AppsOnAirPush.consentRequired }
        set { AppsOnAirPush.consentRequired = newValue }
    }

    /// Grant or revoke user consent. Relevant only when consentRequired is true.
    @objc @MainActor
    public static var consentGiven: Bool {
        get { AppsOnAirPush.consentGiven }
        set { AppsOnAirPush.consentGiven = newValue }
    }

    // MARK: - Async → callback bridging

    /// Check whether notification permission is currently granted.
    /// The result is delivered to `completion` on the main thread.
    @objc
    public static func isPermissionGranted(completion: @escaping @Sendable (Bool) -> Void) {
        Task { @MainActor in
            completion(await AppsOnAirPush.isPermissionGranted())
        }
    }

    // MARK: - Notification management

    /// Remove all delivered notifications from Notification Center.
    @objc @MainActor
    public static func clearAllNotifications() {
        AppsOnAirPush.clearAllNotifications()
    }

    // MARK: - Badge

    /// Whether the badge is automatically cleared when the app enters the foreground.
    @objc @MainActor
    public static var autoClearBadgeOnForeground: Bool {
        get { AppsOnAirPush.autoClearBadgeOnForeground }
        set { AppsOnAirPush.autoClearBadgeOnForeground = newValue }
    }

    /// The current running badge count tracked by the SDK.
    @objc @MainActor
    public static var badgeCount: Int {
        AppsOnAirPush.badgeCount
    }

    /// Set the app-icon badge count.
    @objc @MainActor
    public static func setBadgeCount(_ count: Int) {
        AppsOnAirPush.setBadgeCount(count)
    }

    /// Add `delta` to the current badge count. Returns the new count.
    @objc @MainActor
    @discardableResult
    public static func incrementBadgeCount(by delta: Int) -> Int {
        AppsOnAirPush.incrementBadgeCount(by: delta)
    }

    /// Clear the app-icon badge (sets count to 0).
    @objc @MainActor
    public static func clearBadgeCount() {
        AppsOnAirPush.clearBadgeCount()
    }

    // MARK: - Auto-register

    /// When true (default), the SDK calls `registerForRemoteNotifications()` automatically
    /// during `initialize()`. Set to false before `initialize()` to manage registration yourself.
    @objc @MainActor
    public static var autoRegisterForRemoteNotifications: Bool {
        get { AppsOnAirPush.autoRegisterForRemoteNotifications }
        set { AppsOnAirPush.autoRegisterForRemoteNotifications = newValue }
    }

    // MARK: - APNs handlers (for swizzle: false apps)

    /// Forward APNs device token data to the SDK.
    @objc @MainActor
    public static func handleAPNsToken(_ deviceToken: Data) {
        AppsOnAirPush.handleAPNsToken(deviceToken)
    }

    /// Forward APNs registration errors to the SDK.
    @objc @MainActor
    public static func handleAPNsRegistrationError(_ error: Error) {
        AppsOnAirPush.handleAPNsRegistrationError(error)
    }

    // MARK: - UNUserNotificationCenterDelegate forwarding (swizzle: false only)

    /// Forward `userNotificationCenter(_:willPresent:withCompletionHandler:)` to the SDK.
    /// Only needed when you initialize with `swizzle: false`.
    /// Returns the presentation options the SDK selects for the foreground notification.
    @objc @MainActor
    public static func handleWillPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        AppsOnAirPush.handleWillPresent(notification: notification)
    }

    /// Forward `userNotificationCenter(_:didReceive:withCompletionHandler:)` to the SDK.
    /// Only needed when you initialize with `swizzle: false`.
    @objc @MainActor
    public static func handleDidReceive(response: UNNotificationResponse) {
        AppsOnAirPush.handleDidReceive(response: response)
    }

    // MARK: - Silent Push

    /// ObjC-compatible silent push handler block.
    /// Set this before `initialize()` to receive silent pushes.
    ///
    /// The NSDictionary parameter is the APNs userInfo payload.
    @objc @MainActor
    public static var onSilentPushReceived: ((NSDictionary, @escaping (UIBackgroundFetchResult) -> Void) -> Void)? {
        get {
            guard let swiftHandler = AppsOnAirPush.onSilentPushReceived else { return nil }
            return { userInfo, completion in
                swiftHandler((userInfo as? [AnyHashable: Any]) ?? [:], completion)
            }
        }
        set {
            guard let newValue else {
                AppsOnAirPush.onSilentPushReceived = nil
                return
            }
            AppsOnAirPush.onSilentPushReceived = { userInfo, completion in
                newValue(userInfo as NSDictionary, completion)
            }
        }
    }

    /// Forward a silent push to the SDK for processing.
    @objc @MainActor
    public static func handleSilentPush(
        _ userInfo: NSDictionary,
        fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AppsOnAirPush.handleSilentPush(
            (userInfo as? [AnyHashable: Any]) ?? [:],
            fetchCompletionHandler: completion
        )
    }
}
