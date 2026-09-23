import Foundation
#if SWIFT_PACKAGE
import AppsOnAir_AppPush_Shared
#endif

// MARK: - AppsOnAirEventsAPI
//
// Thin transport for the /v1/events endpoints. This type ONLY builds and sends
// the request and hands the raw URLSession result back to the caller. It does
// not interpret the response or retry — the caller (AppsOnAirEventQueue) owns
// that, since events are backed by a persistent, ordered retry queue.
//
//   POST <EnvironmentConfig.eventDelivered>   (…/v1/events/delivered)
//   Sent once a push notification has been confirmed delivered to the device —
//   queued by the Notification Service Extension, drained and sent here on the
//   next app foreground.
//   Headers:
//     X-App-Id:      <configured appId>
//     X-SDK-Version: <AppsOnAirDeviceInfo.sdkVersion>
//     X-Platform:    ios
//     Content-Type:  application/json
//   Body (exact backend contract — see curl sample):
//     { subscription_id, notification_id, send_id }
//
//   POST <EnvironmentConfig.eventOpened>   (…/v1/events/opened)
//   Sent once the user taps a notification's body (not an action button).
//   Headers:
//     X-App-Id:      <configured appId>
//     X-SDK-Version: <AppsOnAirDeviceInfo.sdkVersion>
//     X-Platform:    ios
//     Content-Type:  application/json
//   Body (exact backend contract — see curl sample):
//     { subscription_id, device_id, notification_id, send_id }
//
//   POST <EnvironmentConfig.eventClicked>   (…/v1/events/clicked)
//   Sent once the user taps a notification's action button.
//   Headers:
//     X-App-Id:      <configured appId>
//     X-SDK-Version: <AppsOnAirDeviceInfo.sdkVersion>
//     X-Platform:    ios
//     Content-Type:  application/json
//   Body (exact backend contract — see curl sample):
//     { subscription_id, notification_id, send_id, action_id }

@MainActor
enum AppsOnAirEventsAPI {

    /// Send POST /v1/events/delivered and return the raw result on the main actor.
    ///
    /// `completion` receives `(Data?, URLResponse?, Error?)` exactly as URLSession
    /// produced it — the caller (`AppsOnAirEventQueue`) decides whether to remove
    /// the event from the retry queue. When the request cannot even be built (bad
    /// URL, encode failure) the completion is called with all-nil.
    static func sendDeliveredEvent(
        notificationId: String,
        subscriptionId: String,
        sendId: String,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let url = URL(string: EnvironmentConfig.eventDelivered) else {
            print("[AppsOnAirEventsAPI] invalid endpoint URL '\(EnvironmentConfig.eventDelivered)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = [
            "subscription_id": subscriptionId,
            "notification_id": notificationId,
            "send_id":         sendId
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirEventsAPI] failed to serialize body")
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

        print("[AppsOnAirEventsAPI] → POST \(url.absoluteString) (delivered)")
        print("[AppsOnAirEventsAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirEventsAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirEventsAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirEventsAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/events/opened and return the raw result on the main actor.
    ///
    /// `completion` receives `(Data?, URLResponse?, Error?)` exactly as URLSession
    /// produced it — the caller (`AppsOnAirEventQueue`) decides whether to remove
    /// the event from the retry queue. When the request cannot even be built (bad
    /// URL, encode failure) the completion is called with all-nil.
    static func sendOpenedEvent(
        notificationId: String,
        subscriptionId: String,
        deviceId: String,
        sendId: String,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let url = URL(string: EnvironmentConfig.eventOpened) else {
            print("[AppsOnAirEventsAPI] invalid endpoint URL '\(EnvironmentConfig.eventOpened)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = [
            "subscription_id": subscriptionId,
            "device_id":       deviceId,
            "notification_id": notificationId,
            "send_id":         sendId
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirEventsAPI] failed to serialize body")
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

        print("[AppsOnAirEventsAPI] → POST \(url.absoluteString) (opened)")
        print("[AppsOnAirEventsAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirEventsAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirEventsAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirEventsAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }

    /// Send POST /v1/events/clicked and return the raw result on the main actor.
    ///
    /// `completion` receives `(Data?, URLResponse?, Error?)` exactly as URLSession
    /// produced it — the caller (`AppsOnAirEventQueue`) decides whether to remove
    /// the event from the retry queue. When the request cannot even be built (bad
    /// URL, encode failure) the completion is called with all-nil.
    static func sendClickedEvent(
        notificationId: String,
        subscriptionId: String,
        actionId: String,
        sendId: String,
        completion: @escaping @MainActor (Data?, URLResponse?, Error?) -> Void
    ) {
        guard let url = URL(string: EnvironmentConfig.eventClicked) else {
            print("[AppsOnAirEventsAPI] invalid endpoint URL '\(EnvironmentConfig.eventClicked)'")
            completion(nil, nil, nil)
            return
        }

        let body: [String: Any] = [
            "subscription_id": subscriptionId,
            "notification_id": notificationId,
            "send_id":         sendId,
            "action_id":       actionId
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else {
            print("[AppsOnAirEventsAPI] failed to serialize body")
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

        print("[AppsOnAirEventsAPI] → POST \(url.absoluteString) (clicked)")
        print("[AppsOnAirEventsAPI]   X-App-Id=\(AppPushService.shared._appId) X-SDK-Version=\(AppsOnAirDeviceInfo.sdkVersion) X-Platform=ios")
        print("[AppsOnAirEventsAPI]   body=\(String(data: httpBody, encoding: .utf8) ?? "<non-utf8>")")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            print("[AppsOnAirEventsAPI] ← HTTP \(status) error=\(error?.localizedDescription ?? "nil")")
            print("[AppsOnAirEventsAPI]   response=\(text)")
            Task { @MainActor in
                completion(data, response, error)
            }
        }.resume()
    }
}
