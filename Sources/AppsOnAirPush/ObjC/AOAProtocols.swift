import Foundation

// MARK: - AOAPushListener

/// ObjC-compatible push event listener.
/// All methods are optional — implement only what you need.
@objc(AOAPushListener)
public protocol AOAPushListener: AnyObject {
    /// Called when APNs issues or rotates a device token.
    @objc optional func onAPNsTokenUpdated(token: String, environment: AOAAPNsEnvironment)
    /// Called when a notification arrives while the app is in the foreground.
    @objc optional func onNotificationReceived(notification: AOAPushNotification)
    /// Called when the user taps a notification.
    @objc optional func onNotificationOpened(notification: AOAPushNotification)
    /// Called on any SDK error.
    @objc optional func onError(_ error: NSError)
}

// MARK: - AOANotificationLifecycleListener

/// ObjC-compatible foreground lifecycle listener.
@objc(AOANotificationLifecycleListener)
public protocol AOANotificationLifecycleListener: AnyObject {
    /// Called when a notification is about to be displayed in the foreground.
    /// Call `event.preventDefault()` to suppress the system banner.
    @objc func onWillDisplay(event: AOANotificationWillDisplayEvent)
}

// MARK: - AOANotificationClickListener

/// ObjC-compatible click listener.
@objc(AOANotificationClickListener)
public protocol AOANotificationClickListener: AnyObject {
    /// Called when the user taps a notification or an action button.
    @objc func onClick(event: AOANotificationClickEvent)
}

// MARK: - AOANotificationPermissionObserver

/// ObjC-compatible notification permission observer.
@objc(AOANotificationPermissionObserver)
public protocol AOANotificationPermissionObserver: AnyObject {
    /// Called when notification permission status changes.
    @objc func onNotificationPermissionDidChange(_ permission: Bool)
}

// MARK: - AOAPushSubscriptionObserver

/// ObjC-compatible push subscription observer.
@objc(AOAPushSubscriptionObserver)
public protocol AOAPushSubscriptionObserver: AnyObject {
    /// Called when the push subscription state changes (token or opt-in state).
    @objc func onPushSubscriptionDidChange(state: AOAPushSubscriptionChangedState)
}

// MARK: - AOAUserStateObserver

/// ObjC-compatible user state observer.
@objc(AOAUserStateObserver)
public protocol AOAUserStateObserver: AnyObject {
    /// Called when the user state changes (e.g. after login/logout).
    @objc func onUserStateDidChange(state: AOAUserChangedState)
}
