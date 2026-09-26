import Foundation

// MARK: - AOAPushUser

/// ObjC-compatible facade for AppPushService.User.
@objc(AOAPushUser)
public final class AOAPushUser: NSObject {

    private override init() {}

    // MARK: - Identity

    /// The AppsOnAir-assigned device ID.
    @objc @MainActor
    public static var appsOnAirId: String {
        AppPushService.User.appsOnAirId
    }

    /// The external user ID linked via login(). Nil when anonymous.
    @objc @MainActor
    public static var externalId: String? {
        AppPushService.User.externalId
    }

    // MARK: - Push Subscription

    /// The AppsOnAir subscription ID for this device. Nil until assigned by the backend.
    @objc @MainActor
    public static var pushSubscriptionId: String? {
        AppPushService.User.pushSubscription.id
    }

    /// The current APNs device token (hex string). Nil until APNs registers.
    @objc @MainActor
    public static var pushSubscriptionToken: String? {
        AppPushService.User.pushSubscription.token
    }

    /// Whether the user is opted in to push notifications.
    @objc @MainActor
    public static var pushSubscriptionOptedIn: Bool {
        AppPushService.User.pushSubscription.optedIn
    }

    /// Opt in to push notifications (reverses a previous optOut call).
    @objc @MainActor
    public static func optIn() {
        AppPushService.User.pushSubscription.optIn()
    }

    /// Opt out of push notifications without revoking OS permission.
    @objc @MainActor
    public static func optOut() {
        AppPushService.User.pushSubscription.optOut()
    }

    // MARK: - Tags

    /// Set a single tag for audience segmentation.
    @objc @MainActor
    public static func addTag(key: String, value: String) {
        AppPushService.User.addTag(key: key, value: value)
    }

    /// Set multiple tags at once.
    @objc @MainActor
    public static func addTags(_ tags: [String: String]) {
        AppPushService.User.addTags(tags)
    }

    /// Remove a tag by key.
    @objc @MainActor
    public static func removeTag(_ key: String) {
        AppPushService.User.removeTag(key)
    }

    /// Remove multiple tags by key.
    @objc @MainActor
    public static func removeTags(_ keys: [String]) {
        AppPushService.User.removeTags(keys)
    }

    /// Returns a copy of all locally cached tags (synchronous).
    @objc @MainActor
    public static func getTags() -> [String: String] {
        AppPushService.User.getTags()
    }

    /// Fetch tags from the backend and deliver the refreshed result to `completion`
    /// on the main thread. Use this when you need the server-authoritative tag set.
    @objc
    public static func fetchTagsFromBackend(completion: @escaping @Sendable ([String: String]) -> Void) {
        Task { @MainActor in
            AppPushService.User.getTags { @MainActor tags in
                completion(tags)
            }
        }
    }

    // MARK: - Language

    /// Override the detected device language. Use ISO 639-1 codes (e.g. "en", "fr").
    @objc @MainActor
    public static func setLanguage(_ code: String) {
        AppPushService.User.setLanguage(code)
    }

    /// The current language code sent to the backend.
    @objc @MainActor
    public static var language: String {
        AppPushService.User.language
    }

    // MARK: - Aliases

    /// Add a single alias (e.g. your CRM ID).
    @objc @MainActor
    public static func addAlias(label: String, id: String) {
        AppPushService.User.addAlias(label: label, id: id)
    }

    /// Add multiple aliases at once.
    @objc @MainActor
    public static func addAliases(_ aliases: [String: String]) {
        AppPushService.User.addAliases(aliases)
    }

    /// Remove an alias by label.
    @objc @MainActor
    public static func removeAlias(_ label: String) {
        AppPushService.User.removeAlias(label)
    }

    /// Remove multiple aliases by label.
    @objc @MainActor
    public static func removeAliases(_ labels: [String]) {
        AppPushService.User.removeAliases(labels)
    }

    /// Returns a copy of all locally cached aliases (synchronous).
    @objc @MainActor
    public static func getAliases() -> [String: String] {
        AppPushService.User.getAliases()
    }

    /// Fetch aliases from the backend and deliver the refreshed result to `completion`
    /// on the main thread. Use this when you need the server-authoritative alias set.
    @objc
    public static func fetchAliasesFromBackend(completion: @escaping @Sendable ([String: String]) -> Void) {
        Task { @MainActor in
            AppPushService.User.getAliases { @MainActor aliases in
                completion(aliases)
            }
        }
    }

    // MARK: - Email

    /// Associate an email address with this user.
    @objc @MainActor
    public static func addEmail(_ address: String) {
        AppPushService.User.addEmail(address)
    }

    /// Remove an email address association.
    @objc @MainActor
    public static func removeEmail(_ address: String) {
        AppPushService.User.removeEmail(address)
    }

    // MARK: - Push Subscription Observer

    /// Add a push subscription state observer.
    @objc @MainActor
    public static func addPushSubscriptionObserver(_ observer: any AOAPushSubscriptionObserver) {
        let storage = AOABridgeStorage.shared
        if storage.subscriptionAdapters.object(forKey: observer) == nil {
            let bridge = AOASubscriptionObserverBridge(observer)
            storage.subscriptionAdapters.setObject(bridge, forKey: observer)
            AppPushService.User.pushSubscription.addObserver(bridge)
        }
    }

    /// Remove a push subscription state observer.
    @objc @MainActor
    public static func removePushSubscriptionObserver(_ observer: any AOAPushSubscriptionObserver) {
        let storage = AOABridgeStorage.shared
        if let bridge = storage.subscriptionAdapters.object(forKey: observer) {
            AppPushService.User.pushSubscription.removeObserver(bridge)
            storage.subscriptionAdapters.removeObject(forKey: observer)
        }
    }

    // MARK: - User State Observer

    /// Add a user state observer.
    @objc @MainActor
    public static func addUserStateObserver(_ observer: any AOAUserStateObserver) {
        let storage = AOABridgeStorage.shared
        if storage.userStateAdapters.object(forKey: observer) == nil {
            let bridge = AOAUserStateObserverBridge(observer)
            storage.userStateAdapters.setObject(bridge, forKey: observer)
            AppPushService.User.addObserver(bridge)
        }
    }

    /// Remove a user state observer.
    @objc @MainActor
    public static func removeUserStateObserver(_ observer: any AOAUserStateObserver) {
        let storage = AOABridgeStorage.shared
        if let bridge = storage.userStateAdapters.object(forKey: observer) {
            AppPushService.User.removeObserver(bridge)
            storage.userStateAdapters.removeObject(forKey: observer)
        }
    }
}
