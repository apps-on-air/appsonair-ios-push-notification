import SwiftUI
import AppsOnAir_AppPush

// MARK: - Helpers

/// A single row: title on top, monospaced green result below + optional Copy button.
private struct QARow: View {
    let title: String
    var result: String? = nil
    var onCopy: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                if let r = result, !r.isEmpty {
                    Text(r)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if let r = result, !r.isEmpty, let copy = onCopy {
                Button("Copy") {
                    UIPasteboard.general.string = r
                    copy()
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Shows a "✓ Copied" toast overlay.
private struct CopiedToast: View {
    var body: some View {
        Text("✓  Copied to clipboard")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.green.opacity(0.92))
            .clipShape(Capsule())
    }
}

// MARK: - ContentView

struct ContentView: View {

    @StateObject private var state = SDKState.shared
    @State private var showToast = false
    @State private var toastWork: DispatchWorkItem?

    // Per-row result storage: [key: resultString]
    @State private var results: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                identitySection
                permissionSection
                loginSection
                tagsSection
                aliasesSection
                emailSection
                languageSection
                subscriptionSection
                badgeSection
                notificationsSection
                debugSection
                backgroundSyncSection
                liveEventsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AppsOnAir Push — SwiftUI")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink("Input") {
                        InputView(onCopied: triggerToast)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .overlay(alignment: .bottom) {
                if showToast {
                    CopiedToast()
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3), value: showToast)
        }
        .onAppear { refreshIdentity() }
    }

    // MARK: - Toast

    private func triggerToast() {
        toastWork?.cancel()
        withAnimation { showToast = true }
        let work = DispatchWorkItem {
            withAnimation { showToast = false }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        triggerToast()
    }

    // MARK: - Identity

    private func refreshIdentity() {
        state.deviceId = AppPushService.deviceId
        state.subscriptionId = AppPushService.subscriptionId ?? ""
        state.apnsEnvironment = AppPushService.apnsEnvironment == .sandbox ? "sandbox" : "production"
        state.externalId = AppPushService.User.externalId ?? ""

        // Pre-fill APNs token from stored subscription token so it shows on first open
        // without waiting for the async onAPNsTokenUpdated callback.
        if state.apnsToken.isEmpty, let token = AppPushService.User.pushSubscription.token {
            state.apnsToken = token
        }

        // Pre-fill permission so "Current Permission" shows on launch, not only on change.
        if state.permissionGranted.isEmpty {
            let perm = AppPushService.Notifications.permissionNative
            switch perm {
            case .authorized:  state.permissionGranted = "granted"
            case .provisional: state.permissionGranted = "provisional"
            case .ephemeral:   state.permissionGranted = "ephemeral"
            case .denied:      state.permissionGranted = "denied"
            default:           state.permissionGranted = "not determined"
            }
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        Section {
            tapRow(key: "identity_0", title: "Device ID") {
                let v = AppPushService.deviceId
                state.deviceId = v
                return v
            } onCopy: { copy(state.deviceId) }

            tapRow(key: "identity_1", title: "Subscription ID") {
                let v = AppPushService.subscriptionId ?? "(nil)"
                state.subscriptionId = v
                return v
            } onCopy: { copy(state.subscriptionId) }

            // APNs Token — updated live from PushListener
            QARow(
                title: "APNs Token",
                result: state.apnsToken.isEmpty ? nil : state.apnsToken,
                onCopy: state.apnsToken.isEmpty ? nil : { copy(state.apnsToken) }
            )

            tapRow(key: "identity_3", title: "APNs Environment") {
                let v = AppPushService.apnsEnvironment == .sandbox ? "sandbox" : "production"
                state.apnsEnvironment = v
                return v
            } onCopy: { copy(state.apnsEnvironment) }

            // External ID — also updated live by UserStateObserver
            QARow(
                title: "External ID",
                result: state.externalId.isEmpty ? nil : state.externalId
            )

            tapRow(key: "identity_5", title: "Set Test Device ON") {
                AppPushService.isTestDevice = true
                return "isTestDevice = true"
            }
            tapRow(key: "identity_6", title: "Set Test Device OFF") {
                AppPushService.isTestDevice = false
                return "isTestDevice = false"
            }
            tapRow(key: "identity_7", title: "Consent Required ON / Given ON") {
                AppPushService.consentRequired = true
                AppPushService.consentGiven = true
                return "consentRequired=true, consentGiven=true"
            }
        } header: {
            Text("Identity")
        } footer: {
            Text("Tap to read. Tap Copy to copy value to clipboard.")
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        Section {
            // Updated live by NotificationPermissionObserver in AppDelegate
            QARow(
                title: "Current Permission",
                result: state.permissionGranted.isEmpty ? nil : state.permissionGranted
            )
            tapRow(key: "perm_1", title: "Native Permission Status") {
                let perm = AppPushService.Notifications.permissionNative
                let names = ["notDetermined", "denied", "authorized", "provisional", "ephemeral"]
                let idx = Int(perm.rawValue)
                return names.indices.contains(idx) ? names[idx] : "unknown"
            }
            tapRow(key: "perm_2", title: "Can Request Permission") {
                return AppPushService.Notifications.canRequestPermission ? "YES" : "NO"
            }
            tapRow(key: "perm_3", title: "Request Permission") {
                AppPushService.Notifications.requestPermission()
                return "requested"
            }
            tapRow(key: "perm_4", title: "Request Permission (fallback to Settings)") {
                AppPushService.Notifications.requestPermission(fallbackToSettings: true)
                return "requested (fallback=true)"
            }
            tapRow(key: "perm_5", title: "Register Provisional Authorization") {
                AppPushService.Notifications.registerForProvisionalAuthorization()
                return "provisional requested"
            }
            asyncRow(key: "perm_6", title: "Refresh Permission  ⟳", pending: "refreshing…") { done in
                Task {
                    let granted = await AppPushService.Notifications.refreshPermission()
                    done(granted ? "refreshed → granted" : "refreshed → not granted")
                }
            }
            asyncRow(key: "perm_7", title: "Is Permission Granted (async)  ⟳", pending: "checking…") { done in
                Task {
                    let granted = await AppPushService.isPermissionGranted()
                    done(granted ? "YES" : "NO")
                }
            }
        } header: {
            Text("Permission")
        } footer: {
            Text("Async rows update automatically when the callback fires.")
        }
    }

    // MARK: - Login / Logout

    @ViewBuilder
    private var loginSection: some View {
        Section("User — Login / Logout") {
            tapRow(key: "login_0", title: "Login (user_swift_123)") {
                AppPushService.login("user_swift_123")
                return "logged in → user_swift_123"
            }
            tapRow(key: "login_1", title: "Logout") {
                AppPushService.logout()
                return "logged out"
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags") {
            tapRow(key: "tags_0", title: "Add Tag (plan=premium)") {
                AppPushService.User.addTag(key: "plan", value: "premium")
                return "added plan=premium"
            }
            tapRow(key: "tags_1", title: "Add Tags (genre=action, rated=PG)") {
                AppPushService.User.addTags(["genre": "action", "rated": "PG"])
                return "added genre=action, rated=PG"
            }
            tapRow(key: "tags_2", title: "Remove Tag (plan)") {
                AppPushService.User.removeTag("plan")
                return "removed plan"
            }
            tapRow(key: "tags_3", title: "Remove Tags (genre, rated)") {
                AppPushService.User.removeTags(["genre", "rated"])
                return "removed genre, rated"
            }
            tapRow(key: "tags_4", title: "Get Tags (local cache)") {
                let tags = AppPushService.User.getTags()
                return tags.isEmpty
                    ? "(empty)"
                    : tags.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            }
            asyncRow(key: "tags_5", title: "Fetch Tags from Backend  ⟳", pending: "fetching…") { done in
                AppPushService.User.getTags { tags in
                    let result = tags.isEmpty
                        ? "(empty)"
                        : tags.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                    done(result)
                }
            }
        }
    }

    // MARK: - Aliases

    @ViewBuilder
    private var aliasesSection: some View {
        Section("Aliases") {
            tapRow(key: "alias_0", title: "Add Alias (crm_id=CRM-999)") {
                AppPushService.User.addAlias(label: "crm_id", id: "CRM-999")
                return "added crm_id=CRM-999"
            }
            tapRow(key: "alias_1", title: "Add Aliases (fb_id=FB-1, tw_id=TW-2)") {
                AppPushService.User.addAliases(["fb_id": "FB-1", "tw_id": "TW-2"])
                return "added fb_id=FB-1, tw_id=TW-2"
            }
            tapRow(key: "alias_2", title: "Remove Alias (crm_id)") {
                AppPushService.User.removeAlias("crm_id")
                return "removed crm_id"
            }
            tapRow(key: "alias_3", title: "Remove Aliases (fb_id, tw_id)") {
                AppPushService.User.removeAliases(["fb_id", "tw_id"])
                return "removed fb_id, tw_id"
            }
            tapRow(key: "alias_4", title: "Get Aliases (local cache)") {
                let aliases = AppPushService.User.getAliases()
                return aliases.isEmpty
                    ? "(empty)"
                    : aliases.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            }
            asyncRow(key: "alias_5", title: "Fetch Aliases from Backend  ⟳", pending: "fetching…") { done in
                AppPushService.User.getAliases { aliases in
                    let result = aliases.isEmpty
                        ? "(empty)"
                        : aliases.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
                    done(result)
                }
            }
        }
    }

    // MARK: - Email

    @ViewBuilder
    private var emailSection: some View {
        Section {
            tapRow(key: "email_0", title: "Add Email (qa@appsonair.com)") {
                AppPushService.User.addEmail("qa@appsonair.com")
                return "added qa@appsonair.com"
            }
            tapRow(key: "email_1", title: "Remove Email (qa@appsonair.com)") {
                AppPushService.User.removeEmail("qa@appsonair.com")
                return "removed qa@appsonair.com"
            }
            tapRow(key: "email_2", title: "Get Emails (local cache)") {
                let emails = AppPushService.User.getEmails()
                return emails.isEmpty ? "(empty)" : emails.joined(separator: ", ")
            }
        } header: {
            Text("Email")
        } footer: {
            Text("Add/Remove patches the subscription with the full current email list.")
        }
    }

    // MARK: - Language

    @ViewBuilder
    private var languageSection: some View {
        Section("Language") {
            tapRow(key: "lang_0", title: "Set Language (fr)") {
                AppPushService.User.setLanguage("fr")
                return "language = fr"
            }
            tapRow(key: "lang_1", title: "Set Language (en)") {
                AppPushService.User.setLanguage("en")
                return "language = en"
            }
            tapRow(key: "lang_2", title: "Get Language") {
                return AppPushService.User.language
            }
        }
    }

    // MARK: - Subscription

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            tapRow(key: "sub_0", title: "Opt Out") {
                AppPushService.User.pushSubscription.optOut()
                return "opted out"
            }
            tapRow(key: "sub_1", title: "Opt In") {
                AppPushService.User.pushSubscription.optIn()
                return "opted in"
            }
            // Updated live by PushSubscriptionObserver in AppDelegate
            QARow(
                title: "Push Subscription Opted In?",
                result: state.optedIn.isEmpty ? nil : state.optedIn
            )
            tapRow(key: "sub_3", title: "Push Subscription Token") {
                return AppPushService.User.pushSubscription.token ?? "(nil)"
            } onCopy: {
                if let v = AppPushService.User.pushSubscription.token { copy(v) }
            }
        } header: {
            Text("Subscription")
        } footer: {
            Text("Observer row updates live when subscription state changes.")
        }
    }

    // MARK: - Badge

    @ViewBuilder
    private var badgeSection: some View {
        Section("Badge") {
            tapRow(key: "badge_0", title: "Set Badge (5)") {
                AppPushService.setBadgeCount(5)
                return "badge = 5"
            }
            tapRow(key: "badge_1", title: "Increment Badge (+1)") {
                let next = AppPushService.incrementBadgeCount(by: 1)
                return "badge → \(next)"
            }
            tapRow(key: "badge_2", title: "Decrement Badge (-1)") {
                let next = AppPushService.incrementBadgeCount(by: -1)
                return "badge → \(next)"
            }
            tapRow(key: "badge_3", title: "Clear Badge") {
                AppPushService.clearBadgeCount()
                return "badge cleared"
            }
            tapRow(key: "badge_4", title: "Get Badge Count") {
                return "badge = \(AppPushService.badgeCount)"
            }
            tapRow(key: "badge_5", title: "Auto Clear Badge ON") {
                AppPushService.autoClearBadgeOnForeground = true
                return "autoClear = true"
            }
            tapRow(key: "badge_6", title: "Auto Clear Badge OFF") {
                AppPushService.autoClearBadgeOnForeground = false
                return "autoClear = false"
            }
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            tapRow(key: "notif_0", title: "Clear All Notifications") {
                AppPushService.Notifications.clearAllNotifications()
                return "cleared all"
            }
            tapRow(key: "notif_1", title: "Remove Notification (id=test-notif-1)") {
                AppPushService.Notifications.removeNotification(withIdentifier: "test-notif-1")
                return "removed test-notif-1"
            }
            tapRow(key: "notif_2", title: "Remove Notifications (test-1, test-2)") {
                AppPushService.Notifications.removeNotifications(withIdentifiers: ["test-1", "test-2"])
                return "removed test-1, test-2"
            }
        }
    }

    // MARK: - Debug

    @ViewBuilder
    private var debugSection: some View {
        Section("Debug") {
            tapRow(key: "debug_0", title: "Set Log Level: Verbose") {
                AppPushService.Debug.logLevel = .verbose
                return "logLevel = verbose"
            }
            tapRow(key: "debug_1", title: "Set Log Level: Debug") {
                AppPushService.Debug.logLevel = .debug
                return "logLevel = debug"
            }
            tapRow(key: "debug_2", title: "Set Log Level: None") {
                AppPushService.Debug.logLevel = .none
                return "logLevel = none"
            }
            tapRow(key: "debug_3", title: "Get Log Level") {
                let names: [LogLevel: String] = [
                    .none: "none", .fatal: "fatal", .error: "error",
                    .warn: "warn", .info: "info", .debug: "debug", .verbose: "verbose"
                ]
                return names[AppPushService.Debug.logLevel] ?? "unknown"
            }
        }
    }

    // MARK: - Background Sync

    @ViewBuilder
    private var backgroundSyncSection: some View {
        Section("Background Sync") {
            tapRow(key: "bg_0", title: "Register Handlers") {
                AppsOnAirBackgroundSync.registerHandlers()
                return "handlers registered"
            }
            tapRow(key: "bg_1", title: "Schedule Sync (default 15 min)") {
                AppsOnAirBackgroundSync.scheduleIfNeeded()
                return "scheduled (default 15 min)"
            }
            tapRow(key: "bg_2", title: "Schedule Sync (30 min)") {
                AppsOnAirBackgroundSync.scheduleIfNeeded(minimumDelay: 30 * 60)
                return "scheduled (30 min)"
            }
            tapRow(key: "bg_3", title: "Cancel Pending Sync") {
                AppsOnAirBackgroundSync.cancelPending()
                return "cancelled"
            }
            tapRow(key: "bg_4", title: "Task Identifier") {
                return AppsOnAirBackgroundSync.taskIdentifier
            }
        }
    }

    // MARK: - Live Events

    @ViewBuilder
    private var liveEventsSection: some View {
        Section {
            QARow(
                title: "APNs Token Updated",
                result: state.liveTokenEvent.isEmpty ? nil : state.liveTokenEvent,
                onCopy: state.liveTokenEvent.isEmpty ? nil : { copy(state.apnsToken) }
            )
            QARow(
                title: "Notification Received (foreground)",
                result: state.liveReceivedEvent.isEmpty ? nil : state.liveReceivedEvent
            )
            QARow(
                title: "Notification Opened",
                result: state.liveOpenedEvent.isEmpty ? nil : state.liveOpenedEvent
            )
            QARow(
                title: "SDK Error",
                result: state.liveErrorEvent.isEmpty ? nil : state.liveErrorEvent
            )
            QARow(
                title: "Silent Push Received",
                result: state.liveSilentPushEvent.isEmpty ? nil : state.liveSilentPushEvent
            )
        } header: {
            Text("Live Events (PushListener)")
        } footer: {
            Text("Rows update automatically when SDK listener callbacks fire.")
        }
    }

    // MARK: - Row builder helpers

    @ViewBuilder
    private func tapRow(
        key: String,
        title: String,
        action: @escaping @MainActor () -> String,
        onCopy: (() -> Void)? = nil
    ) -> some View {
        QARow(title: title, result: results[key], onCopy: results[key] != nil ? onCopy : nil)
            .contentShape(Rectangle())
            .onTapGesture {
                results[key] = action()
            }
    }

    @ViewBuilder
    private func asyncRow(
        key: String,
        title: String,
        pending: String,
        action: @escaping (@escaping (String) -> Void) -> Void
    ) -> some View {
        QARow(title: title, result: results[key])
            .contentShape(Rectangle())
            .onTapGesture {
                results[key] = pending
                action { result in
                    DispatchQueue.main.async { results[key] = result }
                }
            }
    }
}
