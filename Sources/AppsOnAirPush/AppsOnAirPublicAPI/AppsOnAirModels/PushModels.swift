import Foundation
import UserNotifications

// MARK: - APNsEnvironment

/// APNs environment the device token belongs to.
/// Read from the app's entitlements — 100% accurate, no extra APNs calls needed.
/// - sandbox:    Debug / Xcode / Ad-hoc builds → api.sandbox.push.apple.com
/// - production: App Store / TestFlight builds  → api.push.apple.com
public enum APNsEnvironment: String, Sendable {
    case sandbox    = "sandbox"
    case production = "production"
}

// MARK: - NotificationPermission

/// Native OS notification authorization status.
/// Mirrors OneSignal v5 `OSNotificationPermission` and iOS `UNAuthorizationStatus`.
public enum NotificationPermission: Int, Sendable {
    case notDetermined = 0
    case denied
    case authorized
    case provisional
    case ephemeral

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied:        self = .denied
        case .authorized:    self = .authorized
        case .provisional:   self = .provisional
        case .ephemeral:     self = .ephemeral
        @unknown default:    self = .notDetermined
        }
    }

    /// true for `.authorized`, `.provisional`, and `.ephemeral`.
    public var isGranted: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied:               return false
        }
    }
}

// MARK: - PushListener

/// Implement this protocol to receive SDK events.
/// All methods have empty default implementations — only override what you need.
public protocol PushListener: AnyObject {
    /// Called when APNs issues a device token.
    /// - token: 64-char hex string — send to your backend to trigger push.
    /// - environment: sandbox or production — send to backend so it calls the correct APNs endpoint.
    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment)
    /// Called when a notification arrives while the app is in the foreground.
    func onNotificationReceived(notification: PushNotification)
    /// Called when the user taps a notification.
    func onNotificationOpened(notification: PushNotification)
    /// Called on any SDK error (e.g. permission denied, APNs registration failed).
    func onError(_ error: PushError)
}

public extension PushListener {
    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) {}
    func onNotificationReceived(notification: PushNotification) {}
    func onNotificationOpened(notification: PushNotification) {}
    func onError(_ error: PushError) {}
}

// MARK: - PushNotification

/// Data from a received or tapped notification — the full parsed §9.1 APNs payload.
// @unchecked because userInfo is [AnyHashable: Any] from APNs payload —
// values are primitive types (String, Int) but can't be statically verified as Sendable
public struct PushNotification: @unchecked Sendable {

    /// An action button from the payload `actions` array (§9.1). Only `id` + `title`
    /// are surfaced here — `url` / `foreground` / `destructive` drive OS behaviour and are
    /// left in `userInfo` / `rawPayload` for apps that need them. The category that makes
    /// these buttons actually render is registered elsewhere: automatically by the NSE
    /// (`AppPushServiceExtension`, reliable) or, without one, as a best-effort fallback by
    /// `AppPushService.handleWillPresent` when the payload sets `aps.category` — see either
    /// for the registration itself.
    public struct ActionButton: Sendable {
        public let id: String
        public let title: String
    }

    /// A media attachment from the payload `attachments` array (§9.1), or a single
    /// synthesized entry from `image_url` when `attachments` is absent.
    public struct Attachment: Sendable {
        public let id: String?
        public let url: String
    }

    /// Value of "notification_id" from the push payload. Nil if not present.
    public let id: String?
    /// "campaign_id" — analytics grouping. Nil if not present.
    public let campaignId: String?
    /// "template_id" — source template, for analytics. Nil if not present.
    public let templateId: String?
    /// "sent_at" — server send time, ISO-8601 string exactly as received.
    public let sentAt: String?
    /// "send_id" — identifies this specific dispatch of the notification.
    /// Required by the open/click and delivery event APIs. Nil if not present.
    public let sendId: String?

    public let title: String?
    /// "subtitle" — iOS second line above the body.
    public let subtitle: String?
    public let body: String?

    /// "url" — deep link or web URL to open on tap.
    public let launchUrl: String?
    /// "image_url" — single banner image URL (loses to `attachments`).
    public let imageUrl: String?
    /// "attachments" `[{ id, url }]`; falls back to one entry built from `image_url`.
    public let attachments: [Attachment]
    /// "actions" — action buttons, `id` + `title` only.
    public let actionButtons: [ActionButton]
    /// "badge_increment" — delta the NSE / SDK applies to the running badge total.
    public let badgeIncrement: Int?
    /// "collapse_id" if the backend echoes it into the body (APNs delivers
    /// `apns-collapse-id` as a header only, which iOS does not surface to the app).
    public let collapseId: String?
    /// "additional_data" — opaque app payload, parsed. Empty dictionary if absent.
    public let additionalData: [AnyHashable: Any]

