import AppsOnAir_Core
import Foundation
import UIKit

// MARK: - AppsOnAirDeviceInfo
//
// Collects device and app metadata for the subscription registration payload.
// Device/app facts are sourced from AppsOnAir_Core (AppsOnAirCoreServices) so the
// whole SDK family reports identical values; Push-only facts (jailbreak heuristic,
// opt-out, test-device, APNs environment) are added here.
//
// Scope §3.1 — Subscription owns:
//   app version, SDK version, device model/OS, permission status, rooted flag, test-device flag.
//
// AppsOnAir_Core.getDeviceInfo(_:completion:) is ASYNCHRONOUS, so prime() fetches
// the snapshot once during AppPushService.initialize() and registrationPayload()
// reads it synchronously. Before the first fetch returns, registrationPayload()
// falls back to reading Bundle / UIDevice directly.
//
// The full registration payload is assembled by registrationPayload() and logged with a TODO marker.
// When the BE API is ready, POST this payload to /subscriptions on:
//   1. configure() + first APNs token receipt  → new subscription (subscription_id = null)
//   2. APNs token refresh                      → update existing subscription
//   3. Session start                            → update last_session, session_count, app_version, etc.

@MainActor
enum AppsOnAirDeviceInfo {

    // MARK: - Static fields

    /// CocoaPods pod name / SPM product name — the key `SdkManager` looks up.
    /// Must match `s.name` in `AppsOnAir-AppPush.podspec`; never any other
    /// AppsOnAir SDK's pod name (e.g. `AppsOnAir-Core`).
    private static let sdkName = "AppsOnAir-AppPush"

    /// Used only when the installed package ships no version metadata (e.g. SPM
    /// added as source with no resource bundle). Keep in sync with
    /// `AppPushService.podspec` `s.version` on every release.
    private static let fallbackSDKVersion = "0.0.4-alpha"

    /// SDK version, resolved at runtime from the installed package rather than
    /// hard-coded here:
    ///   • CocoaPods — `CFBundleShortVersionString` of the `AppsOnAir-AppPush` pod
    ///     framework (`org.cocoapods.AppsOnAir-AppPush`), i.e. the `.podspec` version.
    ///   • SPM — the SDK bundle's `CFBundleShortVersionString` when the package is
    ///     consumed as a framework / xcframework.
    /// Delegated to AppsOnAir_Core's `SdkManager`, which walks the same bundle
    /// lookups it uses for its own version. Falls back to `fallbackSDKVersion`
    /// when no version metadata is present.
    static let sdkVersion: String = {
        let resolved = SdkManager.shared.getVersion(for: sdkName)
        return (resolved.isEmpty || resolved == "-") ? fallbackSDKVersion : resolved
    }()

    // MARK: - AppsOnAir_Core bridge

    /// Sendable snapshot of the fields we lift out of Core's nested result dict.
    private struct Snapshot: Sendable {
        var appVersion       = ""   // appInfo["releaseVersionNumber"]  (CFBundleShortVersionString)
        var buildNumber      = 0    // appInfo["buildVersionNumber"]    (CFBundleVersion, parsed to Int)
        var deviceModel      = ""   // deviceInfo["deviceModel"]        (marketing name, e.g. "iPhone 15 Pro")
        var osVersion        = ""   // deviceInfo["deviceOsVersion"]
        var timezone         = ""   // deviceInfo["timezone"]
        var regionCode       = ""   // deviceInfo["deviceRegionCode"]
        var isSimulator      = false // deviceInfo["isSimulator"]
        var firstInstallTime = ""   // deviceInfo["firstInstallTime"]   ("dd-MMM-yyyy hh:mm:ss a")
        var primed           = false
    }

    private static var snapshot = Snapshot()

    /// Fetch the device/app metadata snapshot from AppsOnAir_Core.
    /// Call once from AppPushService.initialize(); safe to call again to refresh.
    ///
    /// Note: Core's getDeviceInfo() sets `UIDevice.current.isBatteryMonitoringEnabled = true`
    /// as a side effect and delivers its completion on the main queue.
    static func prime() {
        AppPushService.shared.core.getDeviceInfo { result in
            let device = result["deviceInfo"] as? [String: Any] ?? [:]
            let app    = result["appInfo"]    as? [String: Any] ?? [:]

            var snap = Snapshot()
            snap.appVersion       = app["releaseVersionNumber"] as? String ?? ""
            snap.buildNumber      = parseBuildNumber(app["buildVersionNumber"] as? String ?? "")
            snap.deviceModel      = device["deviceModel"] as? String ?? ""
            snap.osVersion        = device["deviceOsVersion"] as? String ?? ""
            snap.timezone         = device["timezone"] as? String ?? ""
            snap.regionCode       = device["deviceRegionCode"] as? String ?? ""
            snap.isSimulator      = device["isSimulator"] as? Bool ?? false
            snap.firstInstallTime = device["firstInstallTime"] as? String ?? ""
            snap.primed           = true

            Task { @MainActor in
                snapshot = snap
                AppPushService.log("DeviceInfo: AppsOnAir_Core metadata primed.", level: .verbose)
            }
        }
    }

