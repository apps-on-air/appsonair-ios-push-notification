import Foundation
import UserNotifications

// MARK: - AppsOnAir Notification Service Extension
//
// This is the **single** Notification Service Extension (NSE) surface for the SDK.
// It combines what used to be two separate classes:
//   • rich-media download + title/body overrides, and
//   • delivery-receipt reporting (the "Delivered" analytics metric).
//
// It is available to the host app in two equivalent ways:
//   1. `AppsOnAirNotificationServiceExtension` — an `open` base class to subclass
//      (drop-in, no forwarding code).
//   2. `AppPushServiceExtension` — free functions to call from your own
//      `UNNotificationServiceExtension` subclass, for teams that already have one
//      or need to chain another SDK.
//
// ─────────────────────────────────────────────
// SETUP
// ─────────────────────────────────────────────
//  STEP 1 — File ▸ New ▸ Target ▸ Notification Service Extension (e.g. "NotificationService").
//
//  STEP 2 — Link this library to the NSE target ONLY (never the main app):
//             • SPM:       AppsOnAirPushServiceExt
//             • CocoaPods: pod 'AppPushService/ServiceExtension'
//
//  STEP 3 — Make your NSE class inherit from the base class:
//
//             import AppsOnAirPushServiceExt
//
//             class NotificationService: AppsOnAirNotificationServiceExtension {
//                 // Nothing else required. Optionally override modifyContent(_:request:).
//             }
//
//           …or forward from a hand-rolled subclass:
//
//             class NotificationService: UNNotificationServiceExtension {
//                 override func didReceive(_ request: UNNotificationRequest,
//                     withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
//                     guard let content = request.content.mutableCopy() as? UNMutableNotificationContent
//                     else { return handler(request.content) }
//                     AppPushServiceExtension.didReceiveNotificationExtensionRequest(
//                         request, with: content, withContentHandler: handler)
//                 }
//             }
//
//  STEP 4 — (Delivery receipts only) Add the SAME App Group to the main app AND the
//           NSE target. The SDK reads the group name from the project on both sides —
//           no code, matching OneSignal:
//             • Add to each target's Info.plist (or just rely on the convention below):
//                 <key>AppsOnAirAppGroup</key>
//                 <string>group.com.acme.app.appsonair</string>
//             • If the key is omitted, both sides fall back to the convention
//               `group.<main-app-bundle-id>.appsonair`.
//
//  STEP 5 — The backend MUST set `mutable-content: 1` in every APNs payload, else iOS
//           never invokes the NSE:
//             { "aps": { "mutable-content": 1, "alert": { … } }, "notification_id": "…" }
//
// ─────────────────────────────────────────────
// SUPPORTED DATA-PAYLOAD KEYS  (siblings of `aps`, not inside it)
// ─────────────────────────────────────────────
//  | Key               | Type                       | Meaning                                                           |
//  |-------------------|----------------------------|------------------------------------------------------------------|
//  | notification_id   | String                     | AppsOnAir notification ID. Used for the delivery receipt.        |
//  | title             | String                     | Overrides the banner title (backend sends it pre-translated).    |
//  | body              | String                     | Overrides the banner body (backend sends it pre-translated).     |
//  | subtitle          | String                     | Overrides the banner subtitle.                                   |
//  | sound             | String                     | Sound to play: "default" or a .caf/.aiff filename bundled in the |
//  |                   |                            | app. Overrides aps.sound. Also re-applied from aps.sound when    |
//  |                   |                            | this key is absent (iOS drops it from the mutable copy on some   |
//  |                   |                            | versions). Omit both to play no sound.                           |
//  | image_url         | String (https)             | Single image to attach. Wins over `video_url`.                   |
//  | video_url         | String (https)             | Single video to attach. Used only when `image_url` is absent.    |
//  | attachments       | [String] or [{id,url}]     | Multiple media URLs. Takes precedence over image_url/video_url.  |
//  | badge             | Int                        | Absolute app-icon badge count. `max(0, value)`.                  |
//  | badge_increment   | Int (may be negative)      | Delta applied to the running badge total: `max(0, stored+delta)`.|
//  | actions           | [{id,title,foreground,     | Action buttons. The NSE builds a `UNNotificationCategory` and    |
//  |                   | destructive}]              | registers it before delivery, using `aps.category` as the        |
//  |                   |                            | identifier if present, else one derived from the action ids.     |
//
//  Badge counting needs the App Group (STEP 4). The running total is reset to 0 when the
//  app next enters the foreground. Without an App Group only an absolute `badge` is honoured.
//
//  Only the FIRST attachment is shown in the system banner; the rest are available to
//  a Notification Content Extension. HTTPS is required. Non-media / oversize / wrong
//  MIME downloads are dropped silently — the notification is still delivered.
//
// ─────────────────────────────────────────────
// BEST-EFFORT: if the NSE is misconfigured, times out, or is killed, iOS still shows the
// original notification via serviceExtensionTimeWillExpire(). Never imply *guaranteed*
// delivery in dashboard copy — say "confirmed delivered".
// ─────────────────────────────────────────────

