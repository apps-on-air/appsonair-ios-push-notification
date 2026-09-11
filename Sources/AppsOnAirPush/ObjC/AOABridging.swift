import Foundation

// MARK: - AOABridgeStorage

/// Singleton that keeps ObjC → Swift adapter objects alive as long as their
/// corresponding ObjC observer/listener is alive.
///
/// NSMapTable weak-to-strong: when the ObjC object (key) is deallocated the
/// entry is automatically pruned, and the Swift adapter (value) is released.
@MainActor
final class AOABridgeStorage {
    static let shared = AOABridgeStorage()
    private init() {}

    // Single-slot push listener adapter (only one listener is supported).
    var pushListenerAdapter: AOAPushListenerBridge?

    // Multi-observer maps: ObjC observer → Swift bridge adapter
    let permissionAdapters    = NSMapTable<AnyObject, AOAPermissionObserverBridge>.weakToStrongObjects()
    let lifecycleAdapters     = NSMapTable<AnyObject, AOALifecycleListenerBridge>.weakToStrongObjects()
    let clickAdapters         = NSMapTable<AnyObject, AOAClickListenerBridge>.weakToStrongObjects()
    let subscriptionAdapters  = NSMapTable<AnyObject, AOASubscriptionObserverBridge>.weakToStrongObjects()
    let userStateAdapters     = NSMapTable<AnyObject, AOAUserStateObserverBridge>.weakToStrongObjects()
}

// MARK: - AOAPushListenerBridge

/// Bridges AOAPushListener (ObjC) → PushListener (Swift).
/// Not @MainActor at class level — PushListener protocol is not @MainActor,
/// so conforming a @MainActor class to it causes Swift 6 data-race errors.
/// The SDK always calls PushListener methods on the main thread; the
/// objcListener reference is nonisolated(unsafe) because it is only ever
/// read/written on the main thread in practice.
final class AOAPushListenerBridge: PushListener {
    nonisolated(unsafe) weak var objcListener: (any AOAPushListener)?

    init(_ listener: any AOAPushListener) {
        self.objcListener = listener
    }

    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) {
        objcListener?.onAPNsTokenUpdated?(token: token, environment: environment.aoaValue)
    }

    func onNotificationReceived(notification: PushNotification) {
        objcListener?.onNotificationReceived?(notification: AOAPushNotification(notification))
    }

    func onNotificationOpened(notification: PushNotification) {
        objcListener?.onNotificationOpened?(notification: AOAPushNotification(notification))
    }

    func onError(_ error: PushError) {
        objcListener?.onError?(error.nsError)
    }
}

// MARK: - AOAPermissionObserverBridge

/// Bridges AOANotificationPermissionObserver (ObjC) → NotificationPermissionObserver (Swift).
final class AOAPermissionObserverBridge: NotificationPermissionObserver {
    nonisolated(unsafe) weak var objcObserver: (any AOANotificationPermissionObserver)?

    init(_ observer: any AOANotificationPermissionObserver) {
        self.objcObserver = observer
    }

    func onNotificationPermissionDidChange(_ permission: Bool) {
        objcObserver?.onNotificationPermissionDidChange(permission)
    }
}

// MARK: - AOALifecycleListenerBridge

/// Bridges AOANotificationLifecycleListener (ObjC) → NotificationLifecycleListener (Swift).
final class AOALifecycleListenerBridge: NotificationLifecycleListener {
    nonisolated(unsafe) weak var objcListener: (any AOANotificationLifecycleListener)?

    init(_ listener: any AOANotificationLifecycleListener) {
        self.objcListener = listener
    }

    func onWillDisplay(event: NotificationWillDisplayEvent) {
        objcListener?.onWillDisplay(event: AOANotificationWillDisplayEvent(event))
    }
}

// MARK: - AOAClickListenerBridge

/// Bridges AOANotificationClickListener (ObjC) → NotificationClickListener (Swift).
final class AOAClickListenerBridge: NotificationClickListener {
    nonisolated(unsafe) weak var objcListener: (any AOANotificationClickListener)?

    init(_ listener: any AOANotificationClickListener) {
        self.objcListener = listener
    }

    func onClick(event: NotificationClickEvent) {
        objcListener?.onClick(event: AOANotificationClickEvent(event))
    }
}

// MARK: - AOASubscriptionObserverBridge

/// Bridges AOAPushSubscriptionObserver (ObjC) → PushSubscriptionObserver (Swift).
final class AOASubscriptionObserverBridge: PushSubscriptionObserver {
    nonisolated(unsafe) weak var objcObserver: (any AOAPushSubscriptionObserver)?

    init(_ observer: any AOAPushSubscriptionObserver) {
        self.objcObserver = observer
    }

    func onPushSubscriptionDidChange(state: PushSubscriptionChangedState) {
        objcObserver?.onPushSubscriptionDidChange(state: AOAPushSubscriptionChangedState(state))
    }
}

// MARK: - AOAUserStateObserverBridge

/// Bridges AOAUserStateObserver (ObjC) → UserStateObserver (Swift).
final class AOAUserStateObserverBridge: UserStateObserver {
    nonisolated(unsafe) weak var objcObserver: (any AOAUserStateObserver)?

    init(_ observer: any AOAUserStateObserver) {
        self.objcObserver = observer
    }

    func onUserStateDidChange(state: UserChangedState) {
        objcObserver?.onUserStateDidChange(state: AOAUserChangedState(state))
    }
}
