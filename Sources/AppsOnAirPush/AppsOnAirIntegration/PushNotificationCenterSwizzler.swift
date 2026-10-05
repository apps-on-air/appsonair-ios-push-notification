import Foundation
import ObjectiveC
import UserNotifications

nonisolated(unsafe) private var originalSetDelegateIMP: IMP?

private typealias SetDelegateFunc  = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
private typealias WillPresentFunc  = @convention(c) (AnyObject, Selector, UNUserNotificationCenter, UNNotification, @escaping (UNNotificationPresentationOptions) -> Void) -> Void
private typealias DidReceiveFunc   = @convention(c) (AnyObject, Selector, UNUserNotificationCenter, UNNotificationResponse, @escaping () -> Void) -> Void

// MARK: - PushNotificationCenterSwizzler

// Only one object can be UNUserNotificationCenter's delegate. The SDK installs its own
// PushNotificationDelegate when the slot is empty, but in many apps something else owns
// it — Notifee (React Native), a Flutter plugin, or the host AppDelegate — either before
// initialize() runs or by taking it afterwards. Without help, AppsOnAir pushes then never
// reach the SDK unless the host forwards willPresent / didReceive by hand.
//
// This hooks the delegate the SDK does not own, now and whenever one is assigned later
// (via -[UNUserNotificationCenter setDelegate:]). For AppsOnAir remote pushes only, the
// SDK handler runs first; the delegate's own implementation then ALWAYS runs as well, so
// its behaviour (Notifee display, plugin buffering, host deep links) is unchanged. If that
// implementation also forwards to the SDK, AppPushService de-duplicates the second call.
//
// Only methods the delegate already implements (directly or inherited) are wrapped — the
// SDK never adds notification callbacks a delegate chose not to implement.
enum PushNotificationCenterSwizzler {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var wrappedClasses = Set<ObjectIdentifier>()

    private static let willPresentSelector = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    private static let didReceiveSelector  = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")

    /// Called once, from PushAppDelegateSwizzler.swizzle().
    static func install(on center: UNUserNotificationCenter) {
        if let current = center.delegate {
            wrapDelegate(current)
        }
        hookSetDelegate()
    }

    // MARK: - setDelegate: hook

    private static func hookSetDelegate() {
        let sel = NSSelectorFromString("setDelegate:")
        guard let method = class_getInstanceMethod(UNUserNotificationCenter.self, sel) else {
            AppPushService.log("UNUserNotificationCenter.setDelegate: not found — later notification delegates are not hooked.", level: .warn)
            return
        }
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { center, delegate in
            // Wrap before assigning, so the methods are in place when the center adopts it.
            if let delegate { wrapDelegate(delegate) }
            if let orig = originalSetDelegateIMP {
                unsafeBitCast(orig, to: SetDelegateFunc.self)(center, sel, delegate)
            }
        }
        originalSetDelegateIMP = method_setImplementation(method, imp_implementationWithBlock(block))
    }

    // MARK: - Delegate wrapping

    private static func wrapDelegate(_ delegate: AnyObject) {
        // The SDK's own delegate already calls the SDK.
        if delegate is PushNotificationDelegate { return }
        let cls: AnyClass = type(of: delegate)

        lock.lock()
        let isNew = wrappedClasses.insert(ObjectIdentifier(cls)).inserted
        lock.unlock()
        guard isNew else { return }

        wrapWillPresent(in: cls)
        wrapDidReceive(in: cls)
        AppPushService.log("Notification delegate \(NSStringFromClass(cls)) hooked for AppsOnAir pushes.", level: .debug)
    }

