import ObjectiveC
import UIKit
import UserNotifications

nonisolated(unsafe) private var originalDidRegisterTokenIMP: IMP?
nonisolated(unsafe) private var originalDidFailRegisterIMP: IMP?
nonisolated(unsafe) private var originalDidReceiveRemoteNotificationIMP: IMP?

private typealias DidRegisterTokenFunc          = @convention(c) (AnyObject, Selector, UIApplication, Data) -> Void
private typealias DidFailRegisterFunc           = @convention(c) (AnyObject, Selector, UIApplication, Error) -> Void
private typealias DidReceiveRemoteNotifFunc     = @convention(c) (AnyObject, Selector, UIApplication, [AnyHashable: Any], @escaping (UIBackgroundFetchResult) -> Void) -> Void

// MARK: - PushAppDelegateSwizzler

// @MainActor — all swizzle work runs on the main actor (see swizzle() body).
@MainActor
final class PushAppDelegateSwizzler {

    nonisolated(unsafe) private static var hasSwizzled = false
    private static var notificationDelegate: PushNotificationDelegate?

    static func swizzle() {
        guard !hasSwizzled else { return }
        hasSwizzled = true

        // Install the notification center delegate SYNCHRONOUSLY — this must not be
        // deferred. When the app cold-launches because the user tapped a notification,
        // iOS delivers `userNotificationCenter(_:didReceive:withCompletionHandler:)` on
        // the very next run-loop turn after `didFinishLaunchingWithOptions` returns.
        // If the delegate is not yet installed at that point, the tap is missed entirely
        // (no open/click event, no `onNotificationOpened` callback). Setting it here,
        // synchronously, guarantees it is in place before that delivery window opens.
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil {
            let d = PushNotificationDelegate()
            notificationDelegate = d  // hold strongly — center keeps only a weak ref
            center.delegate = d
        }

        // ObjC swizzles are deferred to the next run-loop turn so that
        // UIApplication.shared.delegate is guaranteed to be set (needed by
        // resolveAppDelegateClass) by the time we read it.
        Task { @MainActor in safeSwizzle() }
    }

    // All ObjC runtime calls are here. If anything fails the SDK logs and moves on.
    // The host app will never crash from a swizzle failure.
    private static func safeSwizzle() {
        guard let cls = resolveAppDelegateClass() else {
            AppPushService.log("AppDelegate class not found. APNs token callbacks must be forwarded manually.", level: .warn)
            return
        }

        swizzleToken(in: cls)
        swizzleFail(in: cls)

        // Silent push must be installed on the class iOS actually calls the method on.
        // With @UIApplicationDelegateAdaptor, UIApplication.shared.delegate is a SwiftUI
        // wrapper, not the real AppDelegate. SwiftUI caches which methods to forward at
        // startup — before this deferred swizzle runs — so adding didReceiveRemoteNotification
        // to the real AppDelegate class after the fact is invisible to the wrapper's
        // forwarding cache. When the two classes differ, install on the wrapper so iOS
        // delivers silent push directly to our handler without depending on SwiftUI forwarding.
        let silentPushTarget: AnyClass
        if let rawDelegate = UIApplication.shared.delegate {
            let rawCls: AnyClass = type(of: rawDelegate)
            silentPushTarget = (rawCls !== cls) ? rawCls : cls
        } else {
            silentPushTarget = cls
        }
        swizzleSilentPush(in: silentPushTarget)

        // Notification center delegate was already installed synchronously in swizzle().
        // Install it here as a fallback only if it was not set there (e.g. if the host
        // app set a delegate between swizzle() and this deferred call).
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil {
            let d = PushNotificationDelegate()
            notificationDelegate = d
            center.delegate = d
        }
    }

    // MARK: - Class resolution

    // UIApplication.shared.delegate returns SwiftUI.AppDelegate when using @UIApplicationDelegateAdaptor.
    // We detect this and fall back to the real AppDelegate by class name.
    private static func resolveAppDelegateClass() -> AnyClass? {
        guard let delegate = UIApplication.shared.delegate else { return nil }
        let cls: AnyClass = type(of: delegate)
        let name = NSStringFromClass(cls)

        guard name.contains("SwiftUI") || name.hasPrefix("_") else {
            return cls  // AOA: Already the real AppDelegate class — use directly
        }

        // AOA: SwiftUI wraps AppDelegate as "SwiftUI.AppDelegate" — must find real class by name
        // Swift class names are module-prefixed: "ModuleName.AppDelegate"
        // Module name = CFBundleExecutable (app target name e.g. "appsonair")
        let executable = Bundle.main.infoDictionary?["CFBundleExecutable"] as? String ?? ""

        return NSClassFromString("\(executable).AppDelegate")  // e.g. "appsonair.AppDelegate"
            ?? NSClassFromString("AppDelegate")                // AOA: Fallback for ObjC-style apps
    }

