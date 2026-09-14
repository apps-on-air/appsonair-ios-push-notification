import Foundation
import BackgroundTasks

// MARK: - AppsOnAirBackgroundSync

/// Schedules and handles periodic **background fetch** tasks for the AppsOnAir Push SDK.
///
/// Uses `BGAppRefreshTask` (iOS 13 +, `BackgroundTasks` framework) to let the system
/// wake the app in the background so you can refresh push-related state (e.g. check
/// for queued messages, refresh a badge count, or ping your backend).
///
/// ## One-time setup
///
/// ### 1 — Info.plist
/// Add the task identifier to `BGTaskSchedulerPermittedIdentifiers`:
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///     <string>com.appsonair.push.background-sync</string>
/// </array>
/// ```
///
/// ### 2 — Xcode capability
/// Enable **Background Modes → Background fetch** (and optionally
/// **Background processing**) in *Signing & Capabilities*.
///
/// ### 3 — App launch
/// Call `registerHandlers()` **before** the app finishes launching.
/// For `@main` structs this means in `init()` or in the `Scene` delegate's
/// `scene(_:willConnectTo:options:)` — but _before_ the first `resume()`.
/// For UIKit apps call it in `application(_:didFinishLaunchingWithOptions:)`.
///
/// ```swift
/// // UIKit AppDelegate:
/// func application(_ application: UIApplication,
///                  didFinishLaunchingWithOptions ...) -> Bool {
///     AppsOnAirBackgroundSync.registerHandlers()
///     AppPushService.initialize()
///     AppsOnAirBackgroundSync.scheduleIfNeeded()
///     return true
/// }
///
/// // SwiftUI @main:
/// @main struct MyApp: App {
///     init() {
///         AppsOnAirBackgroundSync.registerHandlers()
///         AppPushService.initialize()
///         AppsOnAirBackgroundSync.scheduleIfNeeded()
///     }
/// }
/// ```
///
/// ### 4 — Handle sync work
/// ```swift
/// AppsOnAirBackgroundSync.onBackgroundSync = { completion in
///     // Perform your lightweight fetch here (≤ 30 s budget).
///     fetchLatestBadgeCount { newCount in
///         UIApplication.shared.applicationIconBadgeNumber = newCount
///         completion(true)   // pass true = new data fetched
///     }
/// }
/// ```
public final class AppsOnAirBackgroundSync {

    // MARK: - Public

    /// The BGTask identifier registered in `BGTaskSchedulerPermittedIdentifiers`.
    public static let taskIdentifier = "com.appsonair.push.background-sync"

    /// Set this closure to perform your sync work when the background task fires.
    ///
    /// - The closure is called on a **background thread** — dispatch to the main
    ///   thread yourself if you need to update UI (e.g. badge count).
    /// - You have a limited time budget (typically ≤ 30 s). Call `completion` as
    ///   soon as you are done — passing `true` if new data was fetched.
    /// - If you do not set this closure the task completes immediately with `false`.
    /// nonisolated(unsafe): set once at app start before any background task fires;
    /// no concurrent write can occur in normal usage.
    public nonisolated(unsafe) static var onBackgroundSync: ((_ completion: @escaping (_ newDataFetched: Bool) -> Void) -> Void)?

    /// Register `BGTask` handlers. **Must be called before the app finishes launching.**
    ///
    /// Safe to call multiple times — subsequent calls are no-ops.
    public static func registerHandlers() {
        guard !handlersRegistered else { return }
        handlersRegistered = true

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil          // nil = system-chosen queue (background thread)
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            AppsOnAirBackgroundSync.handle(refreshTask)
        }
    }

    /// Submit a `BGAppRefreshTaskRequest` so the system can schedule the next run.
    ///
    /// Call once after `registerHandlers()` and again at the end of each background
    /// task execution. The system chooses the actual wake time based on usage patterns
    /// and battery/network conditions — `earliestBeginDate` is only a lower bound.
    ///
    /// - Parameter minimumDelay: Earliest the task may run again. Defaults to 15 min.
    public static func scheduleIfNeeded(minimumDelay: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumDelay)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Common non-fatal errors:
            // • BGTaskScheduler.Error.notPermitted  — missing Info.plist key or capability
            // • BGTaskScheduler.Error.tooManyPendingTaskRequests — already queued
            // Both are safe to ignore silently.
        }
    }

    /// Cancel any pending background sync request. Call if the user logs out or
    /// your app no longer needs background fetch.
    public static func cancelPending() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    // MARK: - Private

    // nonisolated(unsafe): written once from app-launch code (always before any BG task fires).
    private nonisolated(unsafe) static var handlersRegistered = false

    private static func handle(_ task: BGAppRefreshTask) {
        // Reschedule first — iOS cancels pending requests when the task fires.
        scheduleIfNeeded()

        // Expiration handler: time budget is exhausted → mark failed and bail.
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        guard let handler = onBackgroundSync else {
            task.setTaskCompleted(success: false)
            return
        }

        handler { newDataFetched in
            task.setTaskCompleted(success: newDataFetched)
        }
    }
}
