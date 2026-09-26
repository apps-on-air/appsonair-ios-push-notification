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
    // Current open session, per the Session Tracking API contract.
    var sessionId: String? {
        UserDefaultsService.get(key: "com.appsonair.push.sessionId")
    }

    func saveSession(id: String) {
        UserDefaultsService.save(key: "com.appsonair.push.sessionId", value: id)
    }

    func clearSession() {
        UserDefaultsService.delete(key: "com.appsonair.push.sessionId")
    }

    // MARK: - Registration Required Flag
    // Defaults to true on a fresh install (key absent in UserDefaults).
    // Flipped to false after the first successful POST /v1/subscriptions (HTTP 2xx).
    // Persists for the lifetime of the installation; reset to true only on
    // uninstall/reinstall (UserDefaults is cleared by the OS on uninstall).
    var isRegistrationRequired: Bool {
        guard UserDefaults.standard.object(forKey: "com.appsonair.push.isRegistrationRequired") != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: "com.appsonair.push.isRegistrationRequired")
    }

    func markRegistrationComplete() {
        UserDefaults.standard.set(false, forKey: "com.appsonair.push.isRegistrationRequired")
    }

    /// Reset to true after a successful logout (DELETE /v1/subscriptions 2xx) so the
    /// subsequent re-registration POST correctly reports `is_registration_required: true`.
    func resetRegistrationRequired() {
        UserDefaults.standard.removeObject(forKey: "com.appsonair.push.isRegistrationRequired")
    }
}
