import Foundation

// MARK: - AOAActionButton

/// ObjC-compatible wrapper for PushNotification.ActionButton.
@objc(AOAActionButton)
public final class AOAActionButton: NSObject {
    @objc public let id: String
    @objc public let title: String

    internal init(_ swift: PushNotification.ActionButton) {
        self.id = swift.id
        self.title = swift.title
    }
}

// MARK: - AOAAttachment

/// ObjC-compatible wrapper for PushNotification.Attachment.
@objc(AOAAttachment)
public final class AOAAttachment: NSObject {
    /// The attachment ID, or nil if not present.
    @objc public let identifier: String?
    @objc public let url: String

    internal init(_ swift: PushNotification.Attachment) {
        self.identifier = swift.id
        self.url = swift.url
    }
}

// MARK: - AOAPushNotification

/// ObjC-compatible wrapper for PushNotification.
/// Note: `id` is renamed to `identifier` to avoid the ObjC `id` keyword.
@objc(AOAPushNotification)
public final class AOAPushNotification: NSObject {
    /// Notification ID from the push payload. Nil if not present.
    @objc public let identifier: String?
    @objc public let campaignId: String?
    @objc public let templateId: String?
    @objc public let sentAt: String?
    /// Identifies this specific dispatch of the notification. Required by open/click/delivery event APIs.
    @objc public let sendId: String?
    @objc public let title: String?
    @objc public let subtitle: String?
    @objc public let body: String?
    @objc public let launchUrl: String?
    @objc public let imageUrl: String?
    @objc public let attachments: [AOAAttachment]
    @objc public let actionButtons: [AOAActionButton]
    /// badgeIncrement as NSNumber so it can be nil in ObjC.
    @objc public let badgeIncrement: NSNumber?
    @objc public let collapseId: String?
    /// additionalData as NSDictionary for ObjC compatibility.
    @objc public let additionalData: NSDictionary
    /// Full APNs userInfo payload.
    @objc public let userInfo: NSDictionary

    internal init(_ swift: PushNotification) {
        self.identifier    = swift.id
        self.campaignId    = swift.campaignId
        self.templateId    = swift.templateId
        self.sentAt        = swift.sentAt
        self.sendId        = swift.sendId
        self.title         = swift.title
        self.subtitle      = swift.subtitle
        self.body          = swift.body
        self.launchUrl     = swift.launchUrl
        self.imageUrl      = swift.imageUrl
        self.attachments   = swift.attachments.map { AOAAttachment($0) }
        self.actionButtons = swift.actionButtons.map { AOAActionButton($0) }
        self.badgeIncrement = swift.badgeIncrement.map { NSNumber(value: $0) }
        self.collapseId    = swift.collapseId
        self.additionalData = swift.additionalData as NSDictionary
        self.userInfo       = swift.userInfo as NSDictionary
    }
}

// MARK: - AOANotificationClickResult

/// ObjC-compatible wrapper for NotificationClickResult.
@objc(AOANotificationClickResult)
public final class AOANotificationClickResult: NSObject {
    /// Nil = notification body tapped; non-nil = action button ID.
    @objc public let actionId: String?
    @objc public let url: String?

    internal init(_ swift: NotificationClickResult) {
        self.actionId = swift.actionId
        self.url      = swift.url
    }
}

// MARK: - AOANotificationClickEvent

/// ObjC-compatible wrapper for NotificationClickEvent.
@objc(AOANotificationClickEvent)
public final class AOANotificationClickEvent: NSObject {
    @objc public let notification: AOAPushNotification
    @objc public let result: AOANotificationClickResult

    internal init(_ swift: NotificationClickEvent) {
        self.notification = AOAPushNotification(swift.notification)
        self.result       = AOANotificationClickResult(swift.result)
    }
}

// MARK: - AOANotificationWillDisplayEvent

/// ObjC-compatible wrapper for NotificationWillDisplayEvent.
@objc(AOANotificationWillDisplayEvent)
public final class AOANotificationWillDisplayEvent: NSObject {
    @objc public let notification: AOAPushNotification
    private let swiftEvent: NotificationWillDisplayEvent

    internal init(_ swift: NotificationWillDisplayEvent) {
        self.notification = AOAPushNotification(swift.notification)
        self.swiftEvent   = swift
    }

    /// Call to suppress the system notification banner.
    @objc public func preventDefault() {
        swiftEvent.preventDefault()
    }
}

// MARK: - AOAPushSubscriptionState

/// ObjC-compatible wrapper for PushSubscriptionState.
@objc(AOAPushSubscriptionState)
public final class AOAPushSubscriptionState: NSObject {
    @objc public let token: String?
    @objc public let optedIn: Bool

    internal init(_ swift: PushSubscriptionState) {
        self.token   = swift.token
        self.optedIn = swift.optedIn
    }
}

// MARK: - AOAPushSubscriptionChangedState

/// ObjC-compatible wrapper for PushSubscriptionChangedState.
@objc(AOAPushSubscriptionChangedState)
public final class AOAPushSubscriptionChangedState: NSObject {
    @objc public let previous: AOAPushSubscriptionState
    @objc public let current: AOAPushSubscriptionState

    internal init(_ swift: PushSubscriptionChangedState) {
        self.previous = AOAPushSubscriptionState(swift.previous)
        self.current  = AOAPushSubscriptionState(swift.current)
    }
}

// MARK: - AOAUserState

/// ObjC-compatible wrapper for UserState.
@objc(AOAUserState)
public final class AOAUserState: NSObject {
    @objc public let externalId: String?
    @objc public let appsOnAirId: String

    internal init(_ swift: UserState) {
        self.externalId  = swift.externalId
        self.appsOnAirId = swift.appsOnAirId
    }
}

// MARK: - AOAUserChangedState

/// ObjC-compatible wrapper for UserChangedState.
@objc(AOAUserChangedState)
public final class AOAUserChangedState: NSObject {
    @objc public let current: AOAUserState

    internal init(_ swift: UserChangedState) {
        self.current = AOAUserState(swift.current)
    }
}
