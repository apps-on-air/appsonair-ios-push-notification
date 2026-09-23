import Foundation
#if SWIFT_PACKAGE
import AppsOnAir_AppPush_Shared
#endif

// MARK: - AppsOnAirSubscriptionAPI
//
// Thin transport for the /v1/subscriptions endpoints. This type ONLY builds and
// sends the request and hands the raw URLSession result back to the caller. It
// does not interpret the response, retry, dedupe, or track state — the caller
// (AppPushService) owns all of that.
//
//   POST <EnvironmentConfig.registerDevice>   (…/v1/subscriptions)
//   Headers:
//     X-App-Id:      <configured appId>
//     X-SDK-Version: <AppsOnAirDeviceInfo.sdkVersion>
//     X-Platform:    ios
//     Content-Type:  application/json
//   Body (exact backend contract — see curl sample):
//     app_id, device_id, platform, push_token, apns_environment, enabled,
//     sdk_version, app_version, build_number, device_model, os_version,
//     timezone, language, is_jailbroken
//   Response (handled by the caller):
//     { "subscriptionId": "<uuid>" }
//
//   PATCH <EnvironmentConfig.subscriptionById><subscriptionId>   (…/v1/subscriptions/<id>)
//   Headers: same four as POST
//   Body (exact backend contract — see curl sample):
//     { "enabled": <Bool> }   // mirrors the current notification-permission status
//
//   PATCH <EnvironmentConfig.subscriptionById><subscriptionId>   (…/v1/subscriptions/<id>)
//   Sent when the APNs push token refreshes / rotates.
//   Headers: same four as POST
//   Body (exact backend contract — see curl sample):
//     { push_token, os_version, app_version, language, timezone }
//
//   PATCH <EnvironmentConfig.subscriptionById><subscriptionId>   (…/v1/subscriptions/<id>)
//   Sent on login() / logout() to link or unlink the identified user.
//   Headers: same four as POST
//   Body (exact backend contract — see curl sample):
//     { "external_id": <String> }   // JSON null clears it (logout)
//
//   PATCH <EnvironmentConfig.subscriptionById><subscriptionId>   (…/v1/subscriptions/<id>)
//   Sent on User.addEmail() / User.removeEmail() to sync the current email list.
//   Headers: same four as POST
//   Body (exact backend contract — see curl sample):
//     { "emails": [ <String>, … ] }   // full current list; empty array clears all
//
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/alias   (…/v1/subscriptions/<id>/alias)
//   Sent on User.addAlias() / User.addAliases() to sync this subscription's alias map.
//   Headers: same four as the POST above (Content-Type: application/json)
//   Body (exact backend contract — identical to tags POST):
//     [ { "key": <String>, "value": <String> }, … ]
//
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/alias/remove   (…/v1/subscriptions/<id>/alias/remove)
//   Sent on User.removeAlias() / User.removeAliases() to drop labels from this
//   subscription's alias map.
//   Headers: same four as the POST above (Content-Type: application/json)
//   Body (exact backend contract — identical to tags/remove POST):
//     { "keys": [ <String>, … ] }   // one entry per alias key to remove
//
//   GET <EnvironmentConfig.subscriptionById><subscriptionId>/alias   (…/v1/subscriptions/<id>/alias)
//   Sent on alias fetch to refresh the local alias cache from the backend.
//   Headers: X-App-Id, X-SDK-Version, X-Platform (no Content-Type — no body)
//   Body: none. Response parsed by `parseAliasResponse`.
//
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/opt-in    (…/v1/subscriptions/<id>/opt-in)
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/opt-out   (…/v1/subscriptions/<id>/opt-out)
//   Sent on User.pushSubscription.optIn() / optOut() to match the backend
//   subscription's opt-in state to the SDK's local state.
//   Headers: X-App-Id, X-SDK-Version, X-Platform (no Content-Type — no body)
//   Body: none — the path segment is the whole contract (see curl sample)
//
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/tags   (…/v1/subscriptions/<id>/tags)
//   Sent on User.addTag() / User.addTags() to sync this subscription's tag set.
//   Headers: same four as the POST above (Content-Type: application/json)
//   Body (exact backend contract — see curl sample):
//     [ { "key": <String>, "value": <String> }, … ]   // one object per tag
//
//   POST <EnvironmentConfig.subscriptionById><subscriptionId>/tags/remove   (…/v1/subscriptions/<id>/tags/remove)
//   Sent on User.removeTag() / User.removeTags() to drop keys from this
//   subscription's tag set.
//   Headers: same four as the POST above (Content-Type: application/json)
//   Body (exact backend contract — see curl sample):
//     { "keys": [ <String>, … ] }   // one entry per tag key to remove
//
//   GET <EnvironmentConfig.subscriptionById><subscriptionId>/tags   (…/v1/subscriptions/<id>/tags)
//   Sent on User.getTags() to refresh the local tag cache from the backend.
//   Headers: X-App-Id, X-SDK-Version, X-Platform (no Content-Type — no body)
//   Body: none. Response is parsed by `parseTagsResponse` — tolerant of an
//   array of { "key", "value" }, a { "tags": … } wrapper, or a flat map.
//
//   PATCH <EnvironmentConfig.subscriptionById><subscriptionId>/language   (…/v1/subscriptions/<id>/language)
//   Sent on User.setLanguage() to sync the language override to this subscription.
//   Headers: same four as the POST above (Content-Type: application/json)
//   Body (exact backend contract — see curl sample):
//     { "language": <String> }   // e.g. "en-US"
//
//   DELETE <EnvironmentConfig.subscriptionById><subscriptionId>   (…/v1/subscriptions/<id>)
//   Sent on logout() to remove the backend subscription tied to the now-logged-out
//   user. On success the caller registers a fresh, anonymous subscription in its
//   place (POST /v1/subscriptions).
//   Headers: X-App-Id, X-SDK-Version, X-Platform (no Content-Type — no body)
//   Body: none — see curl sample

