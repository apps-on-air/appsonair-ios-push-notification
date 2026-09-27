import SwiftUI
import AppsOnAir_AppPush

// MARK: - InputView
// Separate screen for SDK calls that require user-supplied text input.

struct InputView: View {

    var onCopied: () -> Void

    // MARK: Login
    @State private var loginId = ""
    @State private var loginResult = ""

    // MARK: Tag
    @State private var tagKey = ""
    @State private var tagValue = ""
    @State private var tagResult = ""

    // MARK: Remove Tag
    @State private var removeTagKey = ""
    @State private var removeTagResult = ""

    // MARK: Alias
    @State private var aliasLabel = ""
    @State private var aliasId = ""
    @State private var aliasResult = ""

    // MARK: Remove Alias
    @State private var removeAliasLabel = ""
    @State private var removeAliasResult = ""

    // MARK: Email
    @State private var emailAddress = ""
    @State private var emailResult = ""

    // MARK: Remove Email
    @State private var removeEmail = ""
    @State private var removeEmailResult = ""

    // MARK: Language
    @State private var languageCode = ""
    @State private var languageResult = ""

    // MARK: Badge
    @State private var badgeValue = ""
    @State private var badgeResult = ""

    // MARK: Notification ID
    @State private var notifId = ""
    @State private var notifResult = ""

    // MARK: APNs Token (re-register)
    @State private var reRegisterResult = ""

