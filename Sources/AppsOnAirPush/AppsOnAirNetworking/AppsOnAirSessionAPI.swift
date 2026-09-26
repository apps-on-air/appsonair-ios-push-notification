import Foundation
#if SWIFT_PACKAGE
import AppsOnAir_AppPush_Shared
#endif

// MARK: - AppsOnAirSessionAPI
//
// Thin transport for the /v1/sessions endpoints (see
// docs/Session Tracking API — contract for SDK review.md). This type ONLY
// builds and sends the request and hands the raw URLSession result back to
// the caller — it does not interpret the response or decide retry policy.
// AppsOnAirSessionManager owns that.
//
//   POST <EnvironmentConfig.startSession>   (…/v1/sessions)
//   Sent when the app returns to foreground after being backgrounded for more
//   than the SDK's foreground threshold. The register response (/v1/subscriptions)
//   already starts the first session of a launch, so this is only for a
//   returning app.
//   Headers:
//     X-App-Id:      <configured appId>
//     X-SDK-Version: <AppsOnAirDeviceInfo.sdkVersion>
//     X-Platform:    ios
//     Content-Type:  application/json
//   Body:
//     { subscription_id }
//   Response — 200:
//     { sessionId, startedAt, sessionCount }
//
//   PATCH <EnvironmentConfig.sessionById><sessionId>   (…/v1/sessions/<id>)
//   Sent when the app enters background, to close the currently open session.
//   Headers: same four as POST
//   Body (exact backend contract — see curl sample):
//     { subscription_id, ended_at }   // epoch seconds
//   Response — 200:
//     { sessionId, startedAt, endedAt, durationSec, counted }
//   Safe to retry — a duplicate close returns `counted: false` instead of
//   double-counting.

@MainActor
enum AppsOnAirSessionAPI {

    /// Send POST /v1/sessions and return the raw result on the main actor.
    ///
    /// `completion` receives `(Data?, URLResponse?, Error?)` exactly as URLSession
    /// produced it — the caller (`AppsOnAirSessionManager`) parses `sessionId`
    /// from the body. When the request cannot even be built (no
    /// subscriptionId, bad URL, encode failure) the completion is called with
    /// all-nil.
    static func startSession(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            AppPushService.log("SessionAPI: no subscriptionId — start session not sent", level: .debug)
            completion(nil, nil, nil)
            return
        }
        guard let url = URL(string: EnvironmentConfig.startSession) else {
            AppPushService.log("SessionAPI: invalid endpoint URL '\(EnvironmentConfig.startSession)'", level: .error)
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["subscription_id": subscriptionId]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            AppPushService.log("SessionAPI: failed to serialize start session body", level: .error)
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion,  forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                           forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        AppPushService.log("SessionAPI: POST /v1/sessions subscriptionId=\(subscriptionId)", level: .debug)

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            AppPushService.log("SessionAPI: POST /v1/sessions HTTP \(status) response=\(text)", level: .debug)
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/sessions/<sessionId> and return the raw result on the main actor.
    ///
    /// Mirrors `startSession` — this ONLY builds and sends the request. The body
    /// is exactly `{ subscription_id, ended_at }` (backend contract — see curl
    /// sample). When the request cannot be built (no subscriptionId, bad URL,
    /// encode failure) the completion is called with all-nil.
    static func endSession(
        sessionId: String,
        endedAt: TimeInterval,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard !sessionId.isEmpty else {
            AppPushService.log("SessionAPI: empty sessionId — end session not sent", level: .warn)
            completion(nil, nil, nil)
            return
        }
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            AppPushService.log("SessionAPI: no subscriptionId — end session not sent", level: .debug)
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.sessionById + sessionId
        guard let url = URL(string: endpoint) else {
            AppPushService.log("SessionAPI: invalid endpoint URL '\(endpoint)'", level: .error)
            completion(nil, nil, nil)
            return
        }

        // `endedAt` arrives as a `TimeInterval` (seconds since 1970, e.g. from
        // `Date().timeIntervalSince1970`) — `Int(endedAt)` truncates the
        // fractional part, giving whole epoch seconds as the backend contract
        // requires (NOT milliseconds).
        let endedAtEpochSeconds = Int(endedAt)
        let body: [String: Any] = [
            "subscription_id": subscriptionId,
            "ended_at":        endedAtEpochSeconds
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            AppPushService.log("SessionAPI: failed to serialize end session body", level: .error)
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion,  forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                           forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        AppPushService.log(
            "SessionAPI: PATCH /v1/sessions/\(sessionId) endedAt=\(endedAtEpochSeconds)",
            level: .debug
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            AppPushService.log("SessionAPI: PATCH /v1/sessions/\(sessionId) HTTP \(status) response=\(text)", level: .debug)
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }
}
