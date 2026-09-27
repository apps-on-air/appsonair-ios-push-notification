import UIKit
import AppsOnAir_AppPush

class AppDelegate: NSObject, UIApplicationDelegate, PushListener,
                   NotificationPermissionObserver, NotificationLifecycleListener,
                   NotificationClickListener, PushSubscriptionObserver, UserStateObserver {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppsOnAirBackgroundSync.registerHandlers()
        AppPushService.initialize(debug: true, swizzle: true)
        AppPushService.setListener(self)
        AppPushService.Notifications.addPermissionObserver(self)
        AppPushService.Notifications.addForegroundLifecycleListener(self)
        AppPushService.Notifications.addClickListener(self)
        AppPushService.User.pushSubscription.addObserver(self)
        AppPushService.User.addObserver(self)
        AppPushService.requestPermission()
        AppsOnAirBackgroundSync.scheduleIfNeeded()

        AppPushService.onSilentPushReceived = { userInfo, completion in
            print("==============================")
            print("[SilentPush] RECEIVED")
            print("[SilentPush] Full userInfo: \(userInfo)")
            let notifId   = userInfo["notification_id"] as? String ?? "-"
            let customKey = userInfo["custom_key"] as? String ?? "-"
            let type      = userInfo["type"] as? String ?? "-"
            print("[SilentPush] notification_id : \(notifId)")
            print("[SilentPush] custom_key      : \(customKey)")
            print("[SilentPush] type            : \(type)")
            print("[SilentPush] Calling completion(.newData)")
            print("==============================")
            let display = "id=\(notifId) custom_key=\(customKey)"
            Task { @MainActor in
                SDKState.shared.liveSilentPushEvent = display
            }
            completion(.newData)
        }

        return true
    }

    // MARK: - PushListener

    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) {
        print("==============================")
        print("APNs TOKEN:", token)
        print("Environment:", environment.rawValue)
        print("==============================")
        let env = environment == .sandbox ? "sandbox" : "production"
        Task { @MainActor in
            let state = SDKState.shared
            state.apnsToken = token
            state.apnsEnvironment = env
            state.liveTokenEvent = "[\(env)] \(token.prefix(16))…"
        }
    }

    func onNotificationReceived(notification: PushNotification) {
        print("RECEIVED — id:\(notification.id ?? "-") title:\(notification.title ?? "-")")
        let display = "title=\(notification.title ?? "(nil)") id=\(notification.id ?? "(nil)")"
        Task { @MainActor in
            SDKState.shared.liveReceivedEvent = display
        }
    }

    func onNotificationOpened(notification: PushNotification) {
        print("OPENED — id:\(notification.id ?? "-") title:\(notification.title ?? "-")")
        let display = "title=\(notification.title ?? "(nil)") id=\(notification.id ?? "(nil)")"
        Task { @MainActor in
            SDKState.shared.liveOpenedEvent = display
        }
    }

    func onError(_ error: PushError) {
        print("ERROR [\(error.code)] \(error.message)")
        let display = "code=\(error.code) \(error.message)"
        Task { @MainActor in
            SDKState.shared.liveErrorEvent = display
        }
    }

    // MARK: - NotificationPermissionObserver

    func onNotificationPermissionDidChange(_ permission: Bool) {
        let display = permission ? "granted (observer)" : "not granted (observer)"
        Task { @MainActor in
            SDKState.shared.permissionGranted = display
        }
    }

    // MARK: - NotificationLifecycleListener

    func onWillDisplay(event: NotificationWillDisplayEvent) {
        print("[AppDelegate] will display: \(event.notification.title ?? "-")")
        // Allow the system banner — do NOT call event.preventDefault()
    }

    // MARK: - NotificationClickListener

    func onClick(event: NotificationClickEvent) {
        print("[AppDelegate] click — title=\(event.notification.title ?? "-") actionId=\(event.result.actionId ?? "(body tap)")")
    }

    // MARK: - PushSubscriptionObserver

    func onPushSubscriptionDidChange(state: PushSubscriptionChangedState) {
        let display = state.current.optedIn ? "YES (observer)" : "NO (observer)"
        Task { @MainActor in
            SDKState.shared.optedIn = display
        }
    }

    // MARK: - UserStateObserver

    func onUserStateDidChange(state: UserChangedState) {
        let display = state.current.externalId ?? "(nil — observer)"
        Task { @MainActor in
            SDKState.shared.externalId = display
        }
    }
}
