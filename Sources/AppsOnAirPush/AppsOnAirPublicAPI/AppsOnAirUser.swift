import Foundation

// MARK: - AppsOnAirPush.User namespace

extension AppsOnAirPush {

    /// User identity, tags, language, aliases, email, and SMS management.
    /// Matches OneSignal.User namespace from OneSignal SDK v5.
    @MainActor
    public enum User {

        // MARK: - Identity

        /// The AppsOnAir-assigned device ID (same as deviceId for now).
        public static var appsOnAirId: String { AppsOnAirPush.deviceId }

        /// The external user ID linked via login().
        public static var externalId: String? { AppsOnAirPush.shared.externalId }

        // MARK: - Push Subscription

        /// This device's push subscription — id, token, opt-in state, and observers.
        /// Matches OneSignal v5 `OneSignal.User.pushSubscription`.
        public static var pushSubscription: PushSubscription { PushSubscription() }

        @MainActor
        public struct PushSubscription {

            internal init() {}

            /// The AppsOnAir subscription ID for this device.
            /// nil until the backend registers the device via POST /subscriptions.
            /// Matches OneSignal v5 `pushSubscription.id`.
            public var id: String? { AppsOnAirPush.subscriptionId }

            /// The current APNs device token (hex string). nil until APNs registers.
            public var token: String? { AppsOnAirPush.shared.storage.getApnsToken() }

            /// true unless the user has called optOut().
            public var optedIn: Bool { !AppsOnAirPush.shared.isOptedOut }

            /// Opt in to push notifications. Reverses a previous optOut() call.
            /// Does not re-request OS permission — call Notifications.requestPermission() for that.
            public func optIn() {
                let previous = PushSubscriptionState(token: token, optedIn: !AppsOnAirPush.shared.isOptedOut)
                AppsOnAirPush.shared.isOptedOut = false
                UserDefaults.standard.set(false, forKey: "com.appsonair.push.isOptedOut")
                AppsOnAirPush.log("Push subscription opted in.", level: .info)
                notifyObservers(previous: previous)
                // Match the backend subscription — POST /v1/subscriptions/<id>/opt-in, gated on connectivity.
                AppsOnAirPush.syncOptInStateIfReady(reason: .optIn)
            }

            /// Opt out of push notifications without revoking OS permission.
            /// Token is preserved on backend — user won't receive pushes until optIn() is called.
            public func optOut() {
                let previous = PushSubscriptionState(token: token, optedIn: !AppsOnAirPush.shared.isOptedOut)
                AppsOnAirPush.shared.isOptedOut = true
                UserDefaults.standard.set(true, forKey: "com.appsonair.push.isOptedOut")
                AppsOnAirPush.log("Push subscription opted out.", level: .info)
                notifyObservers(previous: previous)
                // Match the backend subscription — POST /v1/subscriptions/<id>/opt-out, gated on connectivity.
                AppsOnAirPush.syncOptInStateIfReady(reason: .optOut)
            }

            public func addObserver(_ observer: PushSubscriptionObserver) {
                AppsOnAirPush.shared.pushSubscriptionObservers.append(observer)
            }

            public func removeObserver(_ observer: PushSubscriptionObserver) {
                AppsOnAirPush.shared.pushSubscriptionObservers.removeAll { $0 === observer }
            }

            private func notifyObservers(previous: PushSubscriptionState) {
                let current = PushSubscriptionState(token: token, optedIn: optedIn)
                let state = PushSubscriptionChangedState(previous: previous, current: current)
                AppsOnAirPush.shared.pushSubscriptionObservers.forEach { $0.onPushSubscriptionDidChange(state: state) }
            }
        }

        // MARK: - Tags

        /// Set a single tag for this user. Used for audience segmentation on the backend.
        public static func addTag(key: String, value: String) {
            AppsOnAirPush.shared.tags[key] = value
            persistTags()
            AppsOnAirPush.log("Tag added: \(key)=\(value)", level: .debug)
            // Sync the local tag set to the backend subscription —
            // POST /v1/subscriptions/<id>/tags, gated on connectivity.
            AppsOnAirPush.syncTagsIfReady(reason: .tagsAdded)
        }

        /// Set multiple tags at once.
        public static func addTags(_ tags: [String: String]) {
            tags.forEach { AppsOnAirPush.shared.tags[$0.key] = $0.value }
            persistTags()
            AppsOnAirPush.log("Tags added: \(tags.keys.joined(separator: ", "))", level: .debug)
            // Sync the local tag set to the backend subscription —
            // POST /v1/subscriptions/<id>/tags, gated on connectivity.
            AppsOnAirPush.syncTagsIfReady(reason: .tagsAdded)
        }

        /// Remove a tag by key.
        public static func removeTag(_ key: String) {
            AppsOnAirPush.shared.tags.removeValue(forKey: key)
            persistTags()
            AppsOnAirPush.log("Tag removed: \(key)", level: .debug)
            // Drop the key from the backend subscription's tag set —
            // POST /v1/subscriptions/<id>/tags/remove, gated on connectivity.
            AppsOnAirPush.syncTagRemovalIfReady(keys: [key], reason: .tagsRemoved)
        }

        /// Remove multiple tags by key.
        public static func removeTags(_ keys: [String]) {
            keys.forEach { AppsOnAirPush.shared.tags.removeValue(forKey: $0) }
            persistTags()
            AppsOnAirPush.log("Tags removed: \(keys.joined(separator: ", "))", level: .debug)
            // Drop the keys from the backend subscription's tag set —
            // POST /v1/subscriptions/<id>/tags/remove, gated on connectivity.
            AppsOnAirPush.syncTagRemovalIfReady(keys: keys, reason: .tagsRemoved)
        }

