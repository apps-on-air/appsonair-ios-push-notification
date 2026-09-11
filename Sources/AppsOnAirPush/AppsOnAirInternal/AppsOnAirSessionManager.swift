import Foundation
import UIKit

// MARK: - AppsOnAirSessionManager
//
// Tracks app session lifecycle for MAU metering and segment filter data.
// Observes UIApplication foreground/background transitions via NotificationCenter.
//
// Scope §3.9: MAU = a user with ≥1 session in trailing 30 days.
// Scope §3.2: Segment filters — first_session, last_session, session_count, session_time.
//
// Session data is persisted in UserDefaults and included in the registration/update
// payload sent to the backend on every session start.
//
// USAGE: Called once from AppsOnAirPush.initialize().

@MainActor
final class AppsOnAirSessionManager {

    static let shared = AppsOnAirSessionManager()

    private let keyFirstSession = "com.appsonair.push.firstSession"   // epoch Double
    private let keyLastSession  = "com.appsonair.push.lastSession"    // epoch Double
    private let keySessionCount = "com.appsonair.push.sessionCount"   // Int
    private let keyTotalTime    = "com.appsonair.push.totalSessionTime" // TimeInterval (seconds)

    private var sessionStartTime: Date? = nil

    // MARK: - Computed accessors (read from UserDefaults)

    var firstSession: Date? {
        let ts = UserDefaults.standard.double(forKey: keyFirstSession)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    var lastSession: Date? {
        let ts = UserDefaults.standard.double(forKey: keyLastSession)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    /// Number of times the app has been foregrounded (all time).
    var sessionCount: Int { UserDefaults.standard.integer(forKey: keySessionCount) }

    /// Cumulative foreground time in seconds across all sessions.
    var totalSessionTime: TimeInterval { UserDefaults.standard.double(forKey: keyTotalTime) }

    private init() {}

    // MARK: - Start

    /// Register for UIApplication lifecycle notifications and record the launch as a session.
    /// Call once from AppsOnAirPush.initialize().
    func start() {
        let center = NotificationCenter.default

        // didBecomeActive fires on first launch AND every time the app returns from background.
        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordSessionStart() }
        }

        // didEnterBackground fires when the user presses Home or switches apps.
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recordSessionEnd() }
        }

        // configure() is called at launch — count as the first session start immediately.
        // (didBecomeActive will also fire shortly after, but start() may be called before it.)
        recordSessionStart()
        AppsOnAirPush.log(
            "SessionManager: started. sessionCount=\(sessionCount) " +
            "firstSession=\(firstSession.map { "\($0)" } ?? "nil")",
            level: .debug
        )
    }

    // MARK: - Session events (private)

    private func recordSessionStart() {
        let now = Date()
        // Avoid double-counting if didBecomeActive fires right after start()
        if let previous = sessionStartTime, Date().timeIntervalSince(previous) < 2 { return }
        sessionStartTime = now

        // Record first_session on very first app launch.
        if UserDefaults.standard.double(forKey: keyFirstSession) == 0 {
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: keyFirstSession)
            AppsOnAirPush.log("SessionManager: first session recorded.", level: .info)
        }

        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: keyLastSession)
        let count = UserDefaults.standard.integer(forKey: keySessionCount) + 1
        UserDefaults.standard.set(count, forKey: keySessionCount)

        AppsOnAirPush.log(
            "SessionManager: session started. count=\(count)",
            level: .debug
        )

        // Enqueue a session ping so the backend can count this as a MAU event.
        // Also flush any pending events (opened, clicked, delivered) from previous sessions.
        // TODO: API — POST /sessions (see AppsOnAirEventQueue.sendSessionPing)
        AppsOnAirEventQueue.shared.enqueue(PushEvent(
            type: .sessionStart,
            subscriptionId: AppsOnAirPush.subscriptionId
        ))
        AppsOnAirEventQueue.shared.flush()
    }

    private func recordSessionEnd() {
        guard let start = sessionStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        sessionStartTime = nil

        let total = UserDefaults.standard.double(forKey: keyTotalTime) + duration
        UserDefaults.standard.set(total, forKey: keyTotalTime)

        AppsOnAirPush.log(
            "SessionManager: session ended. duration=\(Int(duration))s totalTime=\(Int(total))s",
            level: .debug
        )
    }

    // MARK: - Payload snapshot

    /// All session fields as a dictionary for inclusion in registration/update payloads.
    func asPayloadDict() -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "session_count":    sessionCount,
            "session_time_sec": Int(totalSessionTime)
        ]
        if let first = firstSession { dict["first_session"] = iso.string(from: first) }
        if let last  = lastSession  { dict["last_session"]  = iso.string(from: last)  }
        return dict
    }
}
