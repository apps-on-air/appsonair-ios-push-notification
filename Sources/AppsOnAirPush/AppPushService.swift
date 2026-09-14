@_spi(AppsOnAirInternal) import AppsOnAir_Core
import Foundation
import UIKit
import UserNotifications

// MARK: - AppPushService

@MainActor
public final class AppPushService: NSObject {

    public static let shared = AppPushService()

    internal var isConfigured = false
    internal let storage = PushStorage()
    /// Shared AppsOnAir_Core handle. Owns app-id resolution (from Info.plist) and
    /// network-reachability monitoring; also the source for AppsOnAirDeviceInfo.
    internal let core = AppsOnAirCoreServices()
    private weak var listener: PushListener?

    // MARK: - App config (set by configure())

    internal var _appId: String = ""
    internal var _appGroupId: String? = nil

    // MARK: - Persisted user state (loaded from UserDefaults in init)

    internal var tags: [String: String] = [:]
    internal var language: String = Locale.current.languageCode ?? "en"
    internal var externalId: String? = nil
    internal var isOptedOut: Bool = false
    internal var aliases: [String: String] = [:]
    internal var emails: [String] = []
    // AOA:Future — SMS support not included in push SDK scope
    // internal var smsNumbers: [String] = []

    // MARK: - Listener / observer collections

    internal var foregroundListeners: [NotificationLifecycleListener] = []
    internal var clickListeners: [NotificationClickListener] = []
    internal var permissionObservers: [NotificationPermissionObserver] = []
    internal var pushSubscriptionObservers: [PushSubscriptionObserver] = []
    internal var userStateObservers: [UserStateObserver] = []
    internal var previousPermission: Bool? = nil

    /// Last push-subscription snapshot broadcast to observers. Used by
    /// `firePushSubscriptionChange()` to suppress no-op notifications.
    internal var lastPushSubscriptionState: PushSubscriptionState? = nil

    /// Set once after an entitlement-missing APNs error (code 3000) has been
    /// reported, so a misconfigured app does not emit it on every cold launch.
    internal var didReportEntitlementError = false

    /// Set true after the backend has accepted this device's subscription
    /// (`POST /v1/subscriptions` → 2xx). The SDK registers exactly once per
    /// launch: the trigger is `initialize()` + an available push token.
    internal var didRegisterSubscription = false
    /// True while the one allowed `/v1/subscriptions` request is on the wire, so
    /// overlapping triggers (initialize / token / connectivity) don't double-POST.
    internal var subscriptionRequestInFlight = false

    /// True while a token-rotation `PATCH /v1/subscriptions/<id>` is on the wire,
    /// so a burst of APNs token callbacks doesn't fire overlapping PATCHes.
    internal var pushTokenUpdateInFlight = false

    /// Last-known OS notification authorization status. Refreshed on `initialize()`,
    /// on every app foreground, and after each permission request. Backs the
    /// synchronous `Notifications.permission` / `.permissionNative` / `.canRequestPermission`.
    internal var cachedAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    /// In-memory mirror of `UNUserNotificationCenter.current()`'s registered categories,
    /// seeded once at `initialize()` (see `seedNotificationCategories()`) and kept current
    /// as `handleWillPresent` adds action-button categories from incoming payloads. Lets
    /// registration stay a synchronous merge-and-set instead of an async round trip on
    /// every foreground notification.
    internal var knownNotificationCategories: Set<UNNotificationCategory> = []

    private override init() {
        super.init()
        // Load persisted user state
        externalId = UserDefaults.standard.string(forKey: "com.appsonair.push.externalId")
        isOptedOut = UserDefaults.standard.bool(forKey: "com.appsonair.push.isOptedOut")
        language = UserDefaults.standard.string(forKey: "com.appsonair.push.language")
                   ?? (Locale.current.languageCode ?? "en")
        if let data = UserDefaults.standard.data(forKey: "com.appsonair.push.tags"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            tags = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "com.appsonair.push.aliases"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            aliases = decoded
        }
        if let data = UserDefaults.standard.data(forKey: "com.appsonair.push.emails"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            emails = decoded
        }
        // AOA:Future — SMS: restore persisted smsNumbers here when SMS support is added
        // if let data = UserDefaults.standard.data(forKey: "com.appsonair.push.smsNumbers"),
        //    let decoded = try? JSONDecoder().decode([String].self, from: data) {
        //     smsNumbers = decoded
        // }
    }

    // MARK: - Public API

