import Foundation

// MARK: - AppsOnAirNetworkMonitor
//
// One place to gate SDK work on network connectivity, backed by AppsOnAir_Core's
// reachability (`AppPushService.shared.core`). Core keeps only a SINGLE
// `networkStatusListenerHandler`, so this file owns that slot and fans out to any
// number of queued actions.
//
// Usage:
//
//   if AppsOnAirNetworkMonitor.isConnected {
//       AppsOnAirSubscriptionAPI.registerDevice { … }
//   }
//
//   // or: run it as soon as the network is up (now, or the next time it comes back)
//   AppsOnAirNetworkMonitor.runWhenConnected {
//       AppsOnAirSubscriptionAPI.registerDevice { … }
//   }

@MainActor
enum AppsOnAirNetworkMonitor {

    /// Current connectivity, as last reported by AppsOnAir_Core.
    /// `core.isNetworkConnected` is `nil` until the first reachability callback —
    /// treated as "not connected" here.
    static var isConnected: Bool {
        AppPushService.shared.core.isNetworkConnected == true
    }

    /// Actions waiting for connectivity.
    private static var pending: [@MainActor () -> Void] = []
    /// True once the single Core listener has been installed.
    private static var listening = false

    /// Install the Core reachability listener so that connectivity changes trigger
    /// an immediate event-queue flush and drain any pending `runWhenConnected` actions.
    /// Called once from `AppPushService.initialize()` — this ensures the reconnect
    /// flush fires even when the device was online for every `runWhenConnected` call
    /// and the listener would otherwise never have been installed.
    static func startMonitoring() {
        startListening()
    }

    /// Run `action` as soon as the network is connected — immediately if it
    /// already is, otherwise once, the next time AppsOnAir_Core reports the
    /// network is up.
    static func runWhenConnected(_ action: @escaping @MainActor () -> Void) {
        startListening()  // ensure listener is installed (idempotent)
        if isConnected {
            AppPushService.log("NetworkMonitor: online — running action now", level: .debug)
            action()
            return
        }
        pending.append(action)
        AppPushService.log("NetworkMonitor: offline — queued action (\(pending.count) pending)", level: .debug)
    }

    // MARK: - Private

    private static func startListening() {
        guard !listening else { return }
        listening = true
        AppPushService.shared.core.networkStatusListenerHandler { connected in
            Task { @MainActor in
                AppPushService.log("NetworkMonitor: connectivity changed → \(connected)", level: .debug)
                guard connected else { return }

                // Flush the persistent event queue immediately on reconnect so that
                // queued offline events (open, click, delivered) reach the backend as
                // soon as internet is available — rather than waiting for the next app
                // foreground or session start.
                AppsOnAirEventQueue.shared.flush()

                guard !pending.isEmpty else { return }
                let actions = pending
                pending.removeAll()
                AppPushService.log("NetworkMonitor: draining \(actions.count) queued action(s)", level: .debug)
                actions.forEach { $0() }
            }
        }
    }
}