        /// The tags currently known for this user, as a `[key: value]` map.
        ///
        /// Synchronous, like OneSignal's `getTags()` — it reads the local cache.
        /// The SDK keeps that cache in step with the backend on its own:
        /// `GET /v1/subscriptions/<id>/tags` runs after `initialize()`, right
        /// after the device first registers, and on `login()`, and every
        /// `addTag` / `removeTag` writes through to the backend. Use `getTags(_:)`
        /// when you need to force a fetch and read the result.
        public static func getTags() -> [String: String] {
            AppsOnAirPush.shared.tags
        }

        /// Force a backend fetch of this user's tags and hand back the parsed
        /// `[key: value]` map on the main actor.
        ///
        /// Calls `GET /v1/subscriptions/<id>/tags` (gated on connectivity) and
        /// refreshes the local cache from the response. `completion` receives the
        /// backend tags on success, or the local cache when the request could not
        /// be sent, errored, or returned an unusable body.
        public static func getTags(_ completion: @escaping @MainActor ([String: String]) -> Void) {
            AppsOnAirPush.refreshTagsIfReady(reason: .tagsFetched, completion: completion)
        }

        // MARK: - Language

        /// Override the detected device language. Use ISO 639-1 codes (e.g. "en", "fr", "hi").
        /// The backend uses this to select the correct push translation.
        public static func setLanguage(_ code: String) {
            AppsOnAirPush.shared.language = code
            UserDefaults.standard.set(code, forKey: "com.appsonair.push.language")
            AppsOnAirPush.log("Language set to: \(code)", level: .debug)
            // Match the backend subscription — PATCH /v1/subscriptions/<id>/language,
            // gated on connectivity.
            AppsOnAirPush.syncLanguageIfReady(reason: .languageSet)
        }

        /// The current language code sent to the backend.
        public static var language: String { AppsOnAirPush.shared.language }

        // MARK: - Aliases

        /// Add a single alias. Aliases let the backend find this user by alternative IDs
        /// (e.g. your CRM ID, phone hash, etc.)
        public static func addAlias(label: String, id: String) {
            AppsOnAirPush.shared.aliases[label] = id
            persistAliases()
            AppsOnAirPush.log("Alias added: \(label)=\(id)", level: .debug)
        }

        /// Add multiple aliases at once.
        public static func addAliases(_ aliases: [String: String]) {
            aliases.forEach { AppsOnAirPush.shared.aliases[$0.key] = $0.value }
            persistAliases()
        }

        /// Remove an alias by label.
        public static func removeAlias(_ label: String) {
            AppsOnAirPush.shared.aliases.removeValue(forKey: label)
            persistAliases()
            AppsOnAirPush.log("Alias removed: \(label)", level: .debug)
        }

        /// Remove multiple aliases by label.
        public static func removeAliases(_ labels: [String]) {
            labels.forEach { AppsOnAirPush.shared.aliases.removeValue(forKey: $0) }
            persistAliases()
        }

        // MARK: - Email

        /// Associate an email address with this user for multi-channel messaging.
        public static func addEmail(_ address: String) {
            guard !address.isEmpty, !AppsOnAirPush.shared.emails.contains(address) else { return }
            AppsOnAirPush.shared.emails.append(address)
            persistEmails()
            AppsOnAirPush.log("Email added: \(address)", level: .debug)
        }

        /// Remove an email address association.
        public static func removeEmail(_ address: String) {
            AppsOnAirPush.shared.emails.removeAll { $0 == address }
            persistEmails()
            AppsOnAirPush.log("Email removed: \(address)", level: .debug)
        }

        // MARK: - SMS (AOA:Future — not covered in push SDK scope, will be added in a future release)

        // public static func addSms(_ number: String) {
        //     guard !number.isEmpty, !AppsOnAirPush.shared.smsNumbers.contains(number) else { return }
        //     AppsOnAirPush.shared.smsNumbers.append(number)
        //     persistSmsNumbers()
        //     AppsOnAirPush.log("SMS number added: \(number)", level: .debug)
        // }

        // public static func removeSms(_ number: String) {
        //     AppsOnAirPush.shared.smsNumbers.removeAll { $0 == number }
        //     persistSmsNumbers()
        //     AppsOnAirPush.log("SMS number removed: \(number)", level: .debug)
        // }

        // MARK: - User State Observer

        public static func addObserver(_ observer: UserStateObserver) {
            AppsOnAirPush.shared.userStateObservers.append(observer)
        }

        public static func removeObserver(_ observer: UserStateObserver) {
            AppsOnAirPush.shared.userStateObservers.removeAll { $0 === observer }
        }

        // MARK: - Private persistence helpers

        private static func persistTags() {
            if let data = try? JSONEncoder().encode(AppsOnAirPush.shared.tags) {
                UserDefaults.standard.set(data, forKey: "com.appsonair.push.tags")
            }
        }

        private static func persistAliases() {
            if let data = try? JSONEncoder().encode(AppsOnAirPush.shared.aliases) {
                UserDefaults.standard.set(data, forKey: "com.appsonair.push.aliases")
            }
        }

        private static func persistEmails() {
            if let data = try? JSONEncoder().encode(AppsOnAirPush.shared.emails) {
                UserDefaults.standard.set(data, forKey: "com.appsonair.push.emails")
            }
        }

        // private static func persistSmsNumbers() {
        //     if let data = try? JSONEncoder().encode(AppsOnAirPush.shared.smsNumbers) {
        //         UserDefaults.standard.set(data, forKey: "com.appsonair.push.smsNumbers")
        //     }
        // }
    }
}