    /// CFBundleVersion may legally hold up to three dot-separated integers ("1.0.3"),
    /// so fall back to the leading component, then to 0.
    nonisolated static func parseBuildNumber(_ raw: String) -> Int {
        if let exact = Int(raw) { return exact }
        guard let leading = raw.split(separator: ".").first else { return 0 }
        return Int(leading) ?? 0
    }

    /// Numeric build number for the registration payload. Prefers Core's value,
    /// falls back to a direct CFBundleVersion read before prime() completes.
    static var buildNumber: Int {
        if snapshot.primed { return snapshot.buildNumber }
        return parseBuildNumber(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
    }

    /// Cached result of `computeIsJailbroken()`, filled in by `primeJailbreakCheck()`.
    /// Defaults to `false` (untampered) until that completes.
    private static var cachedIsJailbroken = false

    /// Run the jailbreak heuristic off the main thread and cache the result for
    /// `isJailbroken` to read synchronously. Call once from
    /// `AppPushService.initialize()`, alongside `prime()`.
    ///
    /// The check includes writing a probe file to `/private/…` — outside the
    /// app's sandbox — and catching the expected failure. On a real device that
    /// sandbox violation is logged by the OS and, with a debugger attached, can
    /// visibly stall the thread it runs on for a second or more. Running it
    /// synchronously on the main actor during `subscriptionBody()` (i.e. at
    /// launch, exactly when the app is also showing the permission prompt) is
    /// what produced the "app freezes for a couple seconds at launch" symptom —
    /// hence computing it off-thread here instead.
    static func primeJailbreakCheck() {
        #if targetEnvironment(simulator)
        // isJailbroken already reads false unconditionally on simulator.
        #else
        Task.detached(priority: .utility) {
            let result = computeIsJailbroken()
            await MainActor.run { AppsOnAirDeviceInfo.cachedIsJailbroken = result }
        }
        #endif
    }

    /// Heuristic jailbreak check — NOT a security guarantee. Used for segmentation only.
    /// Returns false on simulator always, and false on device until
    /// `primeJailbreakCheck()`'s background check completes. (Push-owned — Core
    /// does not provide this.)
    static var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        cachedIsJailbroken
        #endif
    }

