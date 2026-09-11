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
//   2. `AppsOnAirPushExtension` — free functions to call from your own
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
//             • CocoaPods: pod 'AppsOnAirPush/ServiceExtension'
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
//                     AppsOnAirPushExtension.didReceiveNotificationExtensionRequest(
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
//  | image_url         | String (https)             | Single image to attach. Wins over `video_url`.                   |
//  | video_url         | String (https)             | Single video to attach. Used only when `image_url` is absent.    |
//  | attachments       | [String] or [{id,url}]     | Multiple media URLs. Takes precedence over image_url/video_url.  |
//  | badge             | Int                        | Absolute app-icon badge count. `max(0, value)`.                  |
//  | badge_increment   | Int (may be negative)      | Delta applied to the running badge total: `max(0, stored+delta)`.|
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
        AppsOnAirPushExtension.didReceiveNotificationExtensionRequest(
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
        let final = AppsOnAirPushExtension.serviceExtensionTimeWillExpireRequest(request, with: content) ?? content
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
public enum AppsOnAirPushExtension {

    // MARK: Tunables

    /// Hard cap on time spent inside `didReceiveNotificationExtensionRequest` before we
    /// deliver whatever we have. Kept below the iOS 30 s NSE budget for headroom.
    private static let maxProcessingTime: TimeInterval = 25
    /// Per-attachment network timeout.
    private static let attachmentDownloadTimeout: TimeInterval = 15
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

        applyTextOverrides(to: content, userInfo: userInfo)
        applyBadge(to: content, userInfo: userInfo)
        recordDeliveryReceipt(userInfo: userInfo)

        let urls = attachmentURLs(from: userInfo)
        guard !urls.isEmpty else {
            deliver(content)
            return
        }

        let deadline = Date().addingTimeInterval(maxProcessingTime)
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

        NSLog("[AppsOnAirPush NSE] Badge count %d → %d (increment=%@, absolute=%@).",
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

    // MARK: Delivery receipt

    /// Persist a delivery receipt to the App Group shared queue. The main app drains it
    /// on next foreground via `AppsOnAirEventQueue.drainSharedExtensionQueue()`.
    ///
    /// NOTE: a direct `POST /events/delivered` from the NSE process is intentionally NOT
    /// performed here — it needs the resolved backend base URL + auth token, which are
    /// not available to the extension yet. Wire it in once that contract exists.
    private static func recordDeliveryReceipt(userInfo: [AnyHashable: Any]) {
        let notificationId = (userInfo[PayloadKey.notificationId] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let groupId = resolveAppGroupId(),
              let defaults = UserDefaults(suiteName: groupId) else {
            NSLog("[AppsOnAirPush NSE] App Group not resolvable — delivery receipt NOT persisted. " +
                  "Add 'AppsOnAirAppGroup' to the NSE Info.plist (STEP 4).")
            return
        }

        let subscriptionId = defaults.string(forKey: SharedKey.subscriptionId)
        let deviceId       = defaults.string(forKey: SharedKey.deviceId)

        var queue = defaults.array(forKey: SharedKey.nseEventQueue) as? [[String: Any]] ?? []
        queue.append([
            "type":            "delivered",
            "notification_id": notificationId ?? "",
            "subscription_id": subscriptionId ?? "",
            "device_id":       deviceId ?? "",
            "timestamp":       Date().timeIntervalSince1970,
        ])
        // Bound growth if the app is never reopened.
        if queue.count > 200 { queue.removeFirst(queue.count - 200) }
        defaults.set(queue, forKey: SharedKey.nseEventQueue)

        NSLog("[AppsOnAirPush NSE] Delivery receipt queued. notificationId=%@ queueSize=%d",
              notificationId ?? "nil", queue.count)
    }

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
        "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif",
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
        static let title           = "title"
        static let body            = "body"
        static let subtitle        = "subtitle"
        static let imageURL        = "image_url"
        static let videoURL        = "video_url"
        static let attachments     = "attachments"
        static let badge           = "badge"
        static let badgeIncrement  = "badge_increment"
    }

    /// App Group `UserDefaults` keys. **Must mirror the literals written by
    /// `AppsOnAirPush.initialize()` in the main `AppsOnAirPush` target** — the two
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
