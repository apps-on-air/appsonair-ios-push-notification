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
//   1. SDK calls enqueue() when a click, open, or delivery event occurs.
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
            AppPushService.log(
                "EventQueue: queue full (100), dropped oldest. type=\(dropped.type.rawValue)",
                level: .warn
            )
        }
        queue.append(event)
        save(queue)
        AppPushService.log(
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
            AppPushService.log("EventQueue: flush already in progress, skipping.", level: .debug)
            return
        }
        // Pull in any delivery receipts the Notification Service Extension wrote to the
        // App Group while the app was backgrounded, so they ride out on this flush.
        drainSharedExtensionQueue()

        let queue = load()
        guard !queue.isEmpty else { return }

        isFlushing = true
        AppPushService.log("EventQueue: flushing \(queue.count) pending event(s).", level: .info)

        Task { @MainActor in
            defer { self.isFlushing = false }
            var remaining = queue

            for event in queue {
                let sent = await self.sendEvent(event)
                if sent {
                    remaining.removeFirst()
                    AppPushService.log(
                        "EventQueue: sent \(event.type.rawValue). remaining=\(remaining.count)",
                        level: .debug
                    )
                } else {
                    // Stop on first failure — preserve ordering, retry on next flush.
                    AppPushService.log(
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
    /// (`AppPushServiceExtension` in the `AppsOnAirPushServiceExt` target). Kept in sync
    /// with that target manually — the two do not share code.
    private let nseQueueKey = "com.appsonair.push.nseEventQueue"

    /// Move delivery receipts written by the NSE process (App Group `UserDefaults`) into
    /// the main persistent queue, then clear the shared slot. Called at the top of `flush()`.
    private func drainSharedExtensionQueue() {
        guard let groupId = AppPushService.shared._appGroupId,
              let defaults = UserDefaults(suiteName: groupId) else { return }
        guard let raw = defaults.array(forKey: nseQueueKey) as? [[String: Any]], !raw.isEmpty else { return }

        let fallbackDeviceId = AppPushService.deviceId
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
                deviceId: nonEmpty("device_id") ?? fallbackDeviceId,
                sendId: nonEmpty("send_id")
            ))
        }
        defaults.removeObject(forKey: nseQueueKey)
        AppPushService.log(
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
            AppPushService.log(
                "EventQueue: 'received' is local-only (no API call). notifId=\(event.notificationId ?? "nil")",
                level: .debug
            )
            return true
        }
    }

    private func sendOpenEvent(_ event: PushEvent) async -> Bool {
        // Body tap → POST /v1/events/opened. Action-button tap → POST /v1/events/clicked.
        guard let actionId = event.actionId else {
            return await sendOpenedReceipt(event)
        }
        return await sendClickedReceipt(event, actionId: actionId)
    }

    /// POST /v1/events/opened — sent once the user taps a notification's body.
    ///
    /// Gated on connectivity like every other SDK network call
    /// (`AppsOnAirNetworkMonitor.isConnected`) — offline, the event stays queued and is
    /// retried on the next flush instead of failing the request. `AppsOnAirEventsAPI`
    /// only builds/sends the request; the success/retry decision is made here:
    ///   • 2xx           → true  (remove from queue)
    ///   • 4xx / no data → true  (bad payload or malformed event — don't retry forever)
    ///   • 5xx / network error → false (retry on next flush)
    private func sendOpenedReceipt(_ event: PushEvent) async -> Bool {
        guard let notificationId = event.notificationId, !notificationId.isEmpty,
              let subscriptionId = event.subscriptionId, !subscriptionId.isEmpty else {
            AppPushService.log(
                "EventQueue: opened event missing notificationId/subscriptionId — dropping.",
                level: .warn
            )
            return true
        }
        guard AppsOnAirNetworkMonitor.isConnected else {
            AppPushService.log("EventQueue: offline — opened receipt deferred.", level: .debug)
            return false
        }

        return await withCheckedContinuation { continuation in
            AppsOnAirEventsAPI.sendOpenedEvent(
                notificationId: notificationId,
                subscriptionId: subscriptionId,
                deviceId: event.deviceId,
                sendId: event.sendId ?? ""
            ) { data, response, error in
                if let error {
                    AppPushService.log(
                        "EventQueue: POST /v1/events/opened error: \(error.localizedDescription)",
                        level: .warn
                    )
                    continuation.resume(returning: false)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                AppPushService.log(
                    "EventQueue: POST /v1/events/opened HTTP \(status) notifId=\(notificationId): \(bodyText)",
                    level: .info
                )
                continuation.resume(returning: (200..<500).contains(status))
            }
        }
    }

    /// POST /v1/events/clicked — sent once the user taps a notification's action button.
    ///
    /// Gated on connectivity like every other SDK network call
    /// (`AppsOnAirNetworkMonitor.isConnected`) — offline, the event stays queued and is
    /// retried on the next flush instead of failing the request. `AppsOnAirEventsAPI`
    /// only builds/sends the request; the success/retry decision is made here:
    ///   • 2xx           → true  (remove from queue)
    ///   • 4xx / no data → true  (bad payload or malformed event — don't retry forever)
    ///   • 5xx / network error → false (retry on next flush)
    private func sendClickedReceipt(_ event: PushEvent, actionId: String) async -> Bool {
        guard let notificationId = event.notificationId, !notificationId.isEmpty,
              let subscriptionId = event.subscriptionId, !subscriptionId.isEmpty else {
            AppPushService.log(
                "EventQueue: clicked event missing notificationId/subscriptionId — dropping.",
                level: .warn
            )
            return true
        }
        guard AppsOnAirNetworkMonitor.isConnected else {
            AppPushService.log("EventQueue: offline — clicked receipt deferred.", level: .debug)
            return false
        }

        return await withCheckedContinuation { continuation in
            AppsOnAirEventsAPI.sendClickedEvent(
                notificationId: notificationId,
                subscriptionId: subscriptionId,
                actionId: actionId,
                sendId: event.sendId ?? ""
            ) { data, response, error in
                if let error {
                    AppPushService.log(
                        "EventQueue: POST /v1/events/clicked error: \(error.localizedDescription)",
                        level: .warn
                    )
                    continuation.resume(returning: false)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                AppPushService.log(
                    "EventQueue: POST /v1/events/clicked HTTP \(status) notifId=\(notificationId): \(bodyText)",
                    level: .info
                )
                continuation.resume(returning: (200..<500).contains(status))
            }
        }
    }

    /// POST /v1/events/delivered — powers "Delivered" analytics (paid tier only — §3.4, §3.8).
    ///
    /// Enqueued by `AppsOnAirNotificationServiceExtension` writing to App Group storage,
    /// then drained into the persistent queue on next main-app foreground
    /// (`drainSharedExtensionQueue()`) and sent here.
    ///
    /// Gated on connectivity like every other SDK network call
    /// (`AppsOnAirNetworkMonitor.isConnected`) — offline, the event stays queued and is
    /// retried on the next flush instead of failing the request. `AppsOnAirEventsAPI`
    /// only builds/sends the request; the success/retry decision is made here:
    ///   • 2xx           → true  (remove from queue)
    ///   • 4xx / no data → true  (bad payload or malformed event — don't retry forever)
    ///   • 5xx / network error → false (retry on next flush)
    private func sendDeliveryReceipt(_ event: PushEvent) async -> Bool {
        guard let notificationId = event.notificationId, !notificationId.isEmpty,
              let subscriptionId = event.subscriptionId, !subscriptionId.isEmpty else {
            AppPushService.log(
                "EventQueue: delivered event missing notificationId/subscriptionId — dropping.",
                level: .warn
            )
            return true
        }
        guard AppsOnAirNetworkMonitor.isConnected else {
            AppPushService.log("EventQueue: offline — delivered receipt deferred.", level: .debug)
            return false
        }

        return await withCheckedContinuation { continuation in
            AppsOnAirEventsAPI.sendDeliveredEvent(
                notificationId: notificationId,
                subscriptionId: subscriptionId,
                sendId: event.sendId ?? ""
            ) { data, response, error in
                if let error {
                    AppPushService.log(
                        "EventQueue: POST /v1/events/delivered error: \(error.localizedDescription)",
                        level: .warn
                    )
                    continuation.resume(returning: false)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let bodyText = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                AppPushService.log(
                    "EventQueue: POST /v1/events/delivered HTTP \(status) notifId=\(notificationId): \(bodyText)",
                    level: .info
                )
                continuation.resume(returning: (200..<500).contains(status))
            }
        }
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
