@_spi(AppsOnAirInternal) import AppsOnAir_Core
import Foundation

// MARK: - PushStorage
//
// Thin wrapper over `UserDefaultsService` (AppsOnAir_Core) for the Push SDK's
// locally persisted values. Using the Core helper keeps storage centralised and
// consistent across the SDK family.
//
// NOTE: Keys shared with the Notification Service Extension (e.g. subscriptionId,
// badgeCount) are written a second time to the App Group `UserDefaults(suiteName:)`
// inside `AppPushService.initialize` and `AppPushServiceExtension` respectively —
// `UserDefaultsService` (standard suite) is used only for the main-app process.
//
// The per-install device identifier is NOT stored here — it comes from
// AppsOnAir_Core (`AppsOnAirCoreServices.deviceId`) so the whole SDK family
// reports the same value.

final class PushStorage {

    // MARK: - APNs token

    func getApnsToken() -> String? {
        UserDefaultsService.get(key: "com.appsonair.push.apnsToken")
    }

    func saveApnsToken(_ token: String) {
        UserDefaultsService.save(key: "com.appsonair.push.apnsToken", value: token)
    }

    // MARK: - Subscription ID
    // Backend-assigned subscription ID. Nil until the host app calls POST /subscriptions
    // and passes the response to AppPushService.setSubscriptionId(_:).
    // Stored in UserDefaults (not Keychain) — can be re-issued by the backend on re-registration.
    var subscriptionId: String? {
        UserDefaultsService.get(key: "com.appsonair.push.subscriptionId")
    }

    func saveSubscriptionId(_ id: String) {
        UserDefaultsService.save(key: "com.appsonair.push.subscriptionId", value: id)
    }

    /// Drop the locally cached subscriptionId — used after the backend
    /// subscription record itself has been deleted (logout), so a stale id
    /// isn't reused by a later request.
    func clearSubscriptionId() {
        UserDefaultsService.delete(key: "com.appsonair.push.subscriptionId")
    }

    // MARK: - Session
    // Current open session, per the Session Tracking API contract. `sessionId` and
    // `sessionStartedAt` are always written together (saveSession) and cleared
    // together (clearSession) — a close needs both to match its start, so they
    // must never disagree about which session they describe.
    var sessionId: String? {
        UserDefaultsService.get(key: "com.appsonair.push.sessionId")
    }

    /// Server-clock epoch seconds the current session started — echoed back
    /// verbatim on End Session, so it is stored exactly as the backend sent it.
    var sessionStartedAt: TimeInterval? {
        UserDefaultsService.get(key: "com.appsonair.push.sessionStartedAt").flatMap(TimeInterval.init)
    }

    func saveSession(id: String, startedAt: TimeInterval) {
        UserDefaultsService.save(key: "com.appsonair.push.sessionId", value: id)
        UserDefaultsService.save(key: "com.appsonair.push.sessionStartedAt", value: String(startedAt))
    }

    func clearSession() {
        UserDefaultsService.delete(key: "com.appsonair.push.sessionId")
        UserDefaultsService.delete(key: "com.appsonair.push.sessionStartedAt")
    }
}