// MARK: - Base class

/// Base class for the host app's Notification Service Extension target.
/// Subclass it and (optionally) override `modifyContent(_:request:)`.
@available(macOS 10.14, *)
open class AppsOnAirNotificationServiceExtension: UNNotificationServiceExtension {

    /// Set by iOS before `didReceive`. Retained so `serviceExtensionTimeWillExpire()` can use it.
    public var contentHandler: ((UNNotificationContent) -> Void)?

    /// Mutable copy of the incoming content — inspect/modify it in `modifyContent(_:request:)`.
    public var bestAttemptContent: UNMutableNotificationContent?

    private var receivedRequest: UNNotificationRequest?

    // MARK: Lifecycle

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.receivedRequest = request
        self.contentHandler = contentHandler

        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = mutable

        // Subclass hook — runs before the SDK's own mutations.
        modifyContent(mutable, request: request)

        // Blocks until the receipt is queued and any attachment is downloaded (or the
        // internal time budget is hit), then calls `contentHandler` exactly once.
        AppPushServiceExtension.didReceiveNotificationExtensionRequest(
            request, with: mutable, withContentHandler: contentHandler
        )
        // Delivery is done. Drop the handler so a late serviceExtensionTimeWillExpire()
        // (should not happen — the internal budget is < 30 s) cannot deliver twice.
        self.contentHandler = nil
    }

    open override func serviceExtensionTimeWillExpire() {
        guard let request = receivedRequest,
              let content = bestAttemptContent,
              let handler = contentHandler else { return }
        let final = AppPushServiceExtension.serviceExtensionTimeWillExpireRequest(request, with: content) ?? content
        handler(final)
        contentHandler = nil
    }

    // MARK: Subclass hook

    /// Override to mutate the notification before the SDK applies `title` / `body` /
    /// `subtitle` overrides and the media attachment. No need to call `super`.
    open func modifyContent(
        _ content: UNMutableNotificationContent,
        request: UNNotificationRequest
    ) {
        // Default: no-op.
    }
}

// MARK: - Free-function surface

/// Free-function entry points for teams that already own their
/// `UNNotificationServiceExtension` subclass and can't change its base class.
/// Behaviour is identical to `AppsOnAirNotificationServiceExtension`.
@available(macOS 10.14, *)
public enum AppPushServiceExtension {

    // MARK: Tunables

    /// Hard cap on time spent inside `didReceiveNotificationExtensionRequest` before we
    /// deliver whatever we have. Kept below the iOS 30 s NSE budget for headroom.
    private static let maxProcessingTime: TimeInterval = 25
    /// Per-attachment network timeout.
    private static let attachmentDownloadTimeout: TimeInterval = 15
    /// Cap on the direct `POST /v1/events/delivered` attempt from the NSE process —
    /// see `sendDeliveryReceiptDirect`. Also bounded by whatever's left of
    /// `maxProcessingTime` by the time delivery-receipt handling runs.
    private static let deliveryReceiptTimeout: TimeInterval = 5
    /// Outer size ceiling for a downloaded attachment. `UNNotificationAttachment` still
    /// enforces Apple's stricter per-type limits (image 10 MB / audio 5 MB / video 50 MB).
    private static let maxAttachmentBytes: Int64 = 50 * 1024 * 1024
    /// Attachments downloaded per notification. Only the first shows in the banner.
    private static let maxAttachmentCount = 3