    var body: some View {
        List {
            loginSection
            addTagSection
            removeTagSection
            addAliasSection
            removeAliasSection
            addEmailSection
            removeEmailSection
            languageSection
            setBadgeSection
            removeNotifSection
            reRegisterSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Input")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Login

    private var loginSection: some View {
        Section {
            TextField("External User ID", text: $loginId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button("Login") {
                    guard !loginId.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    AppPushService.login(loginId.trimmingCharacters(in: .whitespaces))
                    loginResult = "logged in → \(loginId)"
                }
                .buttonStyle(.borderedProminent)
                .disabled(loginId.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Logout") {
                    AppPushService.logout()
                    loginResult = "logged out"
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            resultRow(loginResult)
        } header: {
            Text("Login / Logout")
        }
    }

    // MARK: - Add Tag

    private var addTagSection: some View {
        Section("Add Tag") {
            TextField("Key", text: $tagKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Value", text: $tagValue)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add Tag") {
                let k = tagKey.trimmingCharacters(in: .whitespaces)
                let v = tagValue.trimmingCharacters(in: .whitespaces)
                guard !k.isEmpty, !v.isEmpty else { return }
                AppPushService.User.addTag(key: k, value: v)
                tagResult = "added \(k)=\(v)"
            }
            .buttonStyle(.borderedProminent)
            .disabled(tagKey.trimmingCharacters(in: .whitespaces).isEmpty ||
                      tagValue.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(tagResult)
        }
    }

    // MARK: - Remove Tag

    private var removeTagSection: some View {
        Section("Remove Tag") {
            TextField("Key", text: $removeTagKey)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Remove Tag") {
                let k = removeTagKey.trimmingCharacters(in: .whitespaces)
                guard !k.isEmpty else { return }
                AppPushService.User.removeTag(k)
                removeTagResult = "removed \(k)"
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(removeTagKey.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(removeTagResult)
        }
    }

    // MARK: - Add Alias

    private var addAliasSection: some View {
        Section("Add Alias") {
            TextField("Label (e.g. crm_id)", text: $aliasLabel)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("ID value", text: $aliasId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add Alias") {
                let l = aliasLabel.trimmingCharacters(in: .whitespaces)
                let i = aliasId.trimmingCharacters(in: .whitespaces)
                guard !l.isEmpty, !i.isEmpty else { return }
                AppPushService.User.addAlias(label: l, id: i)
                aliasResult = "added \(l)=\(i)"
            }
            .buttonStyle(.borderedProminent)
            .disabled(aliasLabel.trimmingCharacters(in: .whitespaces).isEmpty ||
                      aliasId.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(aliasResult)
        }
    }

    // MARK: - Remove Alias

    private var removeAliasSection: some View {
        Section("Remove Alias") {
            TextField("Label", text: $removeAliasLabel)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Remove Alias") {
                let l = removeAliasLabel.trimmingCharacters(in: .whitespaces)
                guard !l.isEmpty else { return }
                AppPushService.User.removeAlias(l)
                removeAliasResult = "removed \(l)"
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(removeAliasLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(removeAliasResult)
        }
    }

    // MARK: - Add Email

    private var addEmailSection: some View {
        Section("Add Email") {
            TextField("Email address", text: $emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add Email") {
                let e = emailAddress.trimmingCharacters(in: .whitespaces)
                guard !e.isEmpty else { return }
                AppPushService.User.addEmail(e)
                emailResult = "added \(e)"
            }
            .buttonStyle(.borderedProminent)
            .disabled(emailAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(emailResult)
        }
    }

    // MARK: - Remove Email

    private var removeEmailSection: some View {
        Section("Remove Email") {
            TextField("Email address", text: $removeEmail)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Remove Email") {
                let e = removeEmail.trimmingCharacters(in: .whitespaces)
                guard !e.isEmpty else { return }
                AppPushService.User.removeEmail(e)
                removeEmailResult = "removed \(e)"
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(removeEmail.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(removeEmailResult)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            TextField("ISO 639-1 code (e.g. en, fr, de)", text: $languageCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            HStack {
                Button("Set Language") {
                    let c = languageCode.trimmingCharacters(in: .whitespaces)
                    guard !c.isEmpty else { return }
                    AppPushService.User.setLanguage(c)
                    languageResult = "language = \(c)"
                }
                .buttonStyle(.borderedProminent)
                .disabled(languageCode.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Get") {
                    languageResult = AppPushService.User.language
                }
                .buttonStyle(.bordered)
            }
            resultRow(languageResult)
        } header: {
            Text("Language")
        }
    }

    // MARK: - Set Badge

    private var setBadgeSection: some View {
        Section("Set Badge Count") {
            TextField("Badge count (integer)", text: $badgeValue)
                .keyboardType(.numberPad)
            Button("Set Badge") {
                guard let n = Int(badgeValue.trimmingCharacters(in: .whitespaces)) else { return }
                AppPushService.setBadgeCount(n)
                badgeResult = "badge = \(n)"
            }
            .buttonStyle(.borderedProminent)
            .disabled(Int(badgeValue.trimmingCharacters(in: .whitespaces)) == nil)
            resultRow(badgeResult)
        }
    }

    // MARK: - Remove Notification by ID

    private var removeNotifSection: some View {
        Section {
            TextField("Notification identifier", text: $notifId)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Remove Notification") {
                let i = notifId.trimmingCharacters(in: .whitespaces)
                guard !i.isEmpty else { return }
                AppPushService.Notifications.removeNotification(withIdentifier: i)
                notifResult = "removed \(i)"
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(notifId.trimmingCharacters(in: .whitespaces).isEmpty)
            resultRow(notifResult)
        } header: {
            Text("Remove Notification by ID")
        }
    }

    // MARK: - Re-register for APNs

    private var reRegisterSection: some View {
        Section {
            Button("Re-register for Remote Notifications") {
                UIApplication.shared.registerForRemoteNotifications()
                reRegisterResult = "re-registration triggered — check Live Events"
            }
            .buttonStyle(.borderedProminent)
            resultRow(reRegisterResult)
        } header: {
            Text("APNs Token")
        } footer: {
            Text("Triggers a fresh registerForRemoteNotifications call. New token appears in Live Events on the main screen.")
        }
    }

    // MARK: - Result row helper

    @ViewBuilder
    private func resultRow(_ value: String) -> some View {
        if !value.isEmpty {
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
        }
    }
}