    // MARK: - Swizzle: token received

    private static func swizzleToken(in cls: AnyClass) {
        let sel = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))

        // @convention(block) is required by imp_implementationWithBlock — do not pass as Any
        let block: @convention(block) (AnyObject, UIApplication, Data) -> Void = { obj, app, token in
            MainActor.assumeIsolated { AppPushService.handleAPNsToken(token) }
            if let orig = originalDidRegisterTokenIMP {
                unsafeBitCast(orig, to: DidRegisterTokenFunc.self)(obj, sel, app, token)
            }
        }
        // "v@:@@" — void; self; sel; UIApplication*; NSData*
        install(imp: imp_implementationWithBlock(block), selector: sel, in: cls, typeEncoding: "v@:@@", original: &originalDidRegisterTokenIMP)
    }

    // MARK: - Swizzle: registration failed

    private static func swizzleFail(in cls: AnyClass) {
        let sel = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))

        let block: @convention(block) (AnyObject, UIApplication, Error) -> Void = { obj, app, error in
            MainActor.assumeIsolated { AppPushService.handleAPNsRegistrationError(error) }
            if let orig = originalDidFailRegisterIMP {
                unsafeBitCast(orig, to: DidFailRegisterFunc.self)(obj, sel, app, error)
            }
        }
        // "v@:@@" — void; self; sel; UIApplication*; NSError*
        install(imp: imp_implementationWithBlock(block), selector: sel, in: cls, typeEncoding: "v@:@@", original: &originalDidFailRegisterIMP)
    }

    // MARK: - Swizzle: silent push (content-available: 1)

    private static func swizzleSilentPush(in cls: AnyClass) {
        let sel = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))

        // If the host app already implements this method: chain to the original only —
        // the original is responsible for calling the completion handler.
        // If there is no host implementation: the SDK handles the silent push itself.
        let block: @convention(block) (AnyObject, UIApplication, [AnyHashable: Any], @escaping (UIBackgroundFetchResult) -> Void) -> Void = { obj, app, userInfo, completion in
            if let orig = originalDidReceiveRemoteNotificationIMP {
                // Chain to existing host-app implementation — it is responsible for calling completion
                unsafeBitCast(orig, to: DidReceiveRemoteNotifFunc.self)(obj, sel, app, userInfo, completion)
            } else {
                // No host implementation — SDK handles completion
                MainActor.assumeIsolated {
                    AppPushService.handleSilentPush(userInfo, fetchCompletionHandler: completion)
                }
            }
        }
        // "v@:@@?" — void; self; sel; UIApplication*; NSDictionary*; completion block
        install(imp: imp_implementationWithBlock(block), selector: sel, in: cls, typeEncoding: "v@:@@?", original: &originalDidReceiveRemoteNotificationIMP)
    }

    // MARK: - Install helper

    // Adds or replaces a method on a class safely.
    // If the class already has the method: swaps it, stores original for chaining.
    // If not: adds our IMP directly with the provided type encoding.
    // If the class is invalid or ObjC call fails: does nothing, no crash.
    //
    // typeEncoding must match the actual method signature:
    //   "v@:@@"   — void, self, sel, + 2 object args  (token / error selectors)
    //   "v@:@@?"  — void, self, sel, + 2 object args + block  (silent push selector)
    private static func install(imp newIMP: IMP, selector: Selector, in cls: AnyClass, typeEncoding: String, original: inout IMP?) {
        if class_addMethod(cls, selector, newIMP, typeEncoding) {
            original = nil
        } else if let method = class_getInstanceMethod(cls, selector) {
            original = method_setImplementation(method, newIMP)
        }
    }
}

// MARK: - PushNotificationDelegate

// Auto-installed when no UNUserNotificationCenterDelegate is set.
// @preconcurrency: UNUserNotificationCenterDelegate predates Swift concurrency —
// system guarantees callbacks are on main thread.
@MainActor
public final class PushNotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        AppPushService.handleWillPresent(notification: notification)
    }

    // NOTE: There is no `async` variant of didReceive(_:withCompletionHandler:).
    // The async overload only exists for willPresent (iOS 15+). Using the wrong
    // signature here would cause the delegate method to never be called by the system.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        AppPushService.handleDidReceive(response: response)
        completionHandler()
    }
}