    /// The actual filesystem heuristic — moved out of `isJailbroken` so it can run
    /// off the main actor. Not annotated `@MainActor`-isolated (the enclosing type
    /// is, but this body touches no UIKit / main-actor state), so `Task.detached`
    /// can call it from a background thread.
    nonisolated private static func computeIsJailbroken() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
            "/private/var/lib/apt/"
        ]
        if paths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        // Sandbox escape check: write outside app sandbox — fails on stock iOS
        let probe = "/private/jailbreak_\(UUID().uuidString)"
        do {
            try "x".write(toFile: probe, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: probe)
            return true
        } catch { return false }
    }

    // MARK: - Core device metadata

    /// Typed view over `AppsOnAirCoreServices.getDeviceMetadata()` — the static,
    /// synchronous device/app snapshot Core exposes for the Push SDK. Every field
    /// the `/v1/subscriptions` body needs is pulled out of the `[String: Any]`
    /// dictionary here, once, so callers read named values instead of string keys.
    struct CoreMetadata: Sendable {
        /// CFBundleShortVersionString, e.g. "1.2.3".            Core key: `appVersion`
        let appVersion: String
        /// CFBundleVersion parsed to Int, e.g. 42.              Core key: `buildVersionNumber`
        let buildNumber: Int
        /// Marketing name, e.g. "iPhone 15 Pro".               Core key: `deviceModel`
        let deviceModel: String
        /// Raw `uname` identifier, e.g. "iPhone16,1".          Core key: `rawDeviceModel`
        let rawDeviceModel: String
        /// OS version, e.g. "17.2".                            Core key: `osVersion`
        let osVersion: String
        /// OS name, e.g. "iOS" / "iPadOS".                     Core key: `platform`
        let platform: String
        /// IANA zone, e.g. "Asia/Kolkata".                     Core key: `timezone`
        let timezone: String
        /// ISO region, e.g. "IN".                              Core key: `regionCode`
        let regionCode: String
        /// ISO 639-1 language, e.g. "en".                      Core key: `language`
        let language: String
        /// Full locale, e.g. "en_IN".                          Core key: `locale`
        let locale: String
        /// Hardware vendor — always "Apple".                   Core key: `manufacturer`
        let manufacturer: String
        /// Running on a simulator.                             Core key: `isSimulator`
        let isSimulator: Bool
        /// First install timestamp, Core's formatted string.   Core key: `firstInstallTime`
        let firstInstallTime: String

        fileprivate init(_ m: [String: Any]) {
            appVersion       = m["appVersion"]        as? String ?? ""
            buildNumber      = AppsOnAirDeviceInfo.parseBuildNumber(m["buildVersionNumber"] as? String ?? "")
            deviceModel      = m["deviceModel"]       as? String ?? ""
            rawDeviceModel   = m["rawDeviceModel"]    as? String ?? ""
            osVersion        = m["osVersion"]         as? String ?? ""
            platform         = m["platform"]          as? String ?? "iOS"
            timezone         = m["timezone"]          as? String ?? TimeZone.current.identifier
            regionCode       = m["regionCode"]        as? String ?? ""
            language         = m["language"]          as? String ?? ""
            locale           = m["locale"]            as? String ?? ""
            manufacturer     = m["manufacturer"]      as? String ?? "Apple"
            isSimulator      = m["isSimulator"]       as? Bool   ?? false
            firstInstallTime = m["firstInstallTime"]  as? String ?? ""
        }
    }

    /// Snapshot of `AppsOnAirCoreServices.getDeviceMetadata()` as typed fields.
    /// Call on the main thread — `getDeviceMetadata()` reads UIKit singletons.
    static func coreMetadata() -> CoreMetadata {
        CoreMetadata(AppsOnAirCoreServices.getDeviceMetadata())
    }

    // MARK: - Registration payload

    /// Full subscription registration payload.
    ///
    /// TODO: API — POST /subscriptions
    /// When to call:
    ///   1. After configure() + handleAPNsToken() fires (new/refreshed subscription)
    ///   2. On session start (subscription update)
    ///
    /// Endpoint:  POST <base_url>/subscriptions
    /// Headers:
    ///   Authorization: Bearer <sdk_api_key>
    ///   Content-Type:  application/json
    /// Body:
    /// {
    ///   "app_id":           "<configured appId>",
    ///   "device_id":        AppPushService.deviceId,   // AppsOnAir_Core per-install device id (AppsOnAirCoreServices.deviceId)
    ///   "subscription_id":  AppPushService.subscriptionId,   // null on first registration
    ///   "apns_token":       AppPushService.storage.getApnsToken(),
    ///   "apns_environment": AppPushService.apnsEnvironment.rawValue,
    ///   "sdk_version":      "1.0.0",
    ///   "app_version":      "1.2.3",        // Core appInfo["releaseVersionNumber"]
    ///   "build_number":     42,             // Core appInfo["buildVersionNumber"], parsed to Int
    ///   "device_model":     "iPhone 15 Pro",   // Core deviceInfo["deviceModel"] (marketing name)
    ///   "os_type":          "ios",
    ///   "os_version":       "17.2",         // Core deviceInfo["deviceOsVersion"]
    ///   "timezone":         "America/New_York",   // Core deviceInfo["timezone"]
    ///   "language":         "en",           // Push (AppsOnAirUser override), not Core
    ///   "region_code":      "US",           // Core deviceInfo["deviceRegionCode"]
    ///   "is_simulator":     false,          // Core deviceInfo["isSimulator"]
    ///   "first_install_time": "03-Sep-2025 10:45:30 AM",   // Core deviceInfo["firstInstallTime"]
    ///   "is_opted_out":     false,
    ///   "is_rooted":        false,
    ///   "is_test_device":   false
    /// }
    /// Response: { "subscription_id": "<BE-generated UUID>" }
    ///   → call AppPushService.setSubscriptionId(response["subscription_id"])
    static func registrationPayload() -> [String: Any] {
        let s = snapshot
        let payload: [String: Any] = [
            "sdk_version":       sdkVersion,
            "app_version":       s.primed ? s.appVersion
                                          : (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
            "build_number":      buildNumber,
            "device_model":      s.primed ? s.deviceModel : UIDevice.current.model,
            "os_type":           "ios",
            "os_version":        s.primed ? s.osVersion : UIDevice.current.systemVersion,
            "timezone":          s.primed ? s.timezone : TimeZone.current.identifier,
            "device_id":         AppPushService.deviceId,
            "language":          AppPushService.shared.language,
            "region_code":       s.regionCode,
            "is_simulator":      s.isSimulator,
            "first_install_time": s.firstInstallTime,
            "is_opted_out":      AppPushService.shared.isOptedOut,
            "is_rooted":         isJailbroken,
            "is_test_device":    AppPushService.isTestDevice,
            "apns_environment":  AppPushService.apnsEnvironment.rawValue
        ]

        if !s.primed {
            AppPushService.log("DeviceInfo: payload assembled before AppsOnAir_Core primed — using Bundle/UIDevice fallbacks.", level: .warn)
        }
        AppPushService.log("DeviceInfo: registration payload assembled.", level: .verbose)
        return payload
    }
}