    /// Full APNs payload — access any custom keys you sent from Postman/backend.
    public let userInfo: [AnyHashable: Any]

    /// §7 SDK-surface name for `userInfo` — the full received payload.
    public var rawPayload: [AnyHashable: Any] { userInfo }

    // Built from a UNNotificationContent — called internally by the SDK.
    static func from(_ content: UNNotificationContent) -> PushNotification {
        from(
            userInfo: content.userInfo,
            renderedTitle: content.title,
            renderedSubtitle: content.subtitle,
            renderedBody: content.body
        )
    }

    /// Parse the full §9.1 payload. `rendered*` come from `UNNotificationContent` and
    /// already reflect any Notification Service Extension text overrides; the top-level
    /// `title` / `subtitle` / `body` payload keys are the fallback.
    static func from(
        userInfo: [AnyHashable: Any],
        renderedTitle: String? = nil,
        renderedSubtitle: String? = nil,
        renderedBody: String? = nil
    ) -> PushNotification {
        func str(_ key: String) -> String? {
            (userInfo[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func nonEmpty(_ value: String?) -> String? {
            value.flatMap { $0.isEmpty ? nil : $0 }
        }

        // additional_data — a real nested JSON object on APNs; tolerate a JSON string
        // too (the Android wire form), so the shape matches across platforms.
        var additionalData: [String: Any] = [:]
        if let dict = userInfo["additional_data"] as? [String: Any] {
            additionalData = dict
        } else if let json = userInfo["additional_data"] as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            additionalData = dict
        }

        // actions — [{ id, title, ... }]; expose id + title only (§7).
        let actionButtons: [ActionButton] = (userInfo["actions"] as? [[String: Any]] ?? [])
            .compactMap { entry in
                guard let id = entry["id"] as? String,
                      let title = entry["title"] as? String else { return nil }
                return ActionButton(id: id, title: title)
            }

        // attachments — [{ id, url }] or [String]; else one entry from image_url.
        var attachments: [Attachment] = []
        if let list = userInfo["attachments"] as? [[String: Any]] {
            attachments = list.compactMap { entry in
                guard let url = entry["url"] as? String else { return nil }
                return Attachment(id: entry["id"] as? String, url: url)
            }
        } else if let list = userInfo["attachments"] as? [String] {
            attachments = list.map { Attachment(id: nil, url: $0) }
        }
        if attachments.isEmpty, let image = str("image_url") {
            attachments = [Attachment(id: nil, url: image)]
        }

        return PushNotification(
            id: str("notification_id"),
            campaignId: str("campaign_id"),
            templateId: str("template_id"),
            sentAt: str("sent_at"),
            sendId: str("send_id"),
            title: nonEmpty(renderedTitle) ?? str("title"),
            subtitle: nonEmpty(renderedSubtitle) ?? str("subtitle"),
            body: nonEmpty(renderedBody) ?? str("body"),
            launchUrl: str("url"),
            imageUrl: str("image_url"),
            attachments: attachments,
            actionButtons: actionButtons,
            badgeIncrement: intValue(userInfo["badge_increment"]),
            collapseId: str("collapse_id"),
            additionalData: additionalData,
            userInfo: userInfo
        )
    }

    /// Coerce a JSON value (`Int`, `NSNumber`, numeric `String`) to `Int`.
    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let int as Int:      return int
        case let num as NSNumber: return num.intValue
        case let str as String:   return Int(str)
        default:                  return nil
        }
    }
}

// MARK: - PushError

public struct PushError: Error, Sendable {
    public enum Code: String, Sendable {
        case notInitialized
        case permissionDenied
        case apnsRegistrationFailed
        case unknown
    }
    public let code: Code
    public let message: String
}

// MARK: - LogLevel

public enum LogLevel: Int, Comparable {
    case none = 0, fatal, error, warn, info, debug, verbose
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - NotificationWillDisplayEvent

/// Used in foreground lifecycle listener.
/// Host app can call preventDefault() to suppress the system notification display.
public final class NotificationWillDisplayEvent {
    public let notification: PushNotification
    private(set) var isPreventDefault = false
    init(notification: PushNotification) { self.notification = notification }
    public func preventDefault() { isPreventDefault = true }
}

// MARK: - NotificationClickEvent

/// Details of how the user interacted with the notification.
/// Mirrors OneSignal v5 `OSNotificationClickResult`.
public struct NotificationClickResult {
    /// nil = notification body tapped; non-nil = specific action button ID tapped.
    public let actionId: String?
    /// Launch URL attached to the notification payload (`url` key), if any.
    public let url: String?
}

/// Passed to click listeners when user taps notification or action button.
/// Mirrors OneSignal v5 `OSNotificationClickEvent`.
public struct NotificationClickEvent {
    public let notification: PushNotification
    /// What the user tapped — action button ID and/or launch URL.
    public let result: NotificationClickResult
}

// MARK: - PushSubscriptionState

public struct PushSubscriptionState {
    public let token: String?
    public let optedIn: Bool
}

public struct PushSubscriptionChangedState {
    public let previous: PushSubscriptionState
    public let current: PushSubscriptionState
}

// MARK: - UserChangedState

/// Snapshot of the user's identity. Mirrors OneSignal v5 `OSUserState`.
public struct UserState {
    /// The external user ID linked via `login(_:)`. nil when anonymous.
    public let externalId: String?

