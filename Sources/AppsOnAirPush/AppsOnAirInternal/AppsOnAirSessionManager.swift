import Foundation
import UIKit

// MARK: - AppsOnAirSessionManager
//
// Owns the SDK-side session lifecycle per the Session Tracking API contract
// (docs/Session Tracking API — contract for SDK review.md). The backend never
// closes a session on its own — no timeout, no reaper — so the SDK alone
// decides when a session starts and ends, from UIApplication foreground/
// background transitions:
//
//   • App backgrounds → PATCH /v1/sessions/{id} (End Session) using the
//     currently stored sessionId, with "now" as endedAt.
//   • App foregrounds → if the app was backgrounded for more than
//     `foregroundThreshold`, POST /v1/sessions (Start Session) for a fresh
//     session and replace the stored sessionId; otherwise the
//     existing session carries on untouched — no call.
//
// The first session of a launch comes from the /v1/subscriptions register
// response, which already starts a session — see `adopt(sessionId:)`,
// called from AppPushService once that response is parsed. This manager only
// reacts to backgrounding/foregrounding after that.
//
// Reopen cleanup: if a `sessionId` survives from a previous run (the app was
// killed/crashed while backgrounded, so its End Session PATCH never landed),
// `endStaleSessionIfNeeded(completion:)` closes it before the new launch
// registers — see `AppPushService.registerSubscriptionIfReady`.
//
// USAGE: `start()` called once from AppPushService.initialize().

@MainActor
final class AppsOnAirSessionManager {

    static let shared = AppsOnAirSessionManager()

    /// Background time under which a return to foreground reuses the existing
    /// session instead of starting a new one (Session Tracking API contract).
    private let foregroundThreshold: TimeInterval = 30

    /// Timestamp of the most recent `didEnterBackground`. Cleared once consumed
    /// on the next `didBecomeActive`, so a cold launch's first activation (where
    /// this is nil) is never mistaken for a background return.
    private var backgroundedAt: Date?

    /// Background task assertion started on `didEnterBackground` so the End
    /// Session PATCH gets a few extra seconds to leave the device before iOS
    /// suspends the process.
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    // MARK: - Eye-catching milestone log
    //
    // Session start/end are the events worth spotting at a glance while
    // scrolling a noisy console, so they get '='-ruled banners instead of a
    // plain `AppPushService.log` line.
    //   ============================================================
    //   [SessionManager] ★ SESSION STARTED
    //   sessionId=...
    //   ============================================================
    private static func logMilestone(_ title: String, _ detail: String) {
        let divider = String(repeating: "=", count: 60)
        print(divider)
        print("[SessionManager] ★ \(title)")
        print(detail)
        print(divider)
    }

    // MARK: - Start

    /// Register for UIApplication background/foreground notifications.
    /// Call once from AppPushService.initialize().
    func start() {
        let center = NotificationCenter.default

        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleDidEnterBackground() }
        }

        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleDidBecomeActive() }
        }

        AppPushService.log("SessionManager: started.", level: .debug)
    }

    // MARK: - Adopt a session

    /// Persist a session the backend handed back — the `/v1/subscriptions`
    /// register response, or a `POST /v1/sessions` response. Replaces whatever
    /// session was stored before.
    func adopt(sessionId: String) {
        guard !sessionId.isEmpty else { return }
        AppPushService.shared.storage.saveSession(id: sessionId)
        Self.logMilestone("SESSION STARTED", "sessionId=\(sessionId)")
    }

    // MARK: - Reopen cleanup

    /// Close a session left open from a previous run before this launch
    /// registers and opens a new one — a leftover `sessionId` means the app
    /// was killed/crashed while backgrounded, so `handleDidEnterBackground`'s
    /// End Session PATCH never fired (or never landed). `completion` always
    /// runs, whether or not there was a stale session to close, so the caller
    /// can chain the register call unconditionally.
    func endStaleSessionIfNeeded(completion: @escaping @MainActor () -> Void) {
        guard let staleSessionId = AppPushService.shared.storage.sessionId, !staleSessionId.isEmpty else {
            completion()
            return
        }

        AppPushService.log(
            "SessionManager: stale session \(staleSessionId) found on reopen — ending before register.",
            level: .debug
        )
        AppsOnAirSessionAPI.endSession(
            sessionId: staleSessionId,
            endedAt: Date().timeIntervalSince1970
        ) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error {
                AppPushService.log("SessionManager: stale session end error: \(error.localizedDescription)", level: .warn)
            } else {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Self.logMilestone("STALE SESSION ENDED", "sessionId=\(staleSessionId) status=\(status) response=\(bodyText)")
            }
            completion()
        }
    }

    // MARK: - Lifecycle handlers

    /// App entered background — stamp the moment and close the open session, if any.
    private func handleDidEnterBackground() {
        backgroundedAt = Date()

        guard let sessionId = AppPushService.shared.storage.sessionId else {
            AppPushService.log("SessionManager: no active session to end on background.", level: .debug)
            return
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "AppsOnAirEndSession") { [weak self] in
            self?.finishBackgroundTask()
        }

        let endedAt = Date().timeIntervalSince1970
        AppPushService.log("SessionManager: app backgrounded — ending session \(sessionId).", level: .debug)

        AppsOnAirSessionAPI.endSession(
            sessionId: sessionId,
            endedAt: endedAt
        ) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let error {
                AppPushService.log("SessionManager: end session error: \(error.localizedDescription)", level: .warn)
            } else {
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                Self.logMilestone("SESSION ENDED", "sessionId=\(sessionId) status=\(status) response=\(bodyText)")
            }
            self?.finishBackgroundTask()
        }
    }

    /// App returned to foreground — decide whether the elapsed background time
    /// warrants a fresh session, per the Session Tracking API contract.
    private func handleDidBecomeActive() {
        defer { backgroundedAt = nil }

        // Drain any opened/clicked/delivered events queued while the app was
        // backgrounded (or before this launch's first activation) — see
        // AppsOnAirEventQueue's "flush on session start / app foreground" contract.
        AppsOnAirEventQueue.shared.flush()

        guard let backgroundedAt else {
            // Cold launch: the register (or a queued start-session) call already
            // opened this launch's session — nothing to reconcile here.
            return
        }

        let elapsed = Date().timeIntervalSince(backgroundedAt)
        guard elapsed > foregroundThreshold else {
            AppPushService.log(
                "SessionManager: foregrounded after \(Int(elapsed))s — reusing existing session.",
                level: .debug
            )
            return
        }

        AppPushService.log(
            "SessionManager: foregrounded after \(Int(elapsed))s — starting a new session.",
            level: .debug
        )

        AppsOnAirNetworkMonitor.runWhenConnected {
            AppsOnAirSessionAPI.startSession { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                if let error {
                    AppPushService.log("SessionManager: start session error: \(error.localizedDescription)", level: .warn)
                    return
                }
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                AppPushService.log("SessionManager: start session HTTP \(status): \(bodyText)", level: .info)

                guard (200..<300).contains(status),
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessionId = json["sessionId"] as? String, !sessionId.isEmpty else {
                    AppPushService.log(
                        "SessionManager: start session response missing sessionId — keeping previous session.",
                        level: .warn
                    )
                    return
                }

                AppPushService.shared.storage.clearSession()
                AppsOnAirSessionManager.shared.adopt(sessionId: sessionId)
            }
        }
    }

    private func finishBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