    // MARK: Entry points

    /// Apply text overrides, queue the delivery receipt, download attachments, then
    /// invoke `contentHandler` exactly once. **Blocks the calling thread** (the NSE's
    /// `didReceive` thread) until done or the time budget expires — matches the
    /// semaphore pattern used by other push SDKs' extension helpers.
    ///
    /// `contentHandler` is always invoked on the calling thread before this function
    /// returns — it never escapes to the download callbacks — so it need not be `Sendable`.
    public static func didReceiveNotificationExtensionRequest(
        _ request: UNNotificationRequest,
        with content: UNMutableNotificationContent,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let deliver = DeliverOnce(contentHandler)
        let userInfo = request.content.userInfo
        // One shared deadline for everything below — the delivery-receipt attempt and
        // the attachment downloads split the same budget instead of each getting their
        // own, so the two together can never exceed maxProcessingTime.
        let deadline = Date().addingTimeInterval(maxProcessingTime)

        applyTextOverrides(to: content, userInfo: userInfo)
        applySound(to: content, userInfo: userInfo)
        applyBadge(to: content, userInfo: userInfo)
        registerActionCategory(to: content, userInfo: userInfo)
        recordDeliveryReceipt(userInfo: userInfo, timeBudget: max(0, deadline.timeIntervalSinceNow))

        let urls = attachmentURLs(from: userInfo)
        guard !urls.isEmpty else {
            deliver(content)
            return
        }

        let group = DispatchGroup()
        let collector = AttachmentCollector()

        for url in urls.prefix(maxAttachmentCount) {
            group.enter()
            downloadAttachment(from: url) { attachment in
                collector.add(attachment)
                group.leave()
            }
        }

        let waiter = DispatchSemaphore(value: 0)
        group.notify(queue: .global()) { waiter.signal() }
        _ = waiter.wait(timeout: .now() + max(1, deadline.timeIntervalSinceNow))

        let built = collector.attachments
        if !built.isEmpty { content.attachments = built }
        deliver(content)
    }

    /// Called from `serviceExtensionTimeWillExpire()`. Re-applies text overrides to the
    /// best-attempt content (attachments are skipped — no time left) and returns it.
    @discardableResult
    public static func serviceExtensionTimeWillExpireRequest(
        _ request: UNNotificationRequest,
        with content: UNMutableNotificationContent?
    ) -> UNNotificationContent? {
        guard let content else { return nil }
        applyTextOverrides(to: content, userInfo: request.content.userInfo)
        applySound(to: content, userInfo: request.content.userInfo)
        applyBadge(to: content, userInfo: request.content.userInfo)
        return content
    }

    // MARK: Text overrides

    private static func applyTextOverrides(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        if let title = userInfo[PayloadKey.title] as? String, !title.isEmpty {
            content.title = title
        }
        if let subtitle = userInfo[PayloadKey.subtitle] as? String, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
        if let body = userInfo[PayloadKey.body] as? String, !body.isEmpty {
            content.body = body
        }
    }

    // MARK: Sound

    /// Re-apply sound explicitly so it is never lost when the NSE modifies content.
    ///
    /// On several iOS versions `UNMutableNotificationContent.sound` is nil in the
    /// mutable copy even when `aps.sound` was set in the payload — iOS does not
    /// reliably forward it through `mutableCopy()`. Calling `contentHandler` with a
    /// nil sound means the notification arrives silently.
    ///
    /// Priority:
    ///   1. Top-level `sound` key (sibling of `aps`) — lets the backend override sound
    ///      per notification, the same pattern as `title` / `body` overrides.
    ///   2. `aps.sound` — the standard APNs location; re-applied explicitly so it
    ///      survives the mutable-copy path regardless of iOS version.
    ///   3. Neither present → leave `content.sound` untouched (stays whatever iOS set).
    private static func applySound(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        // Top-level override wins over aps.sound.
        let topLevel = userInfo[PayloadKey.sound] as? String
        let apsSound = (userInfo["aps"] as? [AnyHashable: Any])?["sound"] as? String
        guard let soundName = topLevel ?? apsSound else { return }

        if soundName == "default" || soundName.isEmpty {
            content.sound = .default
        } else {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        }
    }

