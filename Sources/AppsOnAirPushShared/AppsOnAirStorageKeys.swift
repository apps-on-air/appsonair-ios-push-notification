// MARK: - AppsOnAirStorageKeys
//
// UserDefaults keys that are written and read across the main app ↔ NSE
// process boundary via App Group UserDefaults (`UserDefaults(suiteName:)`).
//
// Both the `AppsOnAir-AppPush` and `AppsOnAir-AppPush-ServiceExt` targets
// depend on this shared target so that a key rename is caught at compile time
// in both processes rather than becoming a silent runtime mismatch.

public enum AppsOnAirStorageKeys {
    public enum AppGroup {
        /// App ID written by the main app on initialize(); read by the NSE
        /// to authenticate delivery-receipt POSTs.
        public static let appId          = "com.appsonair.push.appId"

        /// Keychain-backed device ID cached in App Group so the NSE can
        /// include it in delivery receipts without Keychain access.
        public static let deviceId       = "com.appsonair.push.deviceIdCache"

        /// Backend subscription ID written by the main app after POST /v1/subscriptions;
        /// read by the NSE for delivery-receipt payloads.
        public static let subscriptionId = "com.appsonair.push.subscriptionId"

        /// The resolved App Group identifier itself, stored for diagnostic reads.
        public static let appGroupId     = "com.appsonair.push.appGroupId"

        /// Delivery-receipt queue written by the NSE and drained by the main
        /// app on next foreground via `AppsOnAirEventQueue.drainSharedExtensionQueue()`.
        public static let nseEventQueue  = "com.appsonair.push.nseEventQueue"

        /// Running badge total written by the NSE (`badge_increment` payloads)
        /// and read/reset by the main app on foreground.
        public static let badgeCount     = "com.appsonair.push.badgeCount"
    }
}
