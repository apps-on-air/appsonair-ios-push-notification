import Foundation

// MARK: - AppsOnAirNetworkMonitor
//
// One place to gate SDK work on network connectivity, backed by AppsOnAir_Core's
// reachability (`AppsOnAirPush.shared.core`). Core keeps only a SINGLE
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
        AppsOnAirPush.shared.core.isNetworkConnected == true
    }

    /// Actions waiting for connectivity.
    private static var pending: [@MainActor () -> Void] = []
    /// True once the single Core listener has been installed.
    private static var listening = false

    /// Run `action` as soon as the network is connected — immediately if it
    /// already is, otherwise once, the next time AppsOnAir_Core reports the
    /// network is up.
    static func runWhenConnected(_ action: @escaping @MainActor () -> Void) {
        if isConnected {
            print("[AppsOnAirNetworkMonitor] online — running action now")
            action()
            return
        }
        pending.append(action)
        print("[AppsOnAirNetworkMonitor] offline — queued action (\(pending.count) pending)")
        startListening()
    }

    // MARK: - Private

    private static func startListening() {
        guard !listening else { return }
        listening = true
        AppsOnAirPush.shared.core.networkStatusListenerHandler { connected in
            Task { @MainActor in
                print("[AppsOnAirNetworkMonitor] connectivity changed → \(connected)")
                guard connected, !pending.isEmpty else { return }
                let actions = pending
                pending.removeAll()
                print("[AppsOnAirNetworkMonitor] draining \(actions.count) queued action(s)")
                actions.forEach { $0() }
            }
        }
    }
}