    // MARK: Badge

    /// Maintain a running app-icon badge count across notifications — like OneSignal.
    ///
    /// Payload keys (siblings of `aps`):
    ///   • `badge_increment` — Int delta, may be negative. `newCount = max(0, stored + delta)`.
    ///   • `badge`           — Int absolute value. `newCount = max(0, value)`.
    /// `badge_increment` wins when both are present. `aps.badge` is used as a last-resort
    /// absolute value so the counter stays in sync even for non-AppsOnAir payloads.
    ///
    /// The running total lives in the App Group (`SharedKey.badgeCount`); the main app
    /// resets it to 0 when brought to the foreground. Without an App Group only an
    /// absolute value can be honoured — increments are ignored (no place to keep a total).
    private static func applyBadge(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        let increment = intValue(userInfo[PayloadKey.badgeIncrement])
        let apsBadge = intValue((userInfo["aps"] as? [AnyHashable: Any])?["badge"])
        let absolute = intValue(userInfo[PayloadKey.badge]) ?? apsBadge

        guard increment != nil || absolute != nil else { return }  // no badge instruction

        guard let groupId = resolveAppGroupId(),
              let defaults = UserDefaults(suiteName: groupId) else {
            if let absolute { content.badge = NSNumber(value: max(0, absolute)) }
            return
        }

        let current = defaults.integer(forKey: SharedKey.badgeCount)
        let newValue: Int
        if let increment {
            newValue = max(0, current + increment)
        } else {
            newValue = max(0, absolute ?? 0)
        }
        defaults.set(newValue, forKey: SharedKey.badgeCount)
        content.badge = NSNumber(value: newValue)

        NSLog("[AppPushService NSE] Badge count %d → %d (increment=%@, absolute=%@).",
              current, newValue,
              increment.map(String.init) ?? "nil",
              absolute.map(String.init) ?? "nil")
    }

