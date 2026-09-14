import Foundation
import UserNotifications

// MARK: - AOAPushExtension

/// ObjC-callable static wrapper around the ``AppPushServiceExtension`` free-function API.
///
/// `AppPushServiceExtension` is a Swift `enum` (namespace) — not `@objc`, so
/// Objective-C cannot call it directly. This `NSObject` subclass (which is **not**
/// `@MainActor`-isolated) exposes the same two entry points as `+` (class) methods
/// that ObjC NSE implementations can call without triggering
/// `objc_subclassing_restricted`.
///
/// ## Objective-C usage
/// ```objc
/// @import AppsOnAirPushServiceExt;   // imports AOAPushExtension
///
/// @interface NotificationService : UNNotificationServiceExtension
/// @property (nonatomic, strong) UNNotificationRequest            *receivedRequest;
/// @property (nonatomic, copy)   void (^contentHandler)(UNNotificationContent *);
/// @property (nonatomic, strong) UNMutableNotificationContent     *bestAttemptContent;
/// @end
///
/// @implementation NotificationService
/// - (void)didReceiveNotificationRequest:(UNNotificationRequest *)request
///                    withContentHandler:(void (^)(UNNotificationContent *))contentHandler {
///     self.receivedRequest    = request;
///     self.contentHandler     = contentHandler;
///     self.bestAttemptContent = [request.content mutableCopy];
///     [AOAPushExtension didReceiveNotificationRequest:request withContentHandler:contentHandler];
///     self.contentHandler = nil;   // SDK delivers before returning; prevent double-send.
/// }
/// - (void)serviceExtensionTimeWillExpire {
///     [AOAPushExtension serviceExtensionTimeWillExpireRequest:self.receivedRequest
///                                        bestAttemptContent:self.bestAttemptContent
///                                            contentHandler:self.contentHandler];
///     self.contentHandler = nil;
/// }
/// @end
/// ```
@available(macOS 10.14, *)
@objc(AOAPushExtension)
public final class AOAPushExtension: NSObject {

    // MARK: - Entry points

    /// Processes text overrides, badge, delivery receipt, and media attachments for
    /// the given notification request, then invokes `contentHandler` exactly once
    /// before returning — mirroring `AppPushServiceExtension.didReceiveNotificationExtensionRequest`.
    @objc public static func didReceiveNotificationRequest(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        AppPushServiceExtension.didReceiveNotificationExtensionRequest(
            request, with: mutable, withContentHandler: contentHandler)
    }

    /// Applies text overrides to `bestAttemptContent` (skips attachment downloads —
    /// no time left) then calls `contentHandler` — mirroring
    /// `AppPushServiceExtension.serviceExtensionTimeWillExpireRequest`.
    @objc public static func serviceExtensionTimeWillExpireRequest(
        _ request: UNNotificationRequest,
        bestAttemptContent: UNMutableNotificationContent?,
        contentHandler: ((UNNotificationContent) -> Void)?
    ) {
        guard let content = bestAttemptContent, let handler = contentHandler else { return }
        let result = AppPushServiceExtension.serviceExtensionTimeWillExpireRequest(
            request, with: content) ?? content
        handler(result)
    }
}
