import Foundation

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

    // MARK: - Eye-catching log block helper
    //
    // Wraps a request/response log in '='/'-' rules so it's easy to spot while
    // scrolling a noisy console.
    //   ============================================================
    //   [AppsOnAirSessionAPI] → START SESSION REQUEST
    //   ------------------------------------------------------------
    //   URL     : ...
    //   ============================================================
    nonisolated private static let logDivider = String(repeating: "=", count: 60)
    nonisolated private static let logRule = String(repeating: "-", count: 60)

    nonisolated private static func logBlock(_ title: String, _ lines: [String]) {
        print(logDivider)
        print("[AppsOnAirSessionAPI] \(title)")
        print(logRule)
        for line in lines { print(line) }
        print(logDivider)
    }

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
            print("[AppsOnAirSessionAPI] no subscriptionId — start session not sent")
            completion(nil, nil, nil)
            return
        }
        guard let url = URL(string: EnvironmentConfig.startSession) else {
            print("[AppsOnAirSessionAPI] invalid endpoint URL '\(EnvironmentConfig.startSession)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["subscription_id": subscriptionId]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSessionAPI] failed to serialize body")
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

        logBlock("→ START SESSION REQUEST", [
            "URL     : POST \(url.absoluteString)",
            "Headers : X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios",
            "Body    : \(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")"
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            logBlock("← START SESSION RESPONSE", [
                "Status  : HTTP \(status)",
                "Error   : \(error?.localizedDescription ?? "nil")",
                "Body    : \(text)"
            ])
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
            print("[AppsOnAirSessionAPI] empty sessionId — end session not sent")
            completion(nil, nil, nil)
            return
        }
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSessionAPI] no subscriptionId — end session not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.sessionById + sessionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSessionAPI] invalid endpoint URL '\(endpoint)'")
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
            print("[AppsOnAirSessionAPI] failed to serialize body")
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

        logBlock("→ END SESSION REQUEST", [
            "URL     : PATCH \(url.absoluteString)",
            "Headers : X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios",
            "Body    : \(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")",
            "EndedAt : \(endedAtEpochSeconds) (epoch seconds) — \(Date(timeIntervalSince1970: TimeInterval(endedAtEpochSeconds)))"
        ])

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            logBlock("← END SESSION RESPONSE", [
                "Status  : HTTP \(status)",
                "Error   : \(error?.localizedDescription ?? "nil")",
                "Body    : \(text)"
            ])
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }
}