@MainActor
enum AppsOnAirSubscriptionAPI {

    /// Send POST /v1/subscriptions and return the raw result on the main actor.
    ///
    /// `completion` receives `(Data?, URLResponse?, Error?)` exactly as URLSession
    /// produced it — the caller parses status / body / `subscriptionId`. When the
    /// request cannot even be built (no push token, bad URL, encode failure) the
    /// completion is called with all-nil.
    static func registerDevice(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let token = AppPushService.shared.storage.getApnsToken(), !token.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no push token — request not sent")
            completion(nil, nil, nil)
            return
        }
        guard let url = URL(string: EnvironmentConfig.registerDevice) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(EnvironmentConfig.registerDevice)'")
            completion(nil, nil, nil)
            return
        }

        let body = subscriptionBody(pushToken: token)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/subscriptions/<subscriptionId> and return the raw result on
    /// the main actor.
    ///
    /// Mirrors `registerDevice` — this ONLY builds and sends the request. The body
    /// is exactly `{ "enabled": <enabled> }`, where `enabled` is the caller's view
    /// of the current notification-permission status (`true` when granted, `false`
    /// otherwise). When the request cannot be built (no `subscriptionId`, bad URL,
    /// encode failure) the completion is called with all-nil.
    static func updateSubscription(
        enabled: Bool,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["enabled": enabled]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → PATCH \(url.absoluteString)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/subscriptions/<subscriptionId> with the rotated push token
    /// and return the raw result on the main actor.
    ///
    /// Mirrors `updateSubscription` — this ONLY builds and sends the request. The
    /// body is exactly `{ push_token, os_version, app_version, language, timezone }`
    /// (backend contract — see curl sample), where `push_token` is the current
    /// stored APNs token. When the request cannot be built (no push token, no
    /// `subscriptionId`, bad URL, encode failure) the completion is called with
    /// all-nil.
    static func updatePushToken(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let token = AppPushService.shared.storage.getApnsToken(), !token.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no push token — token PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — token PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body = pushTokenBody(pushToken: token)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → PATCH \(url.absoluteString) (token rotation)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/subscriptions/<subscriptionId> with the identified user's
    /// external ID and return the raw result on the main actor.
    ///
    /// Mirrors `updateSubscription` — this ONLY builds and sends the request. The
    /// body is exactly `{ "external_id": <externalId> }` (backend contract — see
    /// curl sample). Pass `nil` on logout: it serializes as JSON `null`, telling
    /// the backend to unlink the user. When the request cannot be built (no
    /// `subscriptionId`, bad URL, encode failure) the completion is called with
    /// all-nil.
    static func updateExternalId(
        _ externalId: String?,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — external_id PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["external_id": externalId ?? NSNull()]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → PATCH \(url.absoluteString) (external_id)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/subscriptions/<subscriptionId>/opt-in (when `optedOut` is
    /// `false`) or …/opt-out (when `true`) and return the raw result on the main
    /// actor.
    ///
    /// Mirrors `updateSubscription` — this ONLY builds and sends the request.
    /// There is no request body: the path segment is the whole backend contract
    /// (see curl sample), so no `Content-Type` header is set. When the request
    /// cannot be built (no `subscriptionId`, bad URL) the completion is called
    /// with all-nil.
    static func updateOptInState(
        optedOut: Bool,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — opt-in/opt-out not sent")
            completion(nil, nil, nil)
            return
        }
        let action = optedOut ? "opt-out" : "opt-in"
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/" + action
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString) (\(action))")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/subscriptions/<subscriptionId>/tags with the SDK's current
    /// tag set and return the raw result on the main actor.
    ///
    /// Mirrors `updateSubscription` — this ONLY builds and sends the request. The
    /// body is the exact backend contract (see curl sample): a JSON array of
    /// `{ "key": <k>, "value": <v> }` objects, one per tag. When the request
    /// cannot be built (no `subscriptionId`, no tags, bad URL, encode failure)
    /// the completion is called with all-nil.
    static func updateTags(
        _ tags: [String: String],
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — tags POST not sent")
            completion(nil, nil, nil)
            return
        }
        guard !tags.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no tags — tags POST not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/tags"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body = tagsBody(tags: tags)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString) (tags)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/subscriptions/<subscriptionId>/tags/remove with the tag keys
    /// to drop and return the raw result on the main actor.
    ///
    /// Mirrors `updateTags` — this ONLY builds and sends the request. The body is
    /// the exact backend contract (see curl sample): `{ "keys": [ <k>, … ] }`.
    /// When the request cannot be built (no `subscriptionId`, no keys, bad URL,
    /// encode failure) the completion is called with all-nil.
    static func removeTags(
        _ keys: [String],
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — tags/remove POST not sent")
            completion(nil, nil, nil)
            return
        }
        guard !keys.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no keys — tags/remove POST not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/tags/remove"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body = tagRemovalBody(keys: keys)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString) (tags/remove)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send GET /v1/subscriptions/<subscriptionId>/tags and return the raw result
    /// on the main actor.
    ///
    /// Mirrors `updateOptInState` — this ONLY builds and sends the request. There
    /// is no request body, so no `Content-Type` header is set. The caller parses
    /// the response with `parseTagsResponse`. When the request cannot be built
    /// (no `subscriptionId`, bad URL) the completion is called with all-nil.
    static func fetchTags(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — tags GET not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/tags"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")

        print("[AppsOnAirSubscriptionAPI] → GET \(url.absoluteString) (tags)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/subscriptions/<subscriptionId>/language with the language
    /// override and return the raw result on the main actor.
    ///
    /// Mirrors `updateSubscription` — this ONLY builds and sends the request. The
    /// body is exactly `{ "language": <language> }` (backend contract — see curl
    /// sample). When the request cannot be built (no `subscriptionId`, empty
    /// `language`, bad URL, encode failure) the completion is called with all-nil.
    static func updateLanguage(
        _ language: String,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — language PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        guard !language.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] empty language — language PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/language"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["language": language]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → PATCH \(url.absoluteString) (language)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send DELETE /v1/subscriptions/<subscriptionId> and return the raw result on
    /// the main actor.
    ///
    /// Mirrors `updateOptInState` — this ONLY builds and sends the request. There
    /// is no request body, so no `Content-Type` header is set. When the request
    /// cannot be built (no `subscriptionId`, bad URL) the completion is called
    /// with all-nil.
    static func deleteSubscription(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — DELETE not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")

        print("[AppsOnAirSubscriptionAPI] → DELETE \(url.absoluteString)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send PATCH /v1/subscriptions/<subscriptionId> with the current email list and
    /// return the raw result on the main actor.
    ///
    /// Mirrors `updateExternalId` — this ONLY builds and sends the request. The body
    /// is exactly `{ "emails": <emails> }` (backend contract). An empty array clears
    /// all emails from the subscription. When the request cannot be built (no
    /// `subscriptionId`, bad URL, encode failure) the completion is called with all-nil.
    static func updateEmail(
        _ emails: [String],
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — email PATCH not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = ["emails": emails]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → PATCH \(url.absoluteString) (emails)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/subscriptions/<subscriptionId>/alias with the SDK's current
    /// alias map and return the raw result on the main actor.
    ///
    /// Mirrors `updateTags` — this ONLY builds and sends the request. The body is
    /// the exact backend contract: `{ "alias": [ { "label": <l>, "id": <i> }, … ] }`.
    /// When the request cannot be built (no `subscriptionId`, no aliases, bad URL,
    /// encode failure) the completion is called with all-nil.
    static func updateAliases(
        _ aliases: [String: String],
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — alias POST not sent")
            completion(nil, nil, nil)
            return
        }
        guard !aliases.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no aliases — alias POST not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/alias"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body = aliasBody(aliases: aliases)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString) (alias)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/subscriptions/<subscriptionId>/alias/remove with the alias
    /// labels to drop and return the raw result on the main actor.
    ///
    /// Mirrors `removeTags` — this ONLY builds and sends the request. The body is
    /// the exact backend contract: `{ "labels": [ <l>, … ] }`. When the request
    /// cannot be built (no `subscriptionId`, no labels, bad URL, encode failure)
    /// the completion is called with all-nil.
    static func removeAliases(
        _ labels: [String],
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — alias/remove POST not sent")
            completion(nil, nil, nil)
            return
        }
        guard !labels.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no labels — alias/remove POST not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/alias/remove"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        let body = aliasRemovalBody(labels: labels)
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirSubscriptionAPI] failed to serialize body")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json",             forHTTPHeaderField: "Content-Type")
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")
        request.httpBody = httpBody

        print("[AppsOnAirSubscriptionAPI] → POST \(url.absoluteString) (alias/remove)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirSubscriptionAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send GET /v1/subscriptions/<subscriptionId>/alias and return the raw result
    /// on the main actor.
    ///
    /// Mirrors `fetchTags` — this ONLY builds and sends the request. There is no
    /// request body, so no `Content-Type` header is set. The caller parses the
    /// response with `parseAliasResponse`. When the request cannot be built
    /// (no `subscriptionId`, bad URL) the completion is called with all-nil.
    static func fetchAliases(
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let subscriptionId = AppPushService.subscriptionId, !subscriptionId.isEmpty else {
            print("[AppsOnAirSubscriptionAPI] no subscriptionId — alias GET not sent")
            completion(nil, nil, nil)
            return
        }
        let endpoint = EnvironmentConfig.subscriptionById + subscriptionId + "/alias"
        guard let url = URL(string: endpoint) else {
            print("[AppsOnAirSubscriptionAPI] invalid endpoint URL '\(endpoint)'")
            completion(nil, nil, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(AppPushService.shared._appId,    forHTTPHeaderField: "X-App-Id")
        request.setValue(AppsOnAirDeviceInfo.sdkVersion, forHTTPHeaderField: "X-SDK-Version")
        request.setValue("ios",                          forHTTPHeaderField: "X-Platform")

        print("[AppsOnAirSubscriptionAPI] → GET \(url.absoluteString) (alias)")
        print("[AppsOnAirSubscriptionAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirSubscriptionAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirSubscriptionAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    // MARK: - Body

    /// Exact backend contract for the tags POST (see curl sample): a JSON array
    /// of `{ "key": <k>, "value": <v> }` objects, one per tag. Sorted by key so
    /// the serialized body is stable for logging / testing.
    static func tagsBody(tags: [String: String]) -> [[String: String]] {
        tags.sorted { $0.key < $1.key }.map { ["key": $0.key, "value": $0.value] }
    }

    /// Exact backend contract for the tags/remove POST (see curl sample):
    /// `{ "keys": [ <k>, … ] }`. Keys are de-duplicated and sorted so the
    /// serialized body is stable for logging / testing.
    static func tagRemovalBody(keys: [String]) -> [String: [String]] {
        ["keys": Array(Set(keys)).sorted()]
    }

    /// Exact backend contract for the alias POST — identical to `tagsBody`:
    /// a plain JSON array of `{ "key": <k>, "value": <v> }` objects, one per alias.
    /// Sorted by key so the serialized body is stable for logging / testing.
    static func aliasBody(aliases: [String: String]) -> [[String: String]] {
        aliases.sorted { $0.key < $1.key }.map { ["key": $0.key, "value": $0.value] }
    }

    /// Exact backend contract for the alias/remove POST — identical to `tagRemovalBody`:
    /// `{ "keys": [ <k>, … ] }`. Keys are de-duplicated and sorted so the
    /// serialized body is stable for logging / testing.
    static func aliasRemovalBody(labels: [String]) -> [String: [String]] {
        ["keys": Array(Set(labels)).sorted()]
    }

    // MARK: - Response parsing

    /// Turn a `GET …/tags` response body into a `[String: String]` map.
    ///
    /// The backend contract for this response is not pinned down by the curl
    /// sample, so this stays tolerant of the shapes the other tag endpoints
    /// suggest:
    ///   • `[ { "key": "plan", "value": "pro" }, … ]`         (mirrors the POST body)
    ///   • `{ "tags": [ { "key": …, "value": … }, … ] }`      (wrapped array)
    ///   • `{ "tags": { "plan": "pro", … } }`                 (wrapped map)
    ///   • `{ "plan": "pro", … }`                             (flat map)
    ///   • any of the above nested under a top-level `"data"` key
    /// Returns `nil` only when the body is not JSON or matches none of these.
    static func parseTagsResponse(_ data: Data?) -> [String: String]? {
        guard let data, !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        // Unwrap a top-level { "data": … } envelope if present.
        let payload: Any = (root as? [String: Any])?["data"] ?? root

        func fromArray(_ array: [[String: Any]]) -> [String: String] {
            var out: [String: String] = [:]
            for entry in array {
                guard let key = entry["key"] as? String else { continue }
                out[key] = entry["value"].map { "\($0)" } ?? ""
            }
            return out
        }

        func fromMap(_ map: [String: Any]) -> [String: String] {
            map.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        }

        if let array = payload as? [[String: Any]] {
            return fromArray(array)
        }
        if let dict = payload as? [String: Any] {
            if let array = dict["tags"] as? [[String: Any]] { return fromArray(array) }
            if let map = dict["tags"] as? [String: Any]     { return fromMap(map) }
            // No "tags" key — treat the object itself as a flat key/value map,
            // dropping any obviously non-tag scalar metadata is not possible here
            // so callers should prefer the wrapped shapes above.
            return fromMap(dict)
        }
        return nil
    }

    /// Turn a `GET …/alias` response body into a `[String: String]` map
    /// (label → id).
    ///
    /// Tolerant of the same shapes as `parseTagsResponse` but with alias keys:
    ///   • `{ "alias": [ { "label": "crm_id", "id": "123" }, … ] }`  (wrapped array)
    ///   • `{ "alias": { "crm_id": "123", … } }`                     (wrapped map)
    ///   • `[ { "label": "crm_id", "id": "123" }, … ]`               (bare array)
    ///   • `{ "crm_id": "123", … }`                                   (flat map)
    ///   • any of the above nested under a top-level `"data"` key
    /// Returns `nil` only when the body is not JSON or matches none of these.
    static func parseAliasResponse(_ data: Data?) -> [String: String]? {
        guard let data, !data.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let payload: Any = (root as? [String: Any])?["data"] ?? root

        func fromArray(_ array: [[String: Any]]) -> [String: String] {
            var out: [String: String] = [:]
            for entry in array {
                guard let label = entry["label"] as? String else { continue }
                out[label] = entry["id"].map { "\($0)" } ?? ""
            }
            return out
        }

        func fromMap(_ map: [String: Any]) -> [String: String] {
            map.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        }

        if let array = payload as? [[String: Any]] {
            return fromArray(array)
        }
        if let dict = payload as? [String: Any] {
            if let array = dict["alias"] as? [[String: Any]] { return fromArray(array) }
            if let map = dict["alias"] as? [String: Any]     { return fromMap(map) }
            return fromMap(dict)
        }
        return nil
    }

    /// Exact backend contract from the `/v1/subscriptions` curl sample.
    ///
    /// Device/app facts come from `AppsOnAirDeviceInfo.coreMetadata()` — a typed
    /// view over Core's static, synchronous `getDeviceMetadata()`.
    /// Must run on the main thread: `coreMetadata()` reads UIKit singletons.
    static func subscriptionBody(pushToken: String) -> [String: Any] {
        let meta = AppsOnAirDeviceInfo.coreMetadata()
        return [
            "app_id":           AppPushService.shared._appId,
            "device_id":        AppPushService.deviceId,
            "platform":         "ios",
            "push_token":       pushToken,
            "apns_environment": AppPushService.apnsEnvironment.rawValue,   // "sandbox" | "production"
            "enabled":          AppPushService.isOptedIn,                  // token && !optedOut && permission
            "external_id":      AppPushService.shared.externalId ?? NSNull(),  // identified user, or null (anonymous)
            "sdk_version":      AppsOnAirDeviceInfo.sdkVersion,
            "app_version":      meta.appVersion,
            "build_number":     meta.buildNumber,
            "device_model":     meta.deviceModel,
            "os_version":       meta.osVersion,
            "timezone":         meta.timezone,
            "country":          meta.regionCode,                        // ISO region, e.g. "IN"
            "language":         AppPushService.shared.language,
            "is_jailbroken":    AppsOnAirDeviceInfo.isJailbroken
        ]
    }

    /// Exact backend contract for the token-rotation PATCH (see curl sample):
    /// `{ push_token, os_version, app_version, language, timezone }`.
    ///
    /// Device/app facts come from `AppsOnAirDeviceInfo.coreMetadata()`; `language`
    /// is the Push-level value (`AppsOnAirUser` override), matching `subscriptionBody`.
    /// Must run on the main thread: `coreMetadata()` reads UIKit singletons.
    static func pushTokenBody(pushToken: String) -> [String: Any] {
        let meta = AppsOnAirDeviceInfo.coreMetadata()
        return [
            "push_token":  pushToken,
            "os_version":  meta.osVersion,
            "app_version": meta.appVersion,
            "language":    AppPushService.shared.language,
            "timezone":    meta.timezone
        ]
    }
}
