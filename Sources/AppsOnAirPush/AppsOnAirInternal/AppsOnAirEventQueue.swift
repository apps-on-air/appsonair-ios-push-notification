import Foundation

// MARK: - AppsOnAirEventQueue
//
// Lightweight, persistent queue for SDK-side events that must be reported to the backend.
// Events are written to UserDefaults immediately so they survive app restarts.
// On session start / app foreground, flush() drains the queue.
//
// Scope §3.3: "SDK reports the open/click event back."
// Scope §3.4: "SDK reports a delivery receipt (notification ID + subscription ID) back."
//
// HOW IT WORKS:
//   1. SDK calls enqueue() when a click, open, delivery, or session event occurs.
//   2. On session start (app foreground), flush() drains the queue in order.
//   3. Each sendEvent() stub logs the payload and returns true (success).
//   4. Replace each stub with a real URLSession HTTP call once BE API is ready.
//   5. On 5xx / network error: return false → event stays in queue for retry.

@MainActor
final class AppsOnAirEventQueue {

    static let shared = AppsOnAirEventQueue()

    private let storageKey = "com.appsonair.push.eventQueue"
    private var isFlushing = false

    private init() {}

    // MARK: - Enqueue

    /// Add an event to the persistent queue.
    /// Written to UserDefaults immediately — events survive app restarts and are sent on next flush.
    func enqueue(_ event: PushEvent) {
        var queue = load()
        // Cap at 100 events — drop oldest if exceeded (avoids unbounded growth on network outage)
        if queue.count >= 100 {
            let dropped = queue.removeFirst()
            AppsOnAirPush.log(
                "EventQueue: queue full (100), dropped oldest. type=\(dropped.type.rawValue)",
                level: .warn
            )
        }
        queue.append(event)
        save(queue)
        AppsOnAirPush.log(
            "EventQueue: enqueued \(event.type.rawValue). " +
            "notifId=\(event.notificationId ?? "nil") queueSize=\(queue.count)",
            level: .debug
        )
    }

    // MARK: - Flush

    /// Drain the event queue — called on session start (app foreground).
    /// Events are sent in FIFO order; stops on first failure to preserve ordering.
    /// Skips if a flush is already in progress.
    func flush() {
        guard !isFlushing else {
            AppsOnAirPush.log("EventQueue: flush already in progress, skipping.", level: .debug)
            return
        }
        // Pull in any delivery receipts the Notification Service Extension wrote to the
        // App Group while the app was backgrounded, so they ride out on this flush.
        drainSharedExtensionQueue()

        let queue = load()
        guard !queue.isEmpty else { return }

        isFlushing = true
        AppsOnAirPush.log("EventQueue: flushing \(queue.count) pending event(s).", level: .info)

        Task { @MainActor in
            defer { self.isFlushing = false }
            var remaining = queue

            for event in queue {
                let sent = await self.sendEvent(event)
                if sent {
                    remaining.removeFirst()
                    AppsOnAirPush.log(
                        "EventQueue: sent \(event.type.rawValue). remaining=\(remaining.count)",
                        level: .debug
                    )
                } else {
                    // Stop on first failure — preserve ordering, retry on next flush.
                    AppsOnAirPush.log(
                        "EventQueue: send failed, stopping flush. remaining=\(remaining.count)",
                        level: .warn
                    )
                    break
                }
            }
            self.save(remaining)
        }
    }

    // MARK: - Notification Service Extension bridge

    /// Key of the shared array the NSE appends delivery receipts to
    /// (`AppsOnAirPushExtension` in the `AppsOnAirPushServiceExt` target). Kept in sync
    /// with that target manually — the two do not share code.
    private let nseQueueKey = "com.appsonair.push.nseEventQueue"

