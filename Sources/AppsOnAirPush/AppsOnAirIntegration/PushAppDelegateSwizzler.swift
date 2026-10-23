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
    /// Held once safeSwizzle() reassigns UIApplication.shared.delegate (see there).
    private static var appDelegate: UIApplicationDelegate?

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

        // When another component owns (or later takes) the notification delegate —
        // Notifee, a cross-platform plugin, the host AppDelegate — make sure AppsOnAir
        // pushes still reach the SDK without the host forwarding them manually.
        PushNotificationCenterSwizzler.install(on: center)

        // The ObjC swizzles need UIApplication.shared.delegate (see resolveAppDelegateClass).
        // It is already set when initialize() runs from didFinishLaunching, from a
        // didFinishLaunching observer (React Native) or from a plugin (Flutter), so swizzle
        // right away — no run-loop turn in which an APNs callback could arrive unhooked.
        // Only when initialize() runs before the delegate exists (e.g. a SwiftUI App's
        // init) is the swizzle deferred to the next run-loop turn.
        if UIApplication.shared.delegate != nil {
            safeSwizzle()
        } else {
            Task { @MainActor in safeSwizzle() }
        }
    }

    // All ObjC runtime calls are here. If anything fails the SDK logs and moves on.
    // The host app will never crash from a swizzle failure.
    private static func safeSwizzle() {
        guard let cls = resolveAppDelegateClass() else {
            AppPushService.log("AppDelegate class not found. APNs token callbacks must be forwarded manually.", level: .warn)
            return
        }
        AppPushService.log("AppDelegate hooks installed on \(NSStringFromClass(cls)).", level: .debug)

        // Which callbacks iOS already sends to the delegate, checked before swizzling (see below).
        let delegateSelectors = [
            #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
            #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
            #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)),
        ]
        let delegateHadAll = delegateSelectors.allSatisfy {
            UIApplication.shared.delegate?.responds(to: $0) ?? true
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
            let rawCls: AnyClass = hookClass(of: rawDelegate)
            silentPushTarget = (rawCls !== cls) ? rawCls : cls
        } else {
            silentPushTarget = cls
        }
        swizzleSilentPush(in: silentPushTarget)

        // UIKit checks which callbacks the delegate implements when the delegate is assigned,
        // and caches it. The delegate is always assigned before this runs, so a method the
        // swizzle *added* (one the AppDelegate didn't declare) is never called: no APNs token.
        // Reassigning the delegate makes UIKit check again, as Firebase does. The token arrives
        // asynchronously after registerForRemoteNotifications(), so this is in time.
        // UIApplication.delegate is `assign`: the AppDelegate UIApplicationMain created is owned
        // by UIApplication only until the property is set again, so setting it frees the
        // AppDelegate and later reads crash. Hold it for the app's lifetime, as Firebase does.
        if !delegateHadAll, let delegate = UIApplication.shared.delegate {
            appDelegate = delegate
            UIApplication.shared.delegate = nil
            UIApplication.shared.delegate = delegate
        }

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
    //
    // object_getClass, not type(of:): Swift's type(of:) hides artificial subclasses, such as the
    // GUL_<AppDelegate> subclass Firebase (GoogleUtilities) isa-swizzles the delegate into. Firebase
    // Auth installs that subclass at launch with its own APNs methods, which call only the IMPs
    // the AppDelegate had at that moment. Methods added to the base class afterwards are never
    // reached, so no APNs token. Swizzling the real isa class wraps Firebase's method instead,
    // and the original-IMP chaining in install() still forwards the callback to Firebase.
    private static func resolveAppDelegateClass() -> AnyClass? {
        guard let delegate = UIApplication.shared.delegate else { return nil }
        let cls: AnyClass = hookClass(of: delegate)
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

    /// The object's real isa class (see resolveAppDelegateClass), except KVO's
    /// NSKVONotifying_ subclass: it is torn down when observation stops, which would take
    /// the hooks with it, so use the class it stands in for.
    private static func hookClass(of object: AnyObject) -> AnyClass {
        guard let isaCls = object_getClass(object),
              !NSStringFromClass(isaCls).hasPrefix("NSKVONotifying_") else {
            return type(of: object)
        }
        return isaCls
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

        // No other implementation: the SDK handles the silent push and calls completion.
        // Another implementation (the host's, or Firebase's AppDelegate proxy):
        //   - not an AppsOnAir push → the original alone handles it and calls completion.
        //   - an AppsOnAir push → both handle it. Without this, an app with Firebase Auth never
        //     delivered AppsOnAir silent pushes: Firebase's proxy method calls only what the
        //     AppDelegate itself implemented. iOS gets one completion once both are done.
        let block: @convention(block) (AnyObject, UIApplication, [AnyHashable: Any], @escaping (UIBackgroundFetchResult) -> Void) -> Void = { obj, app, userInfo, completion in
            guard let orig = originalDidReceiveRemoteNotificationIMP else {
                MainActor.assumeIsolated {
                    AppPushService.handleSilentPush(userInfo, fetchCompletionHandler: completion)
                }
                return
            }
            let callOriginal = { (done: @escaping (UIBackgroundFetchResult) -> Void) in
                unsafeBitCast(orig, to: DidReceiveRemoteNotifFunc.self)(obj, sel, app, userInfo, done)
            }
            guard isAppsOnAirPush(userInfo) else {
                callOriginal(completion)
                return
            }
            let merged = MergedFetchCompletion(expected: 2, completion: completion)
            MainActor.assumeIsolated {
                AppPushService.handleSilentPush(userInfo, fetchCompletionHandler: merged.complete)
            }
            callOriginal(merged.complete)
        }
        // "v@:@@?" — void; self; sel; UIApplication*; NSDictionary*; completion block
        install(imp: imp_implementationWithBlock(block), selector: sel, in: cls, typeEncoding: "v@:@@?", original: &originalDidReceiveRemoteNotificationIMP)
    }

    /// AppsOnAir pushes carry a notification_id (see AppPushService.enqueueSilentPushDelivered).
    private static func isAppsOnAirPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo["notification_id"] as? String)?.isEmpty == false
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
            // Method added to this class (wasn't defined directly on it).
            // Preserve the superclass IMP so framework base classes like
            // FlutterAppDelegate stay in the chain — without this, cross-platform
            // frameworks that implement the method on a superclass would be
            // silently skipped (original = nil breaks their chain).
            // For plain native apps the superclass won't have the method either,
            // so original stays nil and behaviour is identical to before.
            if let superCls = cls.superclass(),
               let method = class_getInstanceMethod(superCls, selector) {
                original = method_getImplementation(method)
            } else {
                original = nil
            }
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

// MARK: - MergedFetchCompletion

/// Calls a silent push's completion handler once, after `expected` handlers have each reported,
/// with the most useful result (newData over noData over failed). iOS allows about 30 s, so if a
/// handler never reports, it completes with what it has after 25 s.
private final class MergedFetchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var result: UIBackgroundFetchResult = .failed
    private var completion: ((UIBackgroundFetchResult) -> Void)?

    init(expected: Int, completion: @escaping (UIBackgroundFetchResult) -> Void) {
        remaining = expected
        self.completion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in finish() }
    }

    func complete(_ value: UIBackgroundFetchResult) {
        lock.lock()
        if value == .newData || (value == .noData && result == .failed) { result = value }
        remaining -= 1
        let done = remaining <= 0
        lock.unlock()
        if done { finish() }
    }

    private func finish() {
        lock.lock()
        let pending = completion
        completion = nil
        let value = result
        lock.unlock()
        pending?(value)
    }
}