    /// Coerce a JSON value (`Int`, `NSNumber`, numeric `String`) to `Int`.
    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let int as Int:       return int
        case let num as NSNumber:  return num.intValue
        case let str as String:    return Int(str)
        default:                   return nil
        }
    }

    // MARK: Action buttons

    /// One entry of the payload's `actions` array (§9.1). `foreground` / `destructive`
    /// mirror `UNNotificationActionOptions`; `id` becomes the `UNNotificationAction`
    /// identifier so `NotificationClickResult.actionId` matches what the user tapped.
    private struct ActionDefinition {
        let id: String
        let title: String
        let foreground: Bool
        let destructive: Bool
    }

    private static func actionDefinitions(from userInfo: [AnyHashable: Any]) -> [ActionDefinition] {
        guard let list = userInfo[PayloadKey.actions] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["id"] as? String, let title = entry["title"] as? String else { return nil }
            return ActionDefinition(
                id: id,
                title: title,
                foreground: (entry["foreground"] as? Bool) ?? false,
                destructive: (entry["destructive"] as? Bool) ?? false
            )
        }
    }

    /// A stable identifier derived from the action ids, used only when the payload
    /// doesn't already set `aps.category`. Same action set → same identifier, so
    /// re-registering an unchanged category on every notification is a no-op merge.
    private static func syntheticCategoryIdentifier(for actions: [ActionDefinition]) -> String {
        "aoa.actions.\(actions.map(\.id).sorted().joined(separator: "-"))"
    }

    /// Builds a `UNNotificationCategory` from the payload's `actions` array and registers
    /// it with iOS *before* the notification is delivered — this is the reliable path
    /// (unlike the best-effort registration `AppPushService.handleWillPresent` attempts for
    /// non-NSE foreground delivery, this one runs before the system has decided what to
    /// display, since the NSE finishes before `contentHandler` hands content back to iOS).
    ///
    /// If `aps.category` is present it's used as the identifier (so the backend can reuse
    /// a category across notifications, e.g. via a Notification Content Extension). If it's
    /// absent, a synthetic identifier derived from the action ids is assigned to
    /// `content.categoryIdentifier` instead — the NSE can mutate content, so unlike the
    /// foreground path it never needs the backend to invent one.
    private static func registerActionCategory(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        let actions = actionDefinitions(from: userInfo)
        guard !actions.isEmpty else { return }

        let apsCategory = (userInfo["aps"] as? [AnyHashable: Any])?["category"] as? String
        let identifier = (apsCategory?.isEmpty == false ? apsCategory : nil)
            ?? syntheticCategoryIdentifier(for: actions)

        let unActions = actions.map { def -> UNNotificationAction in
            var options: UNNotificationActionOptions = []
            if def.foreground { options.insert(.foreground) }
            if def.destructive { options.insert(.destructive) }
            return UNNotificationAction(identifier: def.id, title: def.title, options: options)
        }
        let category = UNNotificationCategory(
            identifier: identifier, actions: unActions, intentIdentifiers: [], options: []
        )

        // Merge with whatever categories are already registered (host app's own, or ones
        // from earlier notifications) rather than clobbering them. `getNotificationCategories`
        // is a local query against usernoted — no network — so a 1 s ceiling is generous
        // headroom against the NSE's overall 25 s / 30 s budget, not a realistic wait.
        let center = UNUserNotificationCenter.current()
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationCategories { existing in
            var merged = existing.filter { $0.identifier != identifier }
            merged.insert(category)
            center.setNotificationCategories(merged)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)

        content.categoryIdentifier = identifier
    }

    // MARK: Delivery receipt

    /// Report a delivery receipt — tries a direct `POST /v1/events/delivered` from the
    /// NSE process first (near-real-time, matches how OneSignal's NSE fires its
    /// `report_received` confirmation synchronously), and only falls back to queuing in
    /// the App Group — for `AppsOnAirEventQueue.drainSharedExtensionQueue()` to retry on
    /// next app foreground — when the direct attempt can't be made or fails:
    ///   • App Group not resolvable at all → nothing persisted either; there is no
    ///     `appId` / `subscriptionId` source without it (STEP 4 not done).
    ///   • App Group resolvable but `appId` / `subscriptionId` not yet written (e.g. the
    ///     host app has never launched) → queued for later, once they exist.
    ///   • Direct POST attempted but failed (offline, timeout, non-2xx) → queued.
    private static func recordDeliveryReceipt(userInfo: [AnyHashable: Any], timeBudget: TimeInterval) {
        let notificationId = (userInfo[PayloadKey.notificationId] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let sendId = (userInfo[PayloadKey.sendId] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let groupId = resolveAppGroupId(),
              let defaults = UserDefaults(suiteName: groupId) else {
            NSLog("[AppPushService NSE] App Group not resolvable — delivery receipt NOT sent or persisted. " +
                  "Add 'AppsOnAirAppGroup' to the NSE Info.plist (STEP 4).")
            return
        }

        let appId          = defaults.string(forKey: SharedKey.appId).flatMap { $0.isEmpty ? nil : $0 }
        let subscriptionId = defaults.string(forKey: SharedKey.subscriptionId).flatMap { $0.isEmpty ? nil : $0 }
        let deviceId       = defaults.string(forKey: SharedKey.deviceId)

        if let appId, let subscriptionId {
            let sent = sendDeliveryReceiptDirect(
                appId: appId,
                subscriptionId: subscriptionId,
                notificationId: notificationId ?? "",
                sendId: sendId ?? "",
                timeBudget: timeBudget
            )
            if sent {
                NSLog("[AppPushService NSE] Delivery receipt sent directly. notificationId=%@", notificationId ?? "nil")
                return
            }
            NSLog("[AppPushService NSE] Direct delivery receipt failed — falling back to queue.")
        } else {
            NSLog("[AppPushService NSE] appId/subscriptionId not yet in App Group — falling back to queue.")
        }

        var queue = defaults.array(forKey: SharedKey.nseEventQueue) as? [[String: Any]] ?? []
        queue.append([
            "type":            "delivered",
            "notification_id": notificationId ?? "",
            "subscription_id": subscriptionId ?? "",
            "device_id":       deviceId ?? "",
            "send_id":         sendId ?? "",
            "timestamp":       Date().timeIntervalSince1970,
        ])
        // Bound growth if the app is never reopened.
        if queue.count > 200 { queue.removeFirst(queue.count - 200) }
        defaults.set(queue, forKey: SharedKey.nseEventQueue)

        NSLog("[AppPushService NSE] Delivery receipt queued. notificationId=%@ queueSize=%d",
              notificationId ?? "nil", queue.count)
    }

    /// Best-effort, blocking `POST /v1/events/delivered` sent directly from the NSE
    /// process, before `contentHandler` hands the notification back to iOS. Blocked on a
    /// semaphore for at most `min(deliveryReceiptTimeout, timeBudget)` so it can never
    /// blow through the caller's overall processing deadline. Returns `false` (never
    /// throws) on any failure — offline, timeout, or a non-2xx response — so the caller
    /// can fall back to the App Group queue.
    ///
    /// Endpoint/body literals are duplicated from `EnvironmentConfig` /
    /// `AppsOnAirEventsAPI` in the main `AppsOnAirPush` target: the NSE target has zero
    /// package dependencies (not even on the main target, see Package.swift) and cannot
    /// import them. Keep in sync manually, same as `SharedKey` below.
    private static func sendDeliveryReceiptDirect(
        appId: String,
        subscriptionId: String,
        notificationId: String,
        sendId: String,
        timeBudget: TimeInterval
    ) -> Bool {
        guard timeBudget > 0.5, let url = URL(string: eventDeliveredURLString) else { return false }

        let body: [String: Any] = [
            "subscription_id": subscriptionId,
            "notification_id": notificationId,
            "send_id":         sendId
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            return false
        }

        let timeout = min(deliveryReceiptTimeout, timeBudget)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        request.httpBody = httpBody

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        let task = session.dataTask(with: request) { _, response, error in
            defer { semaphore.signal() }
            guard error == nil, let http = response as? HTTPURLResponse else {
                NSLog("[AppPushService NSE] POST /v1/events/delivered failed: %@",
                      error?.localizedDescription ?? "unknown error")
                return
            }
            succeeded = (200..<300).contains(http.statusCode)
            NSLog("[AppPushService NSE] POST /v1/events/delivered HTTP %d", http.statusCode)
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        session.finishTasksAndInvalidate()
        return succeeded
    }

    /// `POST /v1/events/delivered` — duplicated from `EnvironmentConfig.eventDelivered`
    /// in the main target (see `sendDeliveryReceiptDirect`). Keep in sync manually.
    private static let eventDeliveredURLString = "https://push.dev.appsonair.com/v1/events/delivered"

    /// 1) `AppsOnAirAppGroup` string in the NSE's Info.plist (authoritative).
    /// 2) Convention fallback: `group.<main-app-bundle-id>.appsonair`, derived by dropping
    ///    the last segment of the NSE bundle id (`com.acme.app.NotificationService`).
    private static func resolveAppGroupId() -> String? {
        if let explicit = Bundle.main.object(forInfoDictionaryKey: "AppsOnAirAppGroup") as? String,
           !explicit.isEmpty {
            return explicit
        }
        if let nseBundleId = Bundle.main.bundleIdentifier {
            let host = nseBundleId.split(separator: ".").dropLast().joined(separator: ".")
            if !host.isEmpty { return "group.\(host).appsonair" }
        }
        return nil
    }

    // MARK: Attachments

    private static func attachmentURLs(from userInfo: [AnyHashable: Any]) -> [URL] {
        var urls: [URL] = []

        if let list = userInfo[PayloadKey.attachments] as? [String] {
            urls += list.compactMap { URL(string: $0) }
        } else if let list = userInfo[PayloadKey.attachments] as? [[String: Any]] {
            urls += list.compactMap { ($0["url"] as? String).flatMap { URL(string: $0) } }
        }

        if urls.isEmpty {
            if let image = userInfo[PayloadKey.imageURL] as? String, let url = URL(string: image) {
                urls.append(url)
            } else if let video = userInfo[PayloadKey.videoURL] as? String, let url = URL(string: video) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func downloadAttachment(
        from url: URL,
        completion: @escaping @Sendable (UNNotificationAttachment?) -> Void
    ) {
        guard url.scheme?.lowercased() == "https" else {
            completion(nil)
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = attachmentDownloadTimeout
        config.timeoutIntervalForResource = attachmentDownloadTimeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        let task = session.downloadTask(with: url) { tempURL, response, error in
            defer { session.finishTasksAndInvalidate() }

            guard error == nil,
                  let tempURL,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                completion(nil)
                return
            }

            // Size validation — declared length and, authoritatively, the file on disk.
            if http.expectedContentLength > 0, http.expectedContentLength > maxAttachmentBytes {
                completion(nil)
                return
            }
            let onDisk = ((try? FileManager.default.attributesOfItem(atPath: tempURL.path))?[.size] as? NSNumber)?.int64Value ?? 0
            if onDisk > maxAttachmentBytes {
                completion(nil)
                return
            }

            // Type validation — URL extension first, then the response MIME type.
            guard let ext = Self.fileExtension(for: url, mimeType: http.mimeType) else {
                completion(nil)
                return
            }

            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: tempURL, to: dest)
                let attachment = try UNNotificationAttachment(
                    identifier: UUID().uuidString, url: dest, options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }

    /// Allow-listed media extensions the system can render in a notification.
    private static let allowedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "webp",
        "mp4", "m4v", "mov",
        "mp3", "m4a", "wav", "aiff", "aif",
    ]

    private static let mimeToExtension: [String: String] = [
        "image/jpeg": "jpg", "image/jpg": "jpg",   // image/jpg is non-standard but used by S3/Cloudinary
        "image/png": "png", "image/gif": "gif",
        "image/heic": "heic", "image/heif": "heic", "image/webp": "webp",
        "video/mp4": "mp4", "video/x-m4v": "m4v", "video/quicktime": "mov",
        "audio/mpeg": "mp3", "audio/mp3": "mp3",
        "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/aac": "m4a",
        "audio/wav": "wav", "audio/x-wav": "wav",
        "audio/aiff": "aiff", "audio/x-aiff": "aiff",
    ]

    private static func fileExtension(for url: URL, mimeType: String?) -> String? {
        let fromURL = url.pathExtension.lowercased()
        if allowedExtensions.contains(fromURL) { return fromURL }
        if let mime = mimeType?.lowercased(), let mapped = mimeToExtension[mime] { return mapped }
        return nil
    }

    // MARK: Concurrency helpers

    /// Thread-safe sink for attachments produced by concurrent downloads.
    private final class AttachmentCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [UNNotificationAttachment] = []

        func add(_ attachment: UNNotificationAttachment?) {
            guard let attachment else { return }
            lock.lock()
            storage.append(attachment)
            lock.unlock()
        }

        var attachments: [UNNotificationAttachment] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    // MARK: Deliver-once guard

    /// Wraps `contentHandler` so it can be called at most once even if the download
    /// callback and `serviceExtensionTimeWillExpire()` race.
    private final class DeliverOnce {
        private var handler: ((UNNotificationContent) -> Void)?
        private let lock = NSLock()

        init(_ handler: @escaping (UNNotificationContent) -> Void) {
            self.handler = handler
        }

        func callAsFunction(_ content: UNNotificationContent) {
            lock.lock()
            let handler = self.handler
            self.handler = nil
            lock.unlock()
            handler?(content)
        }
    }

    // MARK: Keys

    /// APNs data-payload keys read by the extension.
    private enum PayloadKey {
        static let notificationId  = "notification_id"
        static let sendId          = "send_id"
        static let title           = "title"
        static let body            = "body"
        static let subtitle        = "subtitle"
        static let sound           = "sound"
        static let imageURL        = "image_url"
        static let videoURL        = "video_url"
        static let attachments     = "attachments"
        static let badge           = "badge"
        static let badgeIncrement  = "badge_increment"
        static let actions         = "actions"
    }

    /// App Group `UserDefaults` keys. **Must mirror the literals written by
    /// `AppPushService.initialize()` in the main `AppPushService` target** — the two
    /// targets do not share code.
    private enum SharedKey {
        static let appId          = "com.appsonair.push.appId"
        static let deviceId       = "com.appsonair.push.deviceIdCache"
        static let subscriptionId = "com.appsonair.push.subscriptionId"
        static let appGroupId     = "com.appsonair.push.appGroupId"
        static let nseEventQueue  = "com.appsonair.push.nseEventQueue"
        static let badgeCount     = "com.appsonair.push.badgeCount"
    }
}