    /// The AppsOnAir-assigned device ID.
    public let appsOnAirId: String
}

/// Passed to user-state observers. Mirrors OneSignal v5 `OSUserChangedState`
/// (access the values via `state.current`).
public struct UserChangedState {
    public let current: UserState
}

// MARK: - Listener / Observer protocols

public protocol NotificationLifecycleListener: AnyObject {
    func onWillDisplay(event: NotificationWillDisplayEvent)
}

public protocol NotificationClickListener: AnyObject {
    func onClick(event: NotificationClickEvent)
}

public protocol NotificationPermissionObserver: AnyObject {
    /// Matches OneSignal v5 `OSNotificationPermissionObserver.onNotificationPermissionDidChange(_:)`.
    func onNotificationPermissionDidChange(_ permission: Bool)
}

public protocol PushSubscriptionObserver: AnyObject {
    /// Matches OneSignal v5 `OSPushSubscriptionObserver.onPushSubscriptionDidChange(state:)`.
    func onPushSubscriptionDidChange(state: PushSubscriptionChangedState)
}

public protocol UserStateObserver: AnyObject {
    /// Matches OneSignal v5 `OSUserStateObserver.onUserStateDidChange(state:)`.
    func onUserStateDidChange(state: UserChangedState)
}

// MARK: - PushEventType

/// Type of SDK event persisted in the local queue and reported to the backend.
/// Scope §3.3: SDK reports open/click events back.
/// Scope §3.4: NSE reports delivery receipts back (iOS only, paid tier).
public enum PushEventType: String, Codable {
    /// User tapped the notification body (actionId is nil).
    case opened
    /// User tapped a specific action button (actionId is set).
    case clicked
    /// Notification delivered to the foreground (local record — no backend call for free tier).
    case received
    /// NSE confirmed delivery to the device — powers "Delivered" analytics (paid tier, §3.4).
    case delivered
}

// MARK: - PushEvent

/// An SDK event persisted in the local queue and sent to the backend on flush.
/// Survives app restarts — written to UserDefaults immediately on enqueue.
public struct PushEvent: Codable {
    /// What happened.
    public let type: PushEventType
    /// AppsOnAir notification ID from the push payload ("notification_id" key). Nil if not present.
    public let notificationId: String?
    /// Backend-assigned subscription ID for this device. Nil until /subscriptions API is called.
    public let subscriptionId: String?
    /// Non-nil for action button taps; nil for notification body taps.
    public let actionId: String?
    /// Unix timestamp (seconds since epoch) when the event occurred.
    public let timestamp: TimeInterval
    /// Per-install device ID, from `AppPushService.deviceId` (AppsOnAir_Core).
    public let deviceId: String
    /// "send_id" from the push payload — identifies this specific dispatch of the
    /// notification. Required by `POST /v1/events/delivered`. Nil for event types
    /// that don't carry one.
    public let sendId: String?

    init(
        type: PushEventType,
        notificationId: String? = nil,
        subscriptionId: String? = nil,
        actionId: String? = nil,
        sendId: String? = nil
    ) {
        self.type = type
        self.notificationId = notificationId
        self.subscriptionId = subscriptionId
        self.actionId = actionId
        self.timestamp = Date().timeIntervalSince1970
        // AppPushService.deviceId is nonisolated and synchronous, so it is safe to
        // read here regardless of actor context.
        self.deviceId = AppPushService.deviceId
        self.sendId = sendId
    }

    /// Full initializer — used when replaying an event captured in another process
    /// (e.g. a delivery receipt written by the Notification Service Extension) so the
    /// original timestamp and device ID are preserved rather than recomputed.
    init(
        type: PushEventType,
        notificationId: String?,
        subscriptionId: String?,
        actionId: String?,
        timestamp: TimeInterval,
        deviceId: String,
        sendId: String? = nil
    ) {
        self.type = type
        self.notificationId = notificationId
        self.subscriptionId = subscriptionId
        self.actionId = actionId
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.sendId = sendId
    }
}
