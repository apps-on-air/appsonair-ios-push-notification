import Foundation

// MARK: - AppsOnAirSyncReason
//
// Diagnostic tag for *why* a backend subscription-sync call was triggered.
//
// Passed to the `…IfReady` orchestrators in `AppsOnAirPush`
// (`registerSubscriptionIfReady`, `updateSubscriptionEnabledIfReady`,
// `updatePushTokenIfRotated`, `syncExternalIdIfReady`, `syncOptInStateIfReady`,
// `syncTagsIfReady`, `syncLanguageIfReady`)
// and printed verbatim in their log lines. It never affects request behaviour —
// it exists only so the trigger shows up in the SDK logs.
//
// Centralised here so the set of reasons is a closed, greppable list instead of
// string literals scattered across call sites. `description` is kept byte-for-byte
// identical to the previous hand-written literals so existing log output is
// unchanged.

enum AppsOnAirSyncReason: CustomStringConvertible, Equatable {

    /// End of `initialize()` — the launch's first registration attempt.
    case initialize

    /// APNs delivered a device token (`handleAPNsToken`) — nudge the one-shot
    /// registration now that the token it was waiting on exists.
    case apnsToken

    /// APNs reissued a *different* token after this device was already
    /// registered (restore-from-backup, some OS upgrades, reinstall).
    case apnsTokenRotated

    /// `login(_:)` — link the identified user to the backend subscription.
    case login

    /// `logout()` — unlink the identified user from the backend subscription.
    case logout

    /// `User.pushSubscription.optIn()`.
    case optIn

    /// `User.pushSubscription.optOut()`.
    case optOut

    /// `User.addTag(key:value:)` / `User.addTags(_:)` — sync the local tag set
    /// to the backend subscription.
    case tagsAdded

    /// `User.removeTag(_:)` / `User.removeTags(_:)` — drop the given keys from
    /// the backend subscription's tag set.
    case tagsRemoved

    /// `User.getTags()` — refresh the local tag cache from the backend
    /// subscription.
    case tagsFetched

    /// `User.setLanguage(_:)` — sync the language override to the backend
    /// subscription.
    case languageSet

    /// Notification permission flipped; `granted` is the new value.
    case permissionChanged(granted: Bool)

    /// Exact text used in the SDK log lines.
    var description: String {
        switch self {
        case .initialize:       return "initialize"
        case .apnsToken:        return "apns-token"
        case .apnsTokenRotated: return "apns-token-rotated"
        case .login:            return "login"
        case .logout:           return "logout"
        case .optIn:            return "optIn"
        case .optOut:           return "optOut"
        case .tagsAdded:        return "tagsAdded"
        case .tagsRemoved:      return "tagsRemoved"
        case .tagsFetched:      return "tagsFetched"
        case .languageSet:      return "languageSet"
        case .permissionChanged(let granted):
            return "permission changed → \(granted)"
        }
    }
}