    /// Move delivery receipts written by the NSE process (App Group `UserDefaults`) into
    /// the main persistent queue, then clear the shared slot. Called at the top of `flush()`.
    private func drainSharedExtensionQueue() {
        guard let groupId = AppsOnAirPush.shared._appGroupId,
              let defaults = UserDefaults(suiteName: groupId) else { return }
        guard let raw = defaults.array(forKey: nseQueueKey) as? [[String: Any]], !raw.isEmpty else { return }

        let fallbackDeviceId = AppsOnAirPush.deviceId
        for entry in raw {
            func nonEmpty(_ key: String) -> String? {
                (entry[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
            }
            enqueue(PushEvent(
                type: .delivered,
                notificationId: nonEmpty("notification_id"),
                subscriptionId: nonEmpty("subscription_id"),
                actionId: nil,
                timestamp: entry["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970,
                deviceId: nonEmpty("device_id") ?? fallbackDeviceId
            ))
        }
        defaults.removeObject(forKey: nseQueueKey)
        AppsOnAirPush.log(
            "EventQueue: drained \(raw.count) NSE delivery receipt(s) from App Group '\(groupId)'.",
            level: .info
        )
    }

    // MARK: - Send (TODO: replace each stub with real URLSession HTTP calls)

    private func sendEvent(_ event: PushEvent) async -> Bool {
        switch event.type {
        case .opened, .clicked:
            return await sendOpenEvent(event)
        case .delivered:
            return await sendDeliveryReceipt(event)
        case .received:
            // Local foreground receipt — no backend call for free tier.
            // TODO: API — POST /events/received if BE wants foreground delivery tracking.
            AppsOnAirPush.log(
                "EventQueue: 'received' is local-only (no API call). notifId=\(event.notificationId ?? "nil")",
                level: .debug
            )
            return true
        case .sessionStart:
            return await sendSessionPing(event)
        }
    }

    private func sendOpenEvent(_ event: PushEvent) async -> Bool {
        // TODO: API — POST /events/opened  (endpoint: /events/clicked when actionId != nil)
        //
        // let url = URL(string: "\(baseURL)/events/\(event.actionId == nil ? "opened" : "clicked")")!
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.setValue("Bearer \(sdkApiKey)", forHTTPHeaderField: "Authorization")
        // request.httpBody = try? JSONSerialization.data(withJSONObject: [
        //     "app_id":          configuredAppId,
        //     "notification_id": event.notificationId ?? "",
        //     "subscription_id": event.subscriptionId ?? "",
        //     "device_id":       event.deviceId,
        //     "action_id":       event.actionId as Any,  // null = body tap
        //     "timestamp":       ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: event.timestamp))
        // ])
        // // On 2xx → return true (remove from queue)
        // // On 4xx → return true (bad payload, don't retry)
        // // On 5xx / network error → return false (retry on next flush)
        //
        let endpoint = event.actionId == nil ? "opened" : "clicked"
        AppsOnAirPush.log(
            "EventQueue: [TODO] POST /events/\(endpoint) " +
            "notifId=\(event.notificationId ?? "nil") " +
            "subscriptionId=\(event.subscriptionId ?? "nil") " +
            "actionId=\(event.actionId ?? "(body tap)")",
            level: .info
        )
        return true // Stub — remove when BE API is ready
    }

    private func sendDeliveryReceipt(_ event: PushEvent) async -> Bool {
        // TODO: API — POST /events/delivered
        // This powers "Delivered" analytics (paid tier only — §3.4, §3.8).
        //
        // let url = URL(string: "\(baseURL)/events/delivered")!
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.setValue("Bearer \(sdkApiKey)", forHTTPHeaderField: "Authorization")
        // request.httpBody = try? JSONSerialization.data(withJSONObject: [
        //     "app_id":          configuredAppId,
        //     "notification_id": event.notificationId ?? "",
        //     "subscription_id": event.subscriptionId ?? "",
        //     "device_id":       event.deviceId,
        //     "timestamp":       ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: event.timestamp))
        // ])
        //
        // Typically enqueued by AppsOnAirNotificationServiceExtension writing to App Group storage,
        // then drained here on next main app foreground.
        AppsOnAirPush.log(
            "EventQueue: [TODO] POST /events/delivered notifId=\(event.notificationId ?? "nil")",
            level: .info
        )
        return true // Stub
    }

    private func sendSessionPing(_ event: PushEvent) async -> Bool {
        // TODO: API — POST /sessions
        // Backend counts this as a MAU session (user with ≥1 session in trailing 30 days — §3.9).
        // Also triggers a subscription metadata update (device model, OS, app version, etc.).
        //
        // let url = URL(string: "\(baseURL)/sessions")!
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        // request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // request.setValue("Bearer \(sdkApiKey)", forHTTPHeaderField: "Authorization")
        // var body: [String: Any] = [
        //     "app_id":          configuredAppId,
        //     "subscription_id": event.subscriptionId ?? "",
        //     "device_id":       event.deviceId,
        //     "timestamp":       ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: event.timestamp))
        // ]
        // // Merge session + device fields for full subscription update
        // AppsOnAirSessionManager.shared.asPayloadDict().forEach { body[$0.key] = $0.value }
        // AppsOnAirDeviceInfo.registrationPayload().forEach { body[$0.key] = $0.value }
        // request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        AppsOnAirPush.log(
            "EventQueue: [TODO] POST /sessions deviceId=\(event.deviceId)",
            level: .info
        )
        return true // Stub
    }

    // MARK: - Persistence

    private func load() -> [PushEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([PushEvent].self, from: data)
        else { return [] }
        return events
    }

    private func save(_ events: [PushEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