    /// Call once at app launch before anything else.
    /// Renamed from `configure()` to match OneSignal v5 (`OneSignal.initialize`) and Android (`AppPushService.initialize`).
    ///
    /// The app ID is resolved by AppsOnAir_Core from your app target's Info.plist.
    /// Add an `AppsonairAppId` (or legacy `AppsOnAirAPIKey`) String entry:
    /// `<key>AppsonairAppId</key><string>your-app-id</string>`
    /// In DEBUG builds a missing entry traps — AppsOnAir_Core calls `exit(-1)`.
    ///
    /// The App Group used to share data with the Notification Service Extension
    /// (delivery receipts, running badge counts) is read from the project itself —
    /// just like OneSignal — so there is no argument for it. See `resolveAppGroupId()`:
    ///   1. an `AppsOnAirAppGroup` String in the app's Info.plist;
    ///   2. the convention `group.<main-app-bundle-id>.appsonair`.
    /// The resolved ID still has to be a real App Group enabled on both the app and NSE
    /// targets, or the shared `UserDefaults` suite is unavailable and NSE features
    /// degrade silently.
    ///
    /// - Parameters:
    ///   - debug:   Print SDK logs to console. Keep false in production.
    ///   - swizzle: true (default) — SDK captures APNs token automatically, no AppDelegate code needed.
    ///              false — call handleAPNsToken() manually from your AppDelegate.
    public static func initialize(
        debug: Bool = false,
        swizzle: Bool = true
    ) {
        // AppsOnAir_Core reads the app ID from Info.plist ("AppsonairAppId" /
        // "AppsOnAirAPIKey") and starts network-reachability monitoring.
        // DEBUG builds trap here (exit(-1)) when the key is missing.
        shared.core.initialize()
        let appId = shared.core.appId
        guard !appId.isEmpty else {
            log("initialize() failed — add an 'AppsonairAppId' String entry to your app's Info.plist.", level: .error)
            return
        }
        // Legacy debug flag — sets logLevel to .debug if true and not already configured
        if debug && AppPushService.Debug.logLevel == .none {
            AppPushService.Debug.logLevel = .debug
        }
        shared._appId = appId
        shared._appGroupId = resolveAppGroupId()
        shared.isConfigured = true

        // Write shared data to App Group so the Notification Service Extension can read it.
        // NSE runs in a separate process and cannot link AppsOnAir_Core, so it needs a
        // copy of deviceId here. In-process code reads AppPushService.deviceId directly.
        if let groupId = shared._appGroupId, let groupDefaults = UserDefaults(suiteName: groupId) {
            groupDefaults.set(appId,    forKey: "com.appsonair.push.appId")
            groupDefaults.set(deviceId, forKey: "com.appsonair.push.deviceIdCache")
            groupDefaults.set(groupId,  forKey: "com.appsonair.push.appGroupId")
            if let sid = subscriptionId {
                groupDefaults.set(sid, forKey: "com.appsonair.push.subscriptionId")
            }
            groupDefaults.synchronize()
            log("App Group '\(groupId)' configured for NSE delivery receipts.", level: .debug)
        } else if let groupId = shared._appGroupId {
            log("App Group '\(groupId)' resolved but its UserDefaults suite is unavailable — " +
                "enable the App Group capability on the app target. NSE features are disabled.", level: .warn)
        }

        log("SDK ready. appId=\(appId) deviceId=\(deviceId)", level: .debug)

        // Seed the SDK's category cache with whatever the host app already registered
        // (async — no completion needed) so the first action-button payload merges
        // instead of clobbering the host's own categories. See `registerActionCategoryIfNeeded`.
        UNUserNotificationCenter.current().getNotificationCategories { categories in
            let box = CategoriesBox(categories: categories)
            Task { @MainActor in
                AppPushService.shared.knownNotificationCategories = box.categories
            }
        }

        // Start session tracking — observes UIApplication foreground/background lifecycle.
        // Records first_session, last_session, session_count, session_time for MAU metering (§3.9).
        AppsOnAirSessionManager.shared.start()

        // Fetch the shared device/app metadata snapshot from AppsOnAir_Core.
        // Asynchronous — registrationPayload() falls back to Bundle/UIDevice until it lands.
        AppsOnAirDeviceInfo.prime()

        // Prime the notification-permission cache and keep it fresh on every foreground
        // so Notifications.permission / .canRequestPermission can be read synchronously.
        refreshPermissionCache()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                AppPushService.refreshPermissionCache()
                AppPushService.clearBadgeOnForegroundIfEnabled()
            }
        }
        // Cold launch: clear the badge the app was launched with (matches OneSignal).
        clearBadgeOnForegroundIfEnabled()

        // AOA: Swizzler intercepts APNs callbacks automatically — no AppDelegate code needed
        if swizzle {
            PushAppDelegateSwizzler.swizzle()
        }

        // AOA: OneSignal-style token acquisition — register with APNs on every
        // launch, independent of notification permission.
        // `registerForRemoteNotifications()` shows no UI and only needs the
        // aps-environment entitlement; iOS returns a device token even when
        // permission is .notDetermined or .denied. Permission governs whether a
        // notification is *displayed*, not whether a token is issued.
        if autoRegisterForRemoteNotifications {
            #if targetEnvironment(simulator)
            let mockToken = "SIMULATOR-\(deviceId)"
            shared.storage.saveApnsToken(mockToken)
            log("Simulator — no real APNs. Stored mock token so the /subscriptions flow can run.", level: .debug)
            firePushSubscriptionChange()
            shared.listener?.onAPNsTokenUpdated(token: mockToken, environment: .sandbox)
            #else
            UIApplication.shared.registerForRemoteNotifications()
            #endif
        } else {
            log("autoRegisterForRemoteNotifications disabled — token acquired only after requestPermission().", level: .debug)
        }

        // AOA: register this device's subscription with the backend — ONCE per
        // launch. No-ops here until a push token exists; handleAPNsToken() calls
        // this again the moment the token arrives. The POST itself is gated on
        // connectivity via AppsOnAirNetworkMonitor.
        registerSubscriptionIfReady(reason: .initialize)

        // AOA: OneSignal-style — pull the backend's tag set into the local cache
        // so User.getTags() reads fresh data synchronously. No-ops until a
        // subscriptionId exists (a prior launch's, restored from storage);
        // registerSubscriptionIfReady() triggers it again on first registration.
        refreshTagsIfReady(reason: .tagsFetched)
    }

    /// Register a listener to receive push events and errors.
    public static func setListener(_ listener: PushListener?) {
        shared.listener = listener
    }

    /// The per-install device identifier — the single source of truth for
    /// `device_id` everywhere in the SDK.
    ///
    /// Sourced from AppsOnAir_Core (`AppsOnAirCoreServices.deviceId`) so the whole
    /// AppsOnAir SDK family reports the same value for a given install. Core resolves
    /// it from `UserDefaults`, falling back to the identifier-for-vendor (IDFV) and
    /// then a freshly generated UUID. It is **not** Keychain-backed: a reinstall,
    /// "clear data", or a restore onto a new device yields a new ID, and the backend
    /// then treats the install as a new device / subscription. Stable only for the
    /// life of one install.
    ///
    /// `nonisolated` and synchronous: Core resolves it from `UserDefaults` only,
    /// with no dependency on `initialize()`, so non-`@MainActor` callers
    /// (`PushEvent.init`, `AppsOnAirEventQueue`) can read it directly instead of a
    /// cached copy. The App Group mirror written by `initialize()` exists solely for
    /// the Notification Service Extension, which runs in another process and cannot
    /// link AppsOnAir_Core.
    public nonisolated static var deviceId: String {
        AppsOnAirCoreServices.deviceId
    }

    /// Backend-assigned subscription ID for this device.
    /// Nil until the host app calls /subscriptions on the backend and receives the response.
    ///
    /// TODO: This should be set automatically by the SDK once the /subscriptions BE API is integrated.
    /// For now, the host app must call setSubscriptionId(_:) after receiving the ID from the backend.
    public static var subscriptionId: String? {
        get { shared.storage.subscriptionId }
        set {
            guard let id = newValue else { return }
            shared.storage.saveSubscriptionId(id)
            // Mirror to App Group so the Notification Service Extension can include it in receipts.
            if let groupId = shared._appGroupId,
               let groupDefaults = UserDefaults(suiteName: groupId) {
                groupDefaults.set(id, forKey: "com.appsonair.push.subscriptionId")
                groupDefaults.synchronize()
            }
            log("Subscription ID set: \(id)", level: .debug)
        }
    }

    /// Call this once the backend returns a subscription ID after POST /subscriptions.
    /// Persists the ID and includes it in all subsequent event reports (open, click, delivery).
    ///
    /// TODO: Remove this method once the SDK calls /subscriptions internally and sets
    /// subscriptionId automatically from the response.
    public static func setSubscriptionId(_ id: String) {
        guard !id.isEmpty else {
            log("setSubscriptionId() failed — id cannot be empty.", level: .error)
            return
        }
        subscriptionId = id
    }

    /// Mark this device as a test device for targeting purposes.
    /// Test devices can receive test pushes sent from the console without affecting real users.
    /// Scope §3.1: test-device flag is part of the Subscription entity.
    public static var isTestDevice: Bool {
        get { UserDefaults.standard.bool(forKey: "com.appsonair.push.isTestDevice") }
        set {
            UserDefaults.standard.set(newValue, forKey: "com.appsonair.push.isTestDevice")
            log("isTestDevice set to \(newValue). " +
                "TODO: include in next POST /subscriptions call.", level: .debug)
        }
    }

    /// Reads aps-environment directly from the app's embedded entitlements.
    /// This is 100% accurate — no extra APNs calls needed.
    /// Defaults to .production if entitlement cannot be read (safe for App Store builds).
    public static var apnsEnvironment: APNsEnvironment {
        // App Store / TestFlight builds do not include embedded.mobileprovision
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              // Profile is UTF-8 with binary sections — isoLatin1 reads it safely
              let content = String(data: data, encoding: .isoLatin1),
              content.contains("aps-environment") else {
            return .production
        }
        // development = sandbox (debug/Xcode/Ad-hoc), production = App Store/TestFlight
        return content.contains("<string>development</string>") ? .sandbox : .production
    }

    // MARK: - Subscription / opt-in state (OneSignal-style)

    /// Whether the SDK registers with APNs automatically at launch — the
    /// OneSignal model, where a device token (and a subscription record) is
    /// acquired regardless of notification permission.
    ///
    /// `true` (default). Set `<key>AppsOnAirDisableAutoRegister</key><true/>` in
    /// the app's Info.plist to opt out and only register after `requestPermission()`.
    public static var autoRegisterForRemoteNotifications: Bool = {
        !(Bundle.main.object(forInfoDictionaryKey: "AppsOnAirDisableAutoRegister") as? Bool ?? false)
    }()

    /// The `enabled` flag reported to the backend `/subscriptions` endpoint.
    ///
    /// `true` only when the device has an APNs token, the user has not called
    /// `User.pushSubscription.optOut()`, **and** the OS currently grants
    /// notification permission. A device with a token but denied/undetermined
    /// permission is still a valid subscription (it can take silent pushes) — it
    /// just reports `enabled = false`.
    public static var isOptedIn: Bool {
        guard let token = shared.storage.getApnsToken(), !token.isEmpty else { return false }
        return !shared.isOptedOut && Notifications.permission
    }

    /// Broadcast a push-subscription change to observers registered through
    /// `AppPushService.User.pushSubscription.addObserver(_:)`. Fires when the APNs
    /// token first arrives or refreshes, when the backend returns a
    /// `subscriptionId`, and when notification permission flips. No-ops when
    /// neither the token nor the opt-in state actually changed.
    internal static func firePushSubscriptionChange() {
        let current = PushSubscriptionState(token: shared.storage.getApnsToken(), optedIn: isOptedIn)
        let previous = shared.lastPushSubscriptionState ?? current
        shared.lastPushSubscriptionState = current
        guard previous.token != current.token || previous.optedIn != current.optedIn else { return }
        let change = PushSubscriptionChangedState(previous: previous, current: current)
        shared.pushSubscriptionObservers.forEach { $0.onPushSubscriptionDidChange(state: change) }
    }

    /// Register this device's push subscription with the backend — ONCE per app
    /// launch. The trigger is `initialize()` + an available push token:
    ///
    ///   • called at the end of `initialize()` (token may already be cached), and
    ///   • called again from `handleAPNsToken()` the moment the token arrives.
    ///
    /// It no-ops if already registered, if a request is in flight, before
    /// `initialize()`, or while there is no push token. The actual POST is
    /// deferred to `AppsOnAirNetworkMonitor.runWhenConnected` so it only leaves
    /// the device when AppsOnAir_Core reports connectivity. The raw URLSession
    /// result is parsed here — `AppsOnAirSubscriptionAPI` only does transport.
    internal static func registerSubscriptionIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard !shared.didRegisterSubscription else {
            print("[AppPushService] subscription already registered this launch — skip (\(reason))")
            return
        }
        guard !shared.subscriptionRequestInFlight else {
            print("[AppPushService] subscription request already in flight — skip (\(reason))")
            return
        }
        guard let token = shared.storage.getApnsToken(), !token.isEmpty else {
            print("[AppPushService] no push token yet — subscription deferred (\(reason))")
            return
        }

        print("[AppPushService] subscription ready to register (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            // State may have changed while queued for connectivity.
            guard !shared.didRegisterSubscription, !shared.subscriptionRequestInFlight else { return }
            shared.subscriptionRequestInFlight = true
            print("[AppPushService] POST /v1/subscriptions (\(reason))")

            AppsOnAirSubscriptionAPI.registerDevice { data, response, error in
                shared.subscriptionRequestInFlight = false
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1

                if let error {
                    print("[AppPushService] /v1/subscriptions error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] /v1/subscriptions HTTP \(status) (\(reason)): \(bodyText)")

                guard (200..<300).contains(status) else {
                    print("[AppPushService] /v1/subscriptions non-2xx — not marking registered")
                    return
                }

                // Success — this is the one registration for this launch.
                shared.didRegisterSubscription = true

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[AppPushService] /v1/subscriptions 2xx but response body was not JSON")
                    return
                }
                let sid = (json["subscriptionId"] as? String)
                    ?? (json["subscription_id"] as? String)
                    ?? ((json["data"] as? [String: Any])?["subscriptionId"] as? String)
                if let sid, !sid.isEmpty {
                    print("[AppPushService] /v1/subscriptions subscriptionId=\(sid)")
                    setSubscriptionId(sid)              // persists + mirrors to App Group
                    firePushSubscriptionChange()
                    // Now that a subscriptionId exists, pull the backend's tag set
                    // into the local cache so User.getTags() reads it synchronously.
                    refreshTagsIfReady(reason: .tagsFetched)
                } else {
                    print("[AppPushService] /v1/subscriptions 2xx but no subscriptionId in response")
                }
            }
        }
    }

    /// PATCH the backend subscription's `enabled` flag so it matches the current
    /// notification-permission status — `true` when granted, `false` otherwise.
    ///
    /// Same deferral as `registerSubscriptionIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()` or while
    /// there is no `subscriptionId` (nothing to update yet). The permission value
    /// is re-read inside the connectivity closure so a late send reflects reality.
    internal static func updateSubscriptionEnabledIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — enabled sync deferred (\(reason))")
            return
        }

        print("[AppPushService] subscription enabled sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            let enabled = Notifications.permission
            print("[AppPushService] PATCH /v1/subscriptions enabled=\(enabled) (\(reason))")

            AppsOnAirSubscriptionAPI.updateSubscription(enabled: enabled) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] PATCH /v1/subscriptions error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] PATCH /v1/subscriptions HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// PATCH the backend subscription with a rotated APNs push token so the
    /// backend keeps sending to a live token.
    ///
    /// Called from `handleAPNsToken()` whenever the freshly received token differs
    /// from the one already stored (iOS reissues tokens after restore-from-backup,
    /// some OS upgrades, and app reinstalls). Same deferral as
    /// `registerSubscriptionIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()`, while
    /// there is no `subscriptionId` (the POST will carry the new token instead),
    /// or while a PATCH is already in flight. The token is re-read inside the
    /// connectivity closure so a late send reflects the newest value.
    internal static func updatePushTokenIfRotated(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — token PATCH deferred (\(reason))")
            return
        }
        guard !shared.pushTokenUpdateInFlight else {
            print("[AppPushService] token PATCH already in flight — skip (\(reason))")
            return
        }

        print("[AppPushService] push token rotated (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            guard !shared.pushTokenUpdateInFlight else { return }
            shared.pushTokenUpdateInFlight = true
            print("[AppPushService] PATCH /v1/subscriptions push_token (\(reason))")

            AppsOnAirSubscriptionAPI.updatePushToken { data, response, error in
                shared.pushTokenUpdateInFlight = false
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] PATCH /v1/subscriptions push_token error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] PATCH /v1/subscriptions push_token HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// PATCH the backend subscription's `external_id` so it matches the SDK's
    /// current identified-user state — the value passed to `login(_:)`, or JSON
    /// `null` after `logout()`.
    ///
    /// Same deferral as `updateSubscriptionEnabledIfReady()`: the request is handed
    /// to `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device
    /// once AppsOnAir_Core reports connectivity. No-ops before `initialize()` or
    /// while there is no `subscriptionId` — the `POST /v1/subscriptions` body
    /// carries the current `external_id` in that case, so nothing is lost. The
    /// `externalId` is re-read inside the connectivity closure so a late send
    /// reflects the most recent `login()` / `logout()`.
    internal static func syncExternalIdIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — external_id sync deferred (\(reason))")
            return
        }

        print("[AppPushService] external_id sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            let externalId = shared.externalId
            print("[AppPushService] PATCH /v1/subscriptions external_id=\(externalId ?? "null") (\(reason))")

            AppsOnAirSubscriptionAPI.updateExternalId(externalId) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] PATCH /v1/subscriptions external_id error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] PATCH /v1/subscriptions external_id HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// POST /v1/subscriptions/<id>/opt-in or …/opt-out so the backend
    /// subscription's opt-in state matches the SDK's local state after
    /// `User.pushSubscription.optIn()` / `optOut()`.
    ///
    /// Same deferral as `updateSubscriptionEnabledIfReady()`: the request is
    /// handed to `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the
    /// device once AppsOnAir_Core reports connectivity. No-ops before
    /// `initialize()` or while there is no `subscriptionId` — the
    /// `POST /v1/subscriptions` body carries the current opt-in state in its
    /// `enabled` field in that case, so nothing is lost. `isOptedOut` is re-read
    /// inside the connectivity closure so a rapid `optOut()` / `optIn()` toggle
    /// only sends the final state.
    internal static func syncOptInStateIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — opt-in sync deferred (\(reason))")
            return
        }

        print("[AppPushService] opt-in state sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            let optedOut = shared.isOptedOut
            print("[AppPushService] POST /v1/subscriptions/\(sid)/\(optedOut ? "opt-out" : "opt-in") (\(reason))")

            AppsOnAirSubscriptionAPI.updateOptInState(optedOut: optedOut) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] opt-in state POST error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] opt-in state POST HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// PATCH /v1/subscriptions/<id>/language so the backend subscription's
    /// language matches the SDK's local override after `User.setLanguage(_:)`.
    ///
    /// Same deferral as `syncOptInStateIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()` or while
    /// there is no `subscriptionId` — the `POST /v1/subscriptions` body carries
    /// the current `language` in that case, so nothing is lost. `shared.language`
    /// is re-read inside the connectivity closure so a rapid sequence of
    /// `setLanguage()` calls only sends the final value.
    internal static func syncLanguageIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — language sync deferred (\(reason))")
            return
        }

        print("[AppPushService] language sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            let language = shared.language
            print("[AppPushService] PATCH /v1/subscriptions/\(sid)/language language=\(language) (\(reason))")

            AppsOnAirSubscriptionAPI.updateLanguage(language) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] language PATCH error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] language PATCH HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// POST /v1/subscriptions/<id>/tags so the backend subscription's tags match
    /// the SDK's local set after `User.addTag()` / `User.addTags()`.
    ///
    /// Same deferral as `syncOptInStateIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()` or while
    /// there is no `subscriptionId` — the tags are already persisted locally, and
    /// the next `addTag()` / `addTags()` after the subscription exists flushes
    /// the whole set. `shared.tags` is re-read inside the connectivity closure so
    /// a late send carries every tag added while offline.
    internal static func syncTagsIfReady(reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — tags sync deferred (\(reason))")
            return
        }

        print("[AppPushService] tags sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            let tags = shared.tags
            guard !tags.isEmpty else {
                print("[AppPushService] no tags to sync (\(reason))")
                return
            }
            print("[AppPushService] POST /v1/subscriptions/\(sid)/tags \(tags) (\(reason))")

            AppsOnAirSubscriptionAPI.updateTags(tags) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] tags POST error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] tags POST HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// POST /v1/subscriptions/<id>/tags/remove so the given keys are dropped from
    /// the backend subscription's tag set after `User.removeTag()` /
    /// `User.removeTags()`.
    ///
    /// Same deferral as `syncTagsIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()`, while
    /// there is no `subscriptionId` (nothing was ever synced, so nothing to
    /// remove), or when `keys` is empty. The keys are captured as passed — they
    /// have already been removed from `shared.tags`, so they cannot be re-derived
    /// inside the closure.
    internal static func syncTagRemovalIfReady(keys: [String], reason: AppsOnAirSyncReason) {
        guard shared.isConfigured else { return }
        let keys = keys.filter { !$0.isEmpty }
        guard !keys.isEmpty else { return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — tags/remove sync skipped (\(reason))")
            return
        }

        print("[AppPushService] tags/remove sync ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            print("[AppPushService] POST /v1/subscriptions/\(sid)/tags/remove \(keys) (\(reason))")

            AppsOnAirSubscriptionAPI.removeTags(keys) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] tags/remove POST error (\(reason)): \(error.localizedDescription)")
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] tags/remove POST HTTP \(status) (\(reason)): \(bodyText)")
            }
        }
    }

    /// GET /v1/subscriptions/<id>/tags and refresh the local tag cache
    /// (`shared.tags`, persisted to UserDefaults) from the backend response.
    ///
    /// Backs `User.getTags()` — that call returns the cache synchronously (the
    /// OneSignal model) and schedules this refresh so the next read reflects the
    /// backend. Same deferral as `syncTagsIfReady()`: the request is handed to
    /// `AppsOnAirNetworkMonitor.runWhenConnected` and only leaves the device once
    /// AppsOnAir_Core reports connectivity. No-ops before `initialize()` or while
    /// there is no `subscriptionId` (nothing has been registered to read).
    ///
    /// `completion` (main actor) receives the freshly parsed tag map on success,
    /// or the unchanged local cache when the request could not be sent, errored,
    /// returned non-2xx, or had an unparseable body.
    internal static func refreshTagsIfReady(
        reason: AppsOnAirSyncReason,
        completion: (@MainActor ([String: String]) -> Void)? = nil
    ) {
        guard shared.isConfigured else { completion?(shared.tags); return }
        guard let sid = subscriptionId, !sid.isEmpty else {
            print("[AppPushService] no subscriptionId yet — tags GET skipped (\(reason))")
            completion?(shared.tags)
            return
        }

        print("[AppPushService] tags refresh ready (\(reason)) — waiting for connectivity")
        AppsOnAirNetworkMonitor.runWhenConnected {
            print("[AppPushService] GET /v1/subscriptions/\(sid)/tags (\(reason))")

            AppsOnAirSubscriptionAPI.fetchTags { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    print("[AppPushService] tags GET error (\(reason)): \(error.localizedDescription)")
                    completion?(shared.tags)
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[AppPushService] tags GET HTTP \(status) (\(reason)): \(bodyText)")

                guard (200..<300).contains(status),
                      let remote = AppsOnAirSubscriptionAPI.parseTagsResponse(data) else {
                    completion?(shared.tags)
                    return
                }

                shared.tags = remote
                if let encoded = try? JSONEncoder().encode(remote) {
                    UserDefaults.standard.set(encoded, forKey: "com.appsonair.push.tags")
                }
                print("[AppPushService] local tag cache refreshed from backend (\(remote.count) tag(s))")
                completion?(remote)
            }
        }
    }

    /// Ask the user for notification permission and register with APNs.
    /// Renamed from `requestAuthorization()` to match OneSignal v5 (`OneSignal.Notifications.requestPermission`)
    /// and Android (`AppPushService.Notifications.requestPermission`).
    /// The permission dialog is shown on both device and simulator. On simulator the APNs
    /// device token is unavailable, so a mock token is emitted after the user grants permission.
    public static func requestPermission() {
        guard shared.isConfigured else {
            emitError(code: .notInitialized, message: "Call AppPushService.initialize() before requesting permission.")
            return
        }

        // requestAuthorization completion is called on an arbitrary background thread.
        // Hop back to @MainActor before touching any SDK state or UIKit.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    emitError(code: .permissionDenied, message: "Notification permission request failed: \(error.localizedDescription)")
                    return
                }
                if granted {
                    log("Notification permission granted.", level: .info)
                    #if targetEnvironment(simulator)
                    let mockToken = "SIMULATOR-\(deviceId)"
                    shared.storage.saveApnsToken(mockToken)
                    shared.listener?.onAPNsTokenUpdated(token: mockToken, environment: .sandbox)
                    #else
                    // Token was already requested at launch; re-assert so a fresh
                    // token callback fires if that first registration failed.
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                    // Permission just flipped on — notify local subscription observers.
                    // (No backend call here: the device subscription is registered
                    // once per launch by registerSubscriptionIfReady().)
                    firePushSubscriptionChange()
                } else {
                    log("Notification permission denied by user.", level: .warn)
                    emitError(code: .permissionDenied, message: "User denied notification permission. Ask them to enable it in Settings.")
                }
                checkPermissionChange()
            }
        }
    }

    // MARK: - Login / Logout

    /// Link this device to an identified user in your system.
    /// Call after the user signs in. All tags, aliases, and subscription state are associated with this externalId.
    /// Unlabeled argument to match OneSignal v5 (`OneSignal.login(_:)`).
    public static func login(_ externalId: String) {
        guard !externalId.isEmpty else {
            log("login() failed — externalId cannot be empty.", level: .error)
            return
        }
        shared.externalId = externalId
        UserDefaults.standard.set(externalId, forKey: "com.appsonair.push.externalId")
        log("User logged in. externalId=\(externalId)", level: .debug)
        let state = UserChangedState(current: UserState(externalId: externalId, appsOnAirId: deviceId))
        shared.userStateObservers.forEach { $0.onUserStateDidChange(state: state) }
        // Link the identified user on the backend subscription —
        // PATCH /v1/subscriptions/<id> { "external_id": <externalId> }, gated on connectivity.
        syncExternalIdIfReady(reason: .login)
        // Refresh the local tag cache — the identified user may carry a different
        // tag set than the anonymous device did. GET /v1/subscriptions/<id>/tags.
        refreshTagsIfReady(reason: .tagsFetched)
    }

    /// Unlink this device from the identified user. Reverts to anonymous state.
    /// Call on user sign-out. Tags, aliases, and externalId are cleared locally.
    public static func logout() {
        shared.externalId = nil
        shared.tags = [:]
        shared.aliases = [:]
        UserDefaults.standard.removeObject(forKey: "com.appsonair.push.externalId")
        UserDefaults.standard.removeObject(forKey: "com.appsonair.push.tags")
        UserDefaults.standard.removeObject(forKey: "com.appsonair.push.aliases")
        log("User logged out. Reverted to anonymous.", level: .debug)
        let state = UserChangedState(current: UserState(externalId: nil, appsOnAirId: deviceId))
        shared.userStateObservers.forEach { $0.onUserStateDidChange(state: state) }
        // Unlink the user on the backend subscription —
        // PATCH /v1/subscriptions/<id> { "external_id": null }, gated on connectivity.
        syncExternalIdIfReady(reason: .logout)
    }

    // MARK: - Consent

    /// Set to true if your app requires explicit user consent before the SDK can send data.
    /// When true, SDK functionality is gated on consentGiven.
    public static var consentRequired: Bool {
        get { UserDefaults.standard.bool(forKey: "com.appsonair.push.consentRequired") }
        set { UserDefaults.standard.set(newValue, forKey: "com.appsonair.push.consentRequired") }
    }

    /// Grant or revoke user consent. Only relevant when consentRequired is true.
    public static var consentGiven: Bool {
        get { UserDefaults.standard.bool(forKey: "com.appsonair.push.consentGiven") }
        set {
            UserDefaults.standard.set(newValue, forKey: "com.appsonair.push.consentGiven")
            log("Consent \(newValue ? "given" : "revoked").", level: .info)
        }
    }

    // MARK: - Notification Management

    /// Returns `true` if the user has granted notification permission (alert, badge, or sound).
    ///
    /// Checks the current `UNAuthorizationStatus` asynchronously.
    /// - `.authorized`   — user explicitly granted permission.
    /// - `.provisional`  — quiet notifications granted (iOS 12+).
    /// - `.ephemeral`    — granted for App Clips only.
    /// All other statuses (`.denied`, `.notDetermined`) return `false`.
    ///
    /// Call this before showing in-app prompts or gating notification-dependent features.
    public static func isPermissionGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Remove all notifications posted by this app from the notification center,
    /// lock screen, and banner history.
    ///
    /// Use this when the user reads all messages inside the app and the
    /// notification center should be cleared to match in-app state.
    public static func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        log("All delivered notifications cleared.", level: .debug)
    }

    // MARK: - Badge management
    //
    // The SDK maintains a running badge count the way OneSignal does, instead of letting
    // every push overwrite the icon with whatever `aps.badge` it carried.
    //
    //   • The Notification Service Extension applies `badge` / `badge_increment` from the
    //     payload and stores the running total in the App Group
    //     (`com.appsonair.push.badgeCount`). Requires an App Group + `mutable-content: 1`.
    //   • On foreground the main app resets that total to 0 — UNLESS the host app set
    //     `autoClearBadgeOnForeground = false` (or `AppsOnAirDisableBadgeClearing` in
    //     Info.plist). In that mode nothing is cleared on foreground; instead the SDK
    //     subtracts 1 from the running total for every notification the user opens, so
    //     tapping 1 of 5 stacked notifications leaves the icon showing 4.
    //   • `setBadgeCount` / `incrementBadgeCount` / `clearBadgeCount` keep the icon and
    //     the shared total in sync so manual and push-driven changes don't fight.

    /// App Group key holding the running badge total. Mirrors `SharedKey.badgeCount`
    /// in the `AppsOnAirPushServiceExt` target.
    private static let badgeCountKey = "com.appsonair.push.badgeCount"

    /// Controls what the SDK does with the badge when the app is opened.
    ///
    /// - `true` (default): the app-icon badge and the shared running total are reset to
    ///   `0` every time the app enters the foreground — matches OneSignal's default.
    /// - `false`: the badge is **not** cleared on foreground. Instead the SDK subtracts
    ///   `1` from the running total for each notification the user opens, so tapping one
    ///   of several stacked notifications counts it down (5 → 4 → …) instead of zeroing.
    ///   The host app writes no code for this — it happens inside `handleDidReceive`.
    ///
    /// Set it in code, or add `<key>AppsOnAirDisableBadgeClearing</key><true/>` to the
    /// app's Info.plist (that key `true` ⇒ this flag `false`).
    public static var autoClearBadgeOnForeground: Bool = {
        !(Bundle.main.object(forInfoDictionaryKey: "AppsOnAirDisableBadgeClearing") as? Bool ?? false)
    }()

    /// The running badge total the SDK is tracking (as last written to the App Group).
    /// Falls back to the live icon badge number when no App Group is configured.
    public static var badgeCount: Int {
        if let groupId = shared._appGroupId, let g = UserDefaults(suiteName: groupId) {
            return g.integer(forKey: badgeCountKey)
        }
        return UIApplication.shared.applicationIconBadgeNumber
    }

    /// Set the badge count shown on the app icon, and sync the shared running total.
    ///
    /// - Parameter count: The number to display. Pass `0` to hide the badge.
    ///
    /// Uses `UNUserNotificationCenter.setBadgeCount(_:)` on iOS 16+ and the deprecated
    /// `UIApplication.applicationIconBadgeNumber` on iOS 15. Requires notification
    /// permission; if denied, the system ignores the call.
    public static func setBadgeCount(_ count: Int) {
        let clamped = max(0, count)
        applyIconBadge(clamped)
        writeSharedBadgeCount(clamped)
        log("Badge count set to \(clamped).", level: .debug)
    }

    /// Add `delta` (may be negative) to the current badge count. Clamped at 0.
    @discardableResult
    public static func incrementBadgeCount(by delta: Int) -> Int {
        let next = max(0, badgeCount + delta)
        setBadgeCount(next)
        return next
    }

    /// Clear the app icon badge and the shared running total. Shortcut for `setBadgeCount(0)`.
    public static func clearBadgeCount() {
        setBadgeCount(0)
    }

    /// Called on cold launch and on every foreground. No-op unless
    /// `autoClearBadgeOnForeground` is set.
    internal static func clearBadgeOnForegroundIfEnabled() {
        guard autoClearBadgeOnForeground else { return }
        // Only touch things if there is actually a badge to clear.
        guard badgeCount != 0 || UIApplication.shared.applicationIconBadgeNumber != 0 else { return }
        applyIconBadge(0)
        writeSharedBadgeCount(0)
        log("Badge cleared on foreground.", level: .debug)
    }

    private static func applyIconBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error {
                    AppPushService.log("setBadgeCount failed: \(error.localizedDescription)", level: .error)
                }
            }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
        }
    }

    private static func writeSharedBadgeCount(_ count: Int) {
        guard let groupId = shared._appGroupId,
              let groupDefaults = UserDefaults(suiteName: groupId) else { return }
        groupDefaults.set(count, forKey: badgeCountKey)
    }

    // MARK: - APNs callback handlers
    // Called automatically by swizzler, or manually if swizzle: false.

    public static func handleAPNsToken(_ deviceToken: Data) {
        guard !deviceToken.isEmpty else {
            emitError(code: .apnsRegistrationFailed, message: "Received empty APNs token. Try re-running the app.")
            return
        }
        // AOA: Convert raw Data to hex string — this is the token sent to backend/Postman
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        // AOA: Read environment from entitlements — sandbox (debug) or production (App Store)
        let env = apnsEnvironment
        log("APNs token received. environment=\(env.rawValue) token=\(hex.prefix(12))…", level: .debug)

        // Compare against the token we had before overwriting it — a non-empty
        // previous value that differs means APNs rotated the token.
        let previousToken = shared.storage.getApnsToken()
        let didRotate = (previousToken.map { !$0.isEmpty && $0 != hex }) ?? false

        shared.storage.saveApnsToken(hex)
        shared.didReportEntitlementError = false   // a token means the entitlement is fine
        firePushSubscriptionChange()

        // The push token is what initialize()'s registration was waiting on —
        // nudge the one-shot device registration now that it exists. No-ops if
        // already registered this launch.
        registerSubscriptionIfReady(reason: .apnsToken)

        // If the token rotated after this device was already registered, push the
        // new token to the backend with PATCH /v1/subscriptions/<id>. No-ops when
        // there is no subscriptionId yet — the POST above carries the new token.
        if didRotate {
            log("APNs token rotated — updating existing subscription.", level: .debug)
            updatePushTokenIfRotated(reason: .apnsTokenRotated)
        }

        shared.listener?.onAPNsTokenUpdated(token: hex, environment: env)
    }

    public static func handleAPNsRegistrationError(_ error: Error) {
        let nsError = error as NSError
        let reason: String
        switch nsError.code {
        case 3000:
            // Now that registration is attempted on every cold launch, only surface
            // this permanent config error once per process to avoid spamming onError.
            if shared.didReportEntitlementError { return }
            shared.didReportEntitlementError = true
            reason = "Push entitlement is missing. Enable Push Notifications in Xcode → Signing & Capabilities."
        case 3010: reason = "Push is not supported on this device or simulator."
        default:   reason = error.localizedDescription
        }
        emitError(code: .apnsRegistrationFailed, message: "APNs registration failed: \(reason)")
    }

    public static func handleWillPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        let push = PushNotification.from(notification.request.content)
        registerActionCategoryIfNeeded(for: notification.request.content)
        let event = NotificationWillDisplayEvent(notification: push)
        // Fire all foreground lifecycle listeners — any one can call preventDefault()
        shared.foregroundListeners.forEach { $0.onWillDisplay(event: event) }
        // Also fire legacy listener
        shared.listener?.onNotificationReceived(notification: push)
        checkPermissionChange()

        // Enqueue a local RECEIVED event for tracking purposes.
        // No backend call for free tier — TODO: POST /events/received if BE requests it.
        AppsOnAirEventQueue.shared.enqueue(PushEvent(
            type: .received,
            notificationId: push.id,
            subscriptionId: subscriptionId
        ))

        // If any listener suppressed display, return empty options
        return event.isPreventDefault ? [] : [.banner, .badge, .sound]
    }

    // MARK: - Action buttons (foreground fallback)

    /// `Set<UNNotificationCategory>` isn't `Sendable`; this lets the result of
    /// `getNotificationCategories` cross from its background completion handler into a
    /// `Task { @MainActor in }` without tripping strict-concurrency checks. Safe because
    /// the category set is read-only data handed off once, never mutated concurrently.
    private struct CategoriesBox: @unchecked Sendable {
        let categories: Set<UNNotificationCategory>
    }

    /// One entry of the payload's `actions` array (§9.1) — mirrors the identical private
    /// type in `AppsOnAirNotificationServiceExtension.swift`. The two targets share no
    /// common dependency, so this is intentionally duplicated rather than shared.
    private struct PushActionDefinition {
        let id: String
        let title: String
        let foreground: Bool
        let destructive: Bool
    }

    private static func actionDefinitions(from userInfo: [AnyHashable: Any]) -> [PushActionDefinition] {
        guard let list = userInfo["actions"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String, let title = entry["title"] as? String else { return nil }
            return PushActionDefinition(
                id: id,
                title: title,
                foreground: (entry["foreground"] as? Bool) ?? false,
                destructive: (entry["destructive"] as? Bool) ?? false
            )
        }
    }

    /// Best-effort fallback for payloads that reach the app **without** an NSE having run
    /// (no `mutable-content: 1`, or no Notification Service Extension target configured).
    /// When an NSE *is* configured, it already registered the category and assigned
    /// `content.categoryIdentifier` before this notification was ever handed to iOS — see
    /// `AppPushServiceExtension.registerActionCategory`, the reliable path.
    ///
    /// This path cannot do the same: `UNNotification` here is read-only, so the SDK cannot
    /// assign a category identifier retroactively. It can only register a category under
    /// whatever identifier the backend already put in `aps.category`, synchronously, right
    /// before `willPresent` returns — early enough for the current banner in practice, but
    /// not an Apple-documented guarantee, since there is no public API to force a category
    /// lookup to happen after this point and before the system renders it.
    private static func registerActionCategoryIfNeeded(for content: UNNotificationContent) {
        let userInfo = content.userInfo
        let actions = actionDefinitions(from: userInfo)
        guard !actions.isEmpty else { return }

        guard let apsCategory = (userInfo["aps"] as? [AnyHashable: Any])?["category"] as? String,
              !apsCategory.isEmpty else {
            log("'actions' present but 'aps.category' is missing on a foreground notification " +
                "with no NSE to assign one — action buttons will not render. Either set " +
                "aps.category, or add a Notification Service Extension (AppsOnAirPushServiceExt) " +
                "which can assign one automatically.", level: .warn)
            return
        }

        // Already registered from an earlier notification with this same category — skip
        // the redundant setNotificationCategories call.
        if shared.knownNotificationCategories.contains(where: { $0.identifier == apsCategory }) {
            return
        }

        let unActions = actions.map { def -> UNNotificationAction in
            var options: UNNotificationActionOptions = []
            if def.foreground { options.insert(.foreground) }
            if def.destructive { options.insert(.destructive) }
            return UNNotificationAction(identifier: def.id, title: def.title, options: options)
        }
        let category = UNNotificationCategory(
            identifier: apsCategory, actions: unActions, intentIdentifiers: [], options: []
        )

        shared.knownNotificationCategories = shared.knownNotificationCategories
            .filter { $0.identifier != apsCategory }
        shared.knownNotificationCategories.insert(category)
        UNUserNotificationCenter.current().setNotificationCategories(shared.knownNotificationCategories)
        log("Registered action category '\(apsCategory)' with \(actions.count) button(s).", level: .debug)
    }

    public static func handleDidReceive(response: UNNotificationResponse) {
        let push = PushNotification.from(response.notification.request.content)
        // UNNotificationDefaultActionIdentifier means body tap (not a custom action button)
        let actionId: String? = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? nil
            : response.actionIdentifier
        let clickEvent = NotificationClickEvent(
            notification: push,
            result: NotificationClickResult(actionId: actionId, url: push.launchUrl)
        )
        shared.clickListeners.forEach { $0.onClick(event: clickEvent) }
        // Also fire legacy listener
        shared.listener?.onNotificationOpened(notification: push)

        // Badge upkeep. When the host app has NOT disabled foreground clearing, the
        // didBecomeActive observer zeroes the badge on open and there is nothing to do
        // here. When clearing IS disabled (autoClearBadgeOnForeground == false /
        // AppsOnAirDisableBadgeClearing == true), the SDK instead counts the badge down
        // by 1 for every notification the user acts on — body tap or action button —
        // keeping the icon in step with the notifications the user has cleared.
        if !autoClearBadgeOnForeground {
            let remaining = incrementBadgeCount(by: -1)
            log("Notification opened — running badge total decremented to \(remaining).", level: .debug)
        }

        // Enqueue click/open event — sent to backend on next flush.
        // TODO: API — POST /events/opened or /events/clicked (see AppsOnAirEventQueue)
        AppsOnAirEventQueue.shared.enqueue(PushEvent(
            type: actionId == nil ? .opened : .clicked,
            notificationId: push.id,
            subscriptionId: subscriptionId,
            actionId: actionId
        ))
        log(
            "Notification \(actionId == nil ? "opened" : "clicked (action: \(actionId!))")." +
            " notifId=\(push.id ?? "nil") subscriptionId=\(subscriptionId ?? "nil")" +
            " [TODO] POST /events/\(actionId == nil ? "opened" : "clicked")",
            level: .info
        )
    }

    // MARK: - Silent Push

    /// Called when a silent push (content-available: 1) arrives.
    /// Perform lightweight background work and call completion when done.
    public static var onSilentPushReceived: ((_ userInfo: [AnyHashable: Any], _ completion: @escaping (UIBackgroundFetchResult) -> Void) -> Void)?

    public static func handleSilentPush(
        _ userInfo: [AnyHashable: Any],
        fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        log("Silent push received.", level: .debug)
        if let handler = onSilentPushReceived {
            handler(userInfo, completion)
        } else {
            completion(.noData)
        }
    }

    // MARK: - Permission change detection

    /// Re-read the OS notification settings into `cachedAuthorizationStatus`,
    /// firing permission observers when the granted state changes.
    /// - Parameter completion: run on the main actor once the cache is updated.
    internal static func refreshPermissionCache(completion: (@MainActor @Sendable () -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // Pull the Sendable enum out here — UNNotificationSettings is not Sendable
            // and must not cross the actor hop.
            let status = settings.authorizationStatus
            Task { @MainActor in
                shared.cachedAuthorizationStatus = status
                let granted = NotificationPermission(status).isGranted
                if let previous = shared.previousPermission, previous != granted {
                    shared.permissionObservers.forEach { $0.onNotificationPermissionDidChange(granted) }
                    // Notify local push-subscription observers of the new `enabled`
                    // state, then push that state to the backend with
                    // PATCH /v1/subscriptions/<id> — same connectivity-gated flow
                    // as registerSubscriptionIfReady().
                    firePushSubscriptionChange()
                    updateSubscriptionEnabledIfReady(reason: .permissionChanged(granted: granted))
                }
                shared.previousPermission = granted
                completion?()
            }
        }
    }

    /// Legacy internal entry point kept for the swizzler / AppDelegate handlers.
    internal static func checkPermissionChange() {
        refreshPermissionCache()
    }

    // MARK: - Internal helpers

    /// Resolve the App Group ID from the project the same way OneSignal does, in priority order:
    ///   1. `AppsOnAirAppGroup` String in the app's Info.plist.
    ///   2. Convention: `group.<main-app-bundle-id>.appsonair`.
    ///
    /// Both steps mirror `AppsOnAirNotificationServiceExtension.resolveAppGroupId()`
    /// (which derives the same host bundle id by dropping the NSE's last path segment),
    /// so the app and the extension land on the same suite name with zero extra config.
    /// Returns `nil` only when there is no bundle identifier to build a convention from.
    internal static func resolveAppGroupId() -> String? {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "AppsOnAirAppGroup") as? String,
           !plist.isEmpty {
            return plist
        }
        if let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty {
            return "group.\(bundleId).appsonair"
        }
        return nil
    }

    // Internal so PushAppDelegateSwizzler can log through the same channel
    internal static func log(_ message: String, level: LogLevel = .debug) {
        guard level <= AppPushService.Debug.logLevel else { return }
        print("[AppPushService] [\(level)] \(message)")
    }

    private static func emitError(code: PushError.Code, message: String) {
        log("Error — \(message)", level: .error)
        shared.listener?.onError(PushError(code: code, message: message))
    }
}