    private static func wrapWillPresent(in cls: AnyClass) {
        let sel = willPresentSelector
        guard let orig = originalIMP(of: sel, in: cls) else { return }
        let block: @convention(block) (AnyObject, UNUserNotificationCenter, UNNotification, @escaping (UNNotificationPresentationOptions) -> Void) -> Void = { obj, center, notification, completion in
            let callOriginal = unsafeBitCast(orig, to: WillPresentFunc.self)
            guard isAppsOnAirPush(notification) else {
                callOriginal(obj, sel, center, notification, completion)
                return
            }
            // UNUserNotificationCenter calls its delegate on the main thread.
            nonisolated(unsafe) let delivered = notification
            let sdkOptions = MainActor.assumeIsolated { AppPushService.handleWillPresent(notification: delivered) }
            // The delegate still decides for itself; the SDK's options are added so an
            // AppsOnAir push is shown in the foreground exactly as with the SDK's own
            // delegate (a lifecycle listener's preventDefault() makes sdkOptions empty).
            let once = CompletionOnce(completion)
            callOriginal(obj, sel, center, notification) { hostOptions in
                once.call(hostOptions.union(sdkOptions))
            }
            // Some delegates never complete for a push that isn't theirs — Notifee does
            // nothing when it had no earlier delegate to forward to — and iOS then never
            // shows the banner. If the delegate hasn't completed by now, the SDK does.
            DispatchQueue.main.asyncAfter(deadline: .now() + completionFallbackDelay) {
                if once.call(sdkOptions) {
                    AppPushService.log("Notification delegate \(NSStringFromClass(cls)) did not complete willPresent — completed by the SDK.", level: .debug)
                }
            }
        }
        replace(sel, in: cls, with: imp_implementationWithBlock(block))
    }

    private static func wrapDidReceive(in cls: AnyClass) {
        let sel = didReceiveSelector
        guard let orig = originalIMP(of: sel, in: cls) else { return }
        let block: @convention(block) (AnyObject, UNUserNotificationCenter, UNNotificationResponse, @escaping () -> Void) -> Void = { obj, center, response, completion in
            if isAppsOnAirPush(response.notification) {
                nonisolated(unsafe) let tapped = response
                MainActor.assumeIsolated { AppPushService.handleDidReceive(response: tapped) }
            }
            // The delegate owns the completion handler.
            unsafeBitCast(orig, to: DidReceiveFunc.self)(obj, sel, center, response, completion)
        }
        replace(sel, in: cls, with: imp_implementationWithBlock(block))
    }

    // MARK: - Helpers

    /// How long a hooked delegate gets to complete willPresent for an AppsOnAir push
    /// before the SDK completes it instead. Long enough for delegates that complete
    /// asynchronously (e.g. Swift `async` implementations).
    private static let completionFallbackDelay: TimeInterval = 0.5

    /// Lets exactly one of the delegate and the SDK's fallback call the completion handler.
    private final class CompletionOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((UNNotificationPresentationOptions) -> Void)?

        init(_ completion: @escaping (UNNotificationPresentationOptions) -> Void) {
            self.completion = completion
        }

        /// Returns true if this call was the one that completed.
        @discardableResult
        func call(_ options: UNNotificationPresentationOptions) -> Bool {
            lock.lock()
            let completion = self.completion
            self.completion = nil
            lock.unlock()
            completion?(options)
            return completion != nil
        }
    }

    /// An AppsOnAir push is a remote notification carrying a `notification_id`.
    /// Everything else (Notifee local notifications, other providers) is left alone.
    private static func isAppsOnAirPush(_ notification: UNNotification) -> Bool {
        guard notification.request.trigger is UNPushNotificationTrigger else { return false }
        let id = notification.request.content.userInfo["notification_id"] as? String
        return !(id ?? "").isEmpty
    }

    /// The implementation the class currently responds with, including an inherited one.
    private static func originalIMP(of sel: Selector, in cls: AnyClass) -> IMP? {
        class_getInstanceMethod(cls, sel).map(method_getImplementation)
    }

    /// Installs `newIMP` on `cls` itself: replaces the class's own implementation, or —
    /// when the method is inherited — adds an override so the superclass is untouched.
    private static func replace(_ sel: Selector, in cls: AnyClass, with newIMP: IMP) {
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        if !class_addMethod(cls, sel, newIMP, method_getTypeEncoding(method)) {
            method_setImplementation(method, newIMP)
        }
    }
}
