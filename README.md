# AppsOnAir-AppPush — iOS SDK

Add push notifications to your iOS app in minutes. The SDK handles APNs device registration, permission management, rich media attachments, badge tracking, and analytics (delivered, opened, clicked) out of the box — with no Firebase dependency.

- **User targeting** — segment by tags, language, aliases, and email
- **Rich notifications** — images, videos, action buttons, and text overrides via a Notification Service Extension
- **Analytics** — delivered, opened, and clicked events tracked automatically across foreground, background, and killed states
- **Flexible** — works with UIKit, SwiftUI, and Objective-C; swizzling is optional

> [!WARNING]
> **Beta release — not for production use.**
>
> `1.0.2-beta` is an early access release intended for evaluation, integration testing, and
> prototype builds. Do not ship this version in a production app or a build with a large user base.
>
> - The public API may change between releases without a deprecation period.
> - Breaking changes are not restricted to major versions while the SDK is in beta.
> - Behavior in production-scale environments has not been fully validated.
>
> Use a patch-permissive constraint so patch releases flow through automatically, and re-test
> your integration on every upgrade.

For full documentation visit [documentation.appsonair.com](https://documentation.appsonair.com).

---

## Platform Compatibility

| Platform | Support | Notes |
|---|---|---|
| **Swift (UIKit)** | ✅ Full | Native API — recommended |
| **Swift (SwiftUI)** | ✅ Full | Use `@UIApplicationDelegateAdaptor` — see Quick Start |
| **Objective-C** | ✅ Full | Complete `AOA*` facade for all main app APIs. NSE: use `AOAPushExtension`. CE: subclass `AOAContentViewController` |
| **Flutter** | ✅ Full | Use the dedicated [AppsOnAir Flutter SDK](https://documentation.appsonair.com) |
| **React Native** | ✅ Full | Use the dedicated [AppsOnAir React Native SDK](https://documentation.appsonair.com) |

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Apple Setup](#apple-setup)
4. [Quick Start](#quick-start)
5. [Debug Logging](#debug-logging)
6. [User Identity](#user-identity)
7. [User Namespace](#user-namespace)
8. [Notifications Namespace](#notifications-namespace)
9. [Badge Count](#badge-count)
10. [GDPR Consent](#gdpr-consent)
11. [Silent Push](#silent-push)
12. [Swizzling](#swizzling)
13. [Notification Service Extension](#notification-service-extension)
14. [Notification Content Extension](#notification-content-extension)
15. [Background Fetch](#background-fetch)
16. [Push Payload Reference](#push-payload-reference)
17. [Full API Reference](#full-api-reference)
18. [PushListener Protocol](#pushlistener-protocol)
19. [Error Codes](#error-codes)
20. [Simulator Notes](#simulator-notes)
21. [Troubleshooting](#troubleshooting)

---

## Requirements

| | Minimum |
|---|---|
| iOS | 15.0 |
| Xcode | 16+ |
| Swift | 6.2 (SPM) · 5.9 (CocoaPods) |
| Objective-C | Fully supported via `AOA*` facade classes |

---

## Installation

The SDK ships three products. Link the right one to each target — **never add NSE or CE products to the main app target**:

| Product | Link to | SPM name | CocoaPods |
|---|---|---|---|
| Main app SDK | Main app target | `AppsOnAir-AppPush` | `AppsOnAir-AppPush` |
| Notification Service Extension | NSE target only | `AppsOnAir-AppPush-ServiceExt` | SPM only — see CocoaPods note below |
| Notification Content Extension | CE target only | `AppsOnAir-AppPush-ContentExt` | SPM only — see CocoaPods note below |

### Swift Package Manager

In Xcode: **File → Add Package Dependencies** → enter the repository URL:

```
https://github.com/apps-on-air/appsonair-ios-push-notification
```

Set the version rule to **Up to Next Minor Version** from `1.0.2-beta` — this accepts patch releases automatically and blocks minor bumps (`1.1+`) that may carry breaking changes. Link products per the table above.

### CocoaPods

> [!WARNING]
> **CocoaPods is winding down active development.** Swift Package Manager (SPM) is the recommended integration method — zero warnings, explicit product linking, and fully supported by Apple.
>
> **NSE and CE targets must use SPM, not CocoaPods.** All subspecs compile into the same `AppsOnAir_AppPush` framework. Adding the `ServiceExtension` or `ContentExtension` subspec via CocoaPods causes Xcode archive to fail with _"Multiple commands produce AppsOnAir_AppPush.framework"_ — blocking App Store submission. This is a known CocoaPods limitation with no fix in a single-podspec setup.
>
> **You can mix CocoaPods and SPM in the same project.** Add `AppsOnAir-AppPush` via CocoaPods for your main app, then add the SDK repo via **File → Add Package Dependencies** in Xcode and link `AppsOnAir-AppPush-ServiceExt` / `AppsOnAir-AppPush-ContentExt` to your NSE/CE targets only.

```ruby
# '>= 1.0.2-beta', '< 1.1' — accepts patch releases automatically; blocks minor bumps.
# CocoaPods: main app target only.
# Add NSE and CE targets via SPM (see warning above).
target 'MyApp' do
  pod 'AppsOnAir-AppPush', '>= 1.0.2-beta', '< 1.1'
end
```

---

## Apple Setup

1. **Push Notifications capability**
   Target → Signing & Capabilities → + Capability → Push Notifications

2. **Background Modes**
   + Capability → Background Modes → check **Remote notifications**

3. **App ID in Info.plist** (main app target only)
   ```xml
   <key>AppsonairAppId</key>
   <string>your-app-id-here</string>
   ```

4. Use a **real device** for push testing — APNs tokens don't exist on simulator (the SDK emits a mock token so the rest of your flow still works).

---

## Quick Start

### Swift — UIKit AppDelegate

```swift
import AppsOnAir_AppPush

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        AppPushService.Debug.logLevel = .verbose       // development only — remove for production
        AppsOnAirBackgroundSync.registerHandlers()     // must be called before any scene connects
        AppPushService.initialize(debug: true)         // set debug: false for production
        AppPushService.setListener(self)
        AppPushService.requestPermission()
        AppsOnAirBackgroundSync.scheduleIfNeeded()
        return true
    }
}

extension AppDelegate: PushListener {

    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) {
        // No action required — the SDK automatically registers this device.
        // setSubscriptionId() is only needed if you want to set a value manually.
    }

    func onNotificationReceived(notification: PushNotification) {
        print("Foreground push: \(notification.title ?? "")")
    }

    func onNotificationOpened(notification: PushNotification) {
        // Navigate using notification.id or notification.userInfo
    }

    func onError(_ error: PushError) {
        print("[\(error.code)] \(error.message)")
    }
}
```

### Swift — SwiftUI

```swift
import SwiftUI
import AppsOnAir_AppPush

@main
struct MyApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppsOnAirBackgroundSync.registerHandlers()
        AppPushService.initialize(debug: true)         // set debug: false for production
        AppPushService.setListener(self)
        AppPushService.requestPermission()
        AppsOnAirBackgroundSync.scheduleIfNeeded()
        return true
    }
}

extension AppDelegate: PushListener {
    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) { }
    func onNotificationReceived(notification: PushNotification) { }
    func onNotificationOpened(notification: PushNotification) { }
    func onError(_ error: PushError) { }
}
```

### Objective-C

```objc
// AppDelegate.h
#import <UIKit/UIKit.h>
@import AppsOnAir_AppPush;

@interface AppDelegate : UIResponder <UIApplicationDelegate, AOAPushListener>
@property (strong, nonatomic) UIWindow *window;
@end
```

```objc
// AppDelegate.m
#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [AOAPushDebug setLogLevel:AOALogLevelVerbose];       // development only — remove for production
    [AOAPushBackgroundSync registerHandlers];            // must be called before any scene connects
    [AOAPush initializeWithDebug:YES swizzle:YES];      // set NO for production
    [AOAPush setListener:self];
    [AOAPushNotifications requestPermission];
    [AOAPushBackgroundSync scheduleIfNeeded];
    return YES;
}

// Silent push — wakes the app in the background for lightweight work (≤ 30 s)
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    [AOAPush handleSilentPush:userInfo fetchCompletionHandler:completionHandler];
}

// AOAPushListener — all methods are @optional
- (void)onAPNsTokenUpdatedWithToken:(NSString *)token
                        environment:(AOAAPNsEnvironment)environment {
    // SDK registers this device automatically — no action required.
    // Call [AOAPush setSubscriptionId:@"..."] only if you need a manual override.
}

- (void)onNotificationReceivedWithNotification:(AOAPushNotification *)notification {
    NSLog(@"Foreground push: %@", notification.title);
}

- (void)onNotificationOpenedWithNotification:(AOAPushNotification *)notification {
    // Navigate using notification.identifier or notification.userInfo
}

- (void)onError:(NSError *)error {
    NSLog(@"[%ld] %@", (long)error.code, error.localizedDescription);
}

@end
```

---

## Debug Logging

Set the log level **before** `initialize()` to see startup output.

```swift
// Swift
AppPushService.Debug.logLevel = .verbose
```

```objc
// Objective-C
[AOAPushDebug setLogLevel:AOALogLevelVerbose];
```

| Level | What you see |
|---|---|
| `.none` | Nothing (default for production) |
| `.fatal` | Fatal errors only |
| `.error` | Errors that affect SDK behaviour |
| `.warn` | Unexpected but recoverable situations |
| `.info` | Key lifecycle events |
| `.debug` | Detailed SDK flow |
| `.verbose` | Everything |

---

## User Identity

`login()` links this device to your user's account; `logout()` unlinks it — the device reverts to anonymous and continues receiving pushes.

Call `login` when your user signs in and `logout` when they sign out. Tags, aliases, and language are cleared on logout — the device keeps receiving pushes as an anonymous user until the next login.

```swift
// Swift
AppPushService.login("user_12345")   // call when your user signs in
AppPushService.logout()              // call on sign-out — clears tags and aliases
```

```objc
// Objective-C
[AOAPush login:@"user_12345"];
[AOAPush logout];
```

---

## User Namespace

User data attached to this device — tags for segmentation, language for localised sends, aliases to match your CRM records, email addresses, and the push subscription state (opt-in/opt-out).

### Tags

Key-value strings attached to a user for audience segmentation — `plan`, `region`, `tier`, etc. Both sync operations (add/remove) and reads are available.

```swift
// Swift
AppPushService.User.addTag(key: "plan", value: "premium")
AppPushService.User.addTags(["plan": "premium", "region": "us"])
AppPushService.User.removeTag("plan")
AppPushService.User.removeTags(["plan", "region"])

// Synchronous — returns locally stored tags
let tags = AppPushService.User.getTags()

// Async — fetches latest tags from the server
AppPushService.User.getTags { tags in
    print(tags)
}
```

```objc
// Objective-C
[AOAPushUser addTagWithKey:@"plan" value:@"premium"];
[AOAPushUser addTags:@{@"plan": @"premium", @"region": @"us"}];
[AOAPushUser removeTag:@"plan"];
[AOAPushUser removeTags:@[@"plan", @"region"]];

// Synchronous — returns locally stored tags
NSDictionary *tags = [AOAPushUser getTags];

// Async — fetches latest tags from the server
[AOAPushUser fetchTagsFromBackendWithCompletion:^(NSDictionary *tags) {
    NSLog(@"%@", tags);
}];
```

### Language

Override the device locale for this user. Useful when your backend sends localised content and the device language doesn't match the user's preference. Use ISO 639-1 codes (`"en"`, `"fr"`, `"de"`).

```swift
// Swift
AppPushService.User.setLanguage("fr")  // ISO 639-1 code
let lang = AppPushService.User.language
```

```objc
// Objective-C
[AOAPushUser setLanguage:@"fr"];
NSString *lang = [AOAPushUser language];
```

### Aliases

Map this device to an ID in an external system — CRM, helpdesk, analytics, etc. A label identifies the system (`"crm_id"`, `"hubspot_id"`), the id is the value from that system.

```swift
// Swift
AppPushService.User.addAlias(label: "crm_id", id: "CRM-9876")
AppPushService.User.addAliases(["crm_id": "CRM-9876", "hubspot_id": "HS-42"])
AppPushService.User.removeAlias("crm_id")
AppPushService.User.removeAliases(["crm_id", "hubspot_id"])

// Synchronous — returns locally stored aliases
let aliases = AppPushService.User.getAliases()

// Async — fetches latest aliases from the server
AppPushService.User.getAliases { aliases in
    print(aliases)
}
```

```objc
// Objective-C
[AOAPushUser addAliasWithLabel:@"crm_id" id:@"CRM-9876"];
[AOAPushUser addAliases:@{@"crm_id": @"CRM-9876", @"hubspot_id": @"HS-42"}];
[AOAPushUser removeAlias:@"crm_id"];
[AOAPushUser removeAliases:@[@"crm_id", @"hubspot_id"]];

// Synchronous — returns locally stored aliases
NSDictionary *aliases = [AOAPushUser getAliases];

// Async — fetches latest aliases from the server
[AOAPushUser fetchAliasesFromBackendWithCompletion:^(NSDictionary *aliases) {
    NSLog(@"%@", aliases);
}];
```

### Email

Associate an email address with this user record. Multiple addresses can be added and removed independently.

```swift
// Swift
AppPushService.User.addEmail("user@example.com")
AppPushService.User.removeEmail("user@example.com")
```

```objc
// Objective-C
[AOAPushUser addEmail:@"user@example.com"];
[AOAPushUser removeEmail:@"user@example.com"];
```

### Push Subscription (opt-in / opt-out)

Lets the user stop receiving pushes without revoking OS-level permission. Opt back in at any time and pushes resume immediately.

```swift
// Swift
AppPushService.User.pushSubscription.optOut()   // stop receiving pushes
AppPushService.User.pushSubscription.optIn()

let isOptedIn = AppPushService.User.pushSubscription.optedIn
let token     = AppPushService.User.pushSubscription.token
let subId     = AppPushService.User.pushSubscription.id
```

```objc
// Objective-C
[AOAPushUser optOut];
[AOAPushUser optIn];

BOOL    optedIn = [AOAPushUser pushSubscriptionOptedIn];
NSString *token = [AOAPushUser pushSubscriptionToken];
NSString *subId = [AOAPushUser pushSubscriptionId];
```

### Observers

React to opt-in/out changes and login/logout events without polling. Add observers early — they fire immediately with the current state on first add.

```swift
// Swift

// Observe opt-in / token changes
AppPushService.User.pushSubscription.addObserver(self)
AppPushService.User.pushSubscription.removeObserver(self)

func onPushSubscriptionDidChange(state: PushSubscriptionChangedState) {
    print("optedIn:", state.current.optedIn)
}

// Observe login / logout
AppPushService.User.addObserver(self)
AppPushService.User.removeObserver(self)

func onUserStateDidChange(state: UserChangedState) {
    print(state.current.externalId ?? "anonymous")
}
```

```objc
// Objective-C

// AOAPushSubscriptionObserver
[AOAPushUser addPushSubscriptionObserver:self];
[AOAPushUser removePushSubscriptionObserver:self];

- (void)onPushSubscriptionDidChangeWithState:(AOAPushSubscriptionChangedState *)state {
    NSLog(@"optedIn: %d", state.current.optedIn);
}

// AOAUserStateObserver
[AOAPushUser addUserStateObserver:self];
[AOAPushUser removeUserStateObserver:self];

- (void)onUserStateDidChangeWithState:(AOAUserChangedState *)state {
    NSLog(@"%@", state.current.externalId ?: @"anonymous");
}
```

---

## Notifications Namespace

Handles OS permission requests, foreground display behaviour, click/action callbacks, and removing notifications from the tray.

### Permission

```swift
// Swift
AppPushService.Notifications.requestPermission()
AppPushService.Notifications.requestPermission(fallbackToSettings: true) // opens Settings if denied
AppPushService.Notifications.registerForProvisionalAuthorization()       // iOS 12+ quiet notifications

let granted = AppPushService.Notifications.permission           // Bool, synchronous
let status  = AppPushService.Notifications.permissionNative     // enum — notDetermined / denied / authorized / provisional / ephemeral
let canAsk  = AppPushService.Notifications.canRequestPermission // true when dialog would appear

// Force re-read from the OS
let fresh = await AppPushService.Notifications.refreshPermission()
```

```objc
// Objective-C
[AOAPushNotifications requestPermission];
[AOAPushNotifications requestPermissionWithFallbackToSettings:YES];
[AOAPushNotifications registerForProvisionalAuthorization];

BOOL granted                     = [AOAPushNotifications permission];
AOANotificationPermission status = [AOAPushNotifications permissionNative];
BOOL canAsk                      = [AOAPushNotifications canRequestPermission];

[AOAPushNotifications refreshPermissionWithCompletion:^(BOOL granted) {
    NSLog(@"granted: %d", granted);
}];
```

### Permission Observer

Get notified when the user changes notification permission in Settings. Useful for updating UI that reflects the current permission state.

```swift
// Swift
AppPushService.Notifications.addPermissionObserver(self)
AppPushService.Notifications.removePermissionObserver(self)

func onNotificationPermissionDidChange(_ permission: Bool) { }
```

```objc
// Objective-C — AOANotificationPermissionObserver
[AOAPushNotifications addPermissionObserver:self];
[AOAPushNotifications removePermissionObserver:self];

- (void)onNotificationPermissionDidChange:(BOOL)permission { }
```

### Foreground Display

By default the SDK shows banners even when the app is in the foreground. Add a lifecycle listener to intercept and call `preventDefault()` on any notification you want to handle silently.

This hook controls how the notification is displayed on screen — it has no effect on delivery analytics.

```swift
// Swift
AppPushService.Notifications.addForegroundLifecycleListener(self)
AppPushService.Notifications.removeForegroundLifecycleListener(self)

func onWillDisplay(event: NotificationWillDisplayEvent) {
    // Call preventDefault() to suppress the banner; omit to show it normally
    event.preventDefault()
}
```

```objc
// Objective-C — AOANotificationLifecycleListener
[AOAPushNotifications addForegroundLifecycleListener:self];
[AOAPushNotifications removeForegroundLifecycleListener:self];

- (void)onWillDisplayWithEvent:(AOANotificationWillDisplayEvent *)event {
    [event preventDefault];
}
```

### Click / Open Listener

Fired when the user taps a notification or one of its action buttons. Use `event.result.actionId` to distinguish which button was tapped, and `event.result.url` for deep link handling.

Analytics for opens and clicks are reported automatically — no extra code required.

```swift
// Swift
AppPushService.Notifications.addClickListener(self)
AppPushService.Notifications.removeClickListener(self)

func onClick(event: NotificationClickEvent) {
    print(event.result.actionId ?? "body tap")
    print(event.result.url ?? "")
}
```

```objc
// Objective-C — AOANotificationClickListener
[AOAPushNotifications addClickListener:self];
[AOAPushNotifications removeClickListener:self];

- (void)onClickWithEvent:(AOANotificationClickEvent *)event {
    NSLog(@"action: %@  url: %@",
          event.result.actionId ?: @"body tap",
          event.result.url ?: @"");
}
```

### Remove Notifications

Remove delivered notifications from the tray — all at once or by identifier.

```swift
// Swift
AppPushService.Notifications.clearAllNotifications()
AppPushService.Notifications.removeNotification(withIdentifier: "abc")
AppPushService.Notifications.removeNotifications(withIdentifiers: ["a", "b"])
```

```objc
// Objective-C
[AOAPushNotifications clearAllNotifications];
[AOAPushNotifications removeNotificationWithIdentifier:@"abc"];
[AOAPushNotifications removeNotificationsWithIdentifiers:@[@"a", @"b"]];
```

---

## Badge Count

The SDK tracks a **running total** — each push increments the count rather than overwriting it.

```swift
// Swift
AppPushService.setBadgeCount(5)
AppPushService.incrementBadgeCount(by: 1)   // delta can be negative
AppPushService.clearBadgeCount()
let n = AppPushService.badgeCount

// Auto-clear on foreground (default = true)
AppPushService.autoClearBadgeOnForeground = false  // switch to count-down mode
```

```objc
// Objective-C
[AOAPush setBadgeCount:5];
[AOAPush incrementBadgeCountBy:1];
[AOAPush clearBadgeCount];
NSInteger n = [AOAPush badgeCount];

[AOAPush setAutoClearBadgeOnForeground:NO];
```

**Two badge modes:**

| Mode | `autoClearBadgeOnForeground` | What happens on foreground |
|---|---|---|
| Clear (default) | `true` | Badge resets to 0 whenever the app comes to the foreground |
| Count-down | `false` | Badge stays; decremented by 1 each time the user opens a notification |

Push-driven badge updates (`badge` / `badge_increment` payload keys) work via the Notification Service Extension and require an App Group — see [NSE setup](#notification-service-extension).

---

## GDPR Consent

> **Note:** Consent enforcement is not yet active. The SDK does not yet gate network calls behind these values. Full enforcement is coming in a future release.

Set `consentRequired = true` **before** `initialize()` if your app needs explicit user consent before any data is sent. Consent is persisted — you don't need to set it again on relaunch.

```swift
// Swift — set BEFORE initialize()
AppPushService.consentRequired = true
AppPushService.initialize()
// After the user accepts your consent dialog:
AppPushService.consentGiven = true
```

```objc
// Objective-C
[AOAPush setConsentRequired:YES];   // before initialize
[AOAPush initializeWithDebug:NO swizzle:YES];
[AOAPush setConsentGiven:YES];      // after user accepts
```

---

## Silent Push

A silent push (`content-available: 1`, no alert) wakes the app in the background for up to 30 seconds. Good for lightweight syncs — refresh a badge count, pull new content, update local state — without showing a banner.

```swift
// Swift
AppPushService.onSilentPushReceived = { userInfo, completion in
    // run lightweight background work (≤ 30 s)
    completion(.newData)
}
```

```objc
// Objective-C — UIApplicationDelegate
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler {
    [AOAPush handleSilentPush:userInfo fetchCompletionHandler:handler];
}
```

### Required APNs headers for silent push

Silent push requires specific APNs HTTP/2 headers. Using alert push headers with a silent payload (or vice versa) causes APNs to return 200 OK but iOS silently drops the notification.

| APNs header | Silent push value | Alert push value |
|---|---|---|
| `apns-push-type` | `background` | `alert` |
| `apns-priority` | `5` | `10` |

**Correct silent push payload — no `alert`, no `sound`:**

```json
{
  "aps": {
    "content-available": 1
  },
  "your_key": "your_value"
}
```

> [!IMPORTANT]
> Never mix headers. An alert payload (`apns-push-type: alert`) with `apns-priority: 5` will be dropped. A silent payload (`apns-push-type: background`) with `apns-priority: 10` will be dropped. APNs returns 200 OK in both cases but the device never receives the notification.

### iOS system prerequisites for silent push

These iOS settings must be active on the test device or silent push will never be delivered, regardless of payload or headers:

| Requirement | Where to check |
|---|---|
| **Background App Refresh is ON** | iPhone Settings → General → Background App Refresh → Wi-Fi & Cellular Data |
| **Low Power Mode is OFF** | iPhone Settings → Battery → Low Power Mode (OFF) — iOS suspends silent push entirely in Low Power Mode |
| **App is backgrounded, not force-killed** | Press Home once to background. Do not swipe up in App Switcher — iOS will not wake a force-killed app for silent push |

---

## Swizzling

Swizzling is **on by default** — the SDK hooks APNs token and notification delegate methods automatically. If you initialize with `swizzle: false` you need to forward the callbacks yourself.

```swift
// Swift — swizzle: false
AppPushService.initialize(swizzle: false)

func application(_ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    AppPushService.handleAPNsToken(deviceToken)
}
func application(_ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error) {
    AppPushService.handleAPNsRegistrationError(error)
}
func userNotificationCenter(_ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
    handler(AppPushService.handleWillPresent(notification: notification))
}
func userNotificationCenter(_ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler handler: @escaping () -> Void) {
    AppPushService.handleDidReceive(response: response)
    handler()
}
```

```objc
// Objective-C — swizzle: false
[AOAPush initializeWithDebug:NO swizzle:NO];

- (void)application:(UIApplication *)app
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [AOAPush handleAPNsToken:deviceToken];
}
- (void)application:(UIApplication *)app
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [AOAPush handleAPNsRegistrationError:error];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))handler {
    handler([AOAPush handleWillPresentWithNotification:notification]);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))handler {
    [AOAPush handleDidReceiveWithResponse:response];
    handler();
}
```

---

## Notification Service Extension

One NSE gives you **rich media** (image/video attachments, text overrides) and **Delivered analytics**.

### Setup

**1. Add App Group to your main app target**

In Xcode: Target → Signing & Capabilities → **+** → App Groups → add `group.com.yourcompany.app.appsonair`

> [!IMPORTANT]
> Xcode automatically adds the group to your `.entitlements` file — but it does **not** add anything to `Info.plist`. You must add the `AppsOnAirAppGroup` key to `Info.plist` manually. Skipping this step causes the SDK to fail reading shared storage (APNs token and permission state will not appear).

Add the key manually to both the **main app** and **NSE** `Info.plist`:

```xml
<key>AppsOnAirAppGroup</key>
<string>group.com.yourcompany.app.appsonair</string>
```

After adding via Signing & Capabilities your `.entitlements` will contain (added automatically by Xcode):
```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.yourcompany.app.appsonair</string>
</array>
```

Both files are required — the `.entitlements` entry tells iOS the app is allowed to access the group container; the `Info.plist` key tells the SDK which group ID to use.

If you name the group following the convention `group.<main-bundle-id>.appsonair` exactly, the SDK finds it automatically without the Info.plist key.

**2. Add a Notification Service Extension target**

File → New Target → Notification Service Extension.
Add the **same App Group** capability to the NSE target (Signing & Capabilities → App Groups), then add the same `AppsOnAirAppGroup` key to the NSE `Info.plist` as well.

> [!IMPORTANT]
> The App Group must be registered in **Apple Developer Portal → Identifiers** for both your main app App ID and your NSE App ID before you regenerate the provisioning profiles. Adding it only in Xcode Signing & Capabilities is not enough — the provisioning profile will not include the entitlement until you regenerate it in the portal.
>
> The **CE App ID does not need the App Group** — the Content Extension only renders UI and does not access shared storage.

**3. Link the SDK to the NSE target only**

SPM: add `AppsOnAir-AppPush-ServiceExt` to the NSE target only — never to the main app target.
CocoaPods: NSE must use SPM — adding the `ServiceExtension` subspec via CocoaPods causes an archive error (see [Installation → CocoaPods](#cocoapods)).

**4. Add `mutable-content: 1` to every push payload**

```json
{
  "aps": { "mutable-content": 1, "alert": { "title": "…", "body": "…" } },
  "notification_id": "notif-abc-123",
  "image_url": "https://cdn.example.com/image.jpg"
}
```

Without this iOS never invokes the NSE.

### Swift — subclass

```swift
import AppsOnAir_AppPush_ServiceExt

class NotificationService: AppsOnAirNotificationServiceExtension {
    // No code required — media download, text overrides, badge, delivery receipt are automatic.

    // Optional hook — runs before the SDK applies its changes:
    // override func modifyContent(_ content: UNMutableNotificationContent,
    //                             request: UNNotificationRequest) {
    //     content.title = "[Modified] " + content.title
    // }
}
```

### Swift — free functions (if you already have your own NSE subclass)

```swift
import AppsOnAir_AppPush_ServiceExt

class NotificationService: UNNotificationServiceExtension {

    override func didReceive(_ request: UNNotificationRequest,
        withContentHandler handler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent
        else { return handler(request.content) }
        AppPushServiceExtension.didReceiveNotificationExtensionRequest(
            request, with: content, withContentHandler: handler)
    }

    override func serviceExtensionTimeWillExpire() { /* SDK handles this */ }
}
```

### Objective-C

> ObjC cannot subclass `AppsOnAirNotificationServiceExtension`. Subclass `UNNotificationServiceExtension` directly and call `AOAPushExtension` static methods — behaviour is identical.

```objc
// NotificationService.h
#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

@interface NotificationService : UNNotificationServiceExtension
@end

// NotificationService.m
#import "NotificationService.h"
@import AppsOnAir_AppPush_ServiceExt;

@interface NotificationService ()
@property (nonatomic, strong) UNNotificationRequest            *receivedRequest;
@property (nonatomic, copy)   void (^contentHandler)(UNNotificationContent *);
@property (nonatomic, strong) UNMutableNotificationContent     *bestAttemptContent;
@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request
                   withContentHandler:(void (^)(UNNotificationContent *))contentHandler {
    self.receivedRequest    = request;
    self.contentHandler     = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];

    [AOAPushExtension didReceiveNotificationRequest:request
                              withContentHandler:contentHandler];
    self.contentHandler = nil;
}

- (void)serviceExtensionTimeWillExpire {
    [AOAPushExtension serviceExtensionTimeWillExpireRequest:self.receivedRequest
                                       bestAttemptContent:self.bestAttemptContent
                                           contentHandler:self.contentHandler];
    self.contentHandler = nil;
}

@end
```

---

## Notification Content Extension

Replaces the expanded (long-press) notification view with custom UI. There are two ways to set this up — choose the one that fits your needs.

| | Option A — SDK built-in UI | Option B — Custom storyboard UI |
|---|---|---|
| UI built by | SDK (`AppsOnAirContentViewController`) | You (storyboard + code) |
| Storyboard | Delete it | Keep it |
| SDK pod required | Yes | No |
| ObjC subclassing | Not supported — use Option B | Fully supported |
| Best for | Quick setup, standard image+title+body layout | Custom layouts, ObjC apps |

Send `"aps": { "category": "your-category-id" }` in the payload to route the notification to this extension.

---

### Option A — SDK built-in UI (programmatic, no storyboard)

The SDK provides `AppsOnAirContentViewController` which renders a full-width image (from the NSE attachment), bold title, and multiline body automatically.

**1. Add a Notification Content Extension target**

File → New Target → Notification Content Extension.

**2. Link the SDK to the CE target only**

SPM: add `AppsOnAir-AppPush-ContentExt` to the CE target only — never to the main app target.
CocoaPods: CE must use SPM — adding the `ContentExtension` subspec via CocoaPods causes an archive error (see [Installation → CocoaPods](#cocoapods)).

**3. Update Info.plist**

Xcode generates `NSExtensionMainStoryboard` by default — replace it with `NSExtensionPrincipalClass`:

```xml
<!-- Remove this (Xcode default): -->
<key>NSExtensionMainStoryboard</key>
<string>MainInterface</string>

<!-- Add this instead: -->
<key>NSExtensionPrincipalClass</key>
<string>$(PRODUCT_MODULE_NAME).NotificationViewController</string>
```

Full Info.plist after the change:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>UNNotificationExtensionCategory</key>
        <string>your-category-id</string>
        <key>UNNotificationExtensionInitialContentSizeRatio</key>
        <real>1</real>
    </dict>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).NotificationViewController</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.content-extension</string>
</dict>
```

**4. Delete `MainInterface.storyboard`**

Right-click `MainInterface.storyboard` in the Xcode project navigator → Delete → Move to Trash. The SDK builds its UI entirely in code — the storyboard is not used.

**5. Subclass `AppsOnAirContentViewController`**

```swift
import AppsOnAir_AppPush_ContentExt

class NotificationViewController: AppsOnAirContentViewController {
    // No code required — image, title, and body are rendered automatically.
}
```

To add custom behaviour on top of the built-in layout, override `configure(with:)`:

```swift
class NotificationViewController: AppsOnAirContentViewController {
    override func configure(with notification: UNNotification) {
        super.configure(with: notification)  // keeps image + title + body
        // add your own views or customisations here
    }
}
```

> **Note:** `AppsOnAirContentViewController` cannot be subclassed from Objective-C. Use Option B instead.

---

### Option B — Custom storyboard UI

Use this when you want full control over the layout, have an existing storyboard-based CE, or are working in Objective-C.

No SDK pod is required for this option — the CE uses only Apple's `UserNotifications` and `UserNotificationsUI` frameworks. The NSE still handles media downloads and delivery analytics.

**Keep the Xcode-generated Info.plist as-is** — `NSExtensionMainStoryboard` stays:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>UNNotificationExtensionCategory</key>
        <string>your-category-id</string>
        <key>UNNotificationExtensionInitialContentSizeRatio</key>
        <real>1</real>
    </dict>
    <key>NSExtensionMainStoryboard</key>
    <string>MainInterface</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.content-extension</string>
</dict>
```

**Swift — implement `UNNotificationContentExtension` in your storyboard view controller:**

```swift
import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var bodyLabel: UILabel!

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        titleLabel.text = content.title
        bodyLabel.text  = content.body

        if let attachment = content.attachments.first,
           attachment.url.startAccessingSecurityScopedResource() {
            defer { attachment.url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: attachment.url) {
                imageView.image = UIImage(data: data)
            }
        }
    }
}
```

**Objective-C — Option A (SDK built-in UI, no storyboard):**

Use `AOAContentViewController` — the ObjC-subclassable equivalent of `AppsOnAirContentViewController`. It renders the same full-width image, bold title, and multiline body layout.

Delete `MainInterface.storyboard`. Set Info.plist to use `NSExtensionPrincipalClass`:

```xml
<key>NSExtensionPrincipalClass</key>
<string>NotificationViewController</string>
```

```objc
// NotificationViewController.h
@import AppsOnAir_AppPush_ContentExt;

@interface NotificationViewController : AOAContentViewController
@end

// NotificationViewController.m
#import "NotificationViewController.h"

@implementation NotificationViewController

// No code required — image, title, and body are rendered by AOAContentViewController.

// Optional: override to add custom behaviour on top of the built-in layout.
- (void)configureWithNotification:(UNNotification *)notification {
    [super configureWithNotification:notification]; // keeps image + title + body
    // add your own customisation here
}

@end
```

**Objective-C — Option B (custom storyboard UI):**

Keep `MainInterface.storyboard` and `NSExtensionMainStoryboard` in Info.plist. No SDK CE class involved.

```objc
// NotificationViewController.h
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

@interface NotificationViewController : UIViewController <UNNotificationContentExtension>
@property (nonatomic, weak) IBOutlet UIImageView *imageView;
@property (nonatomic, weak) IBOutlet UILabel     *titleLabel;
@property (nonatomic, weak) IBOutlet UILabel     *bodyLabel;
@end

// NotificationViewController.m
#import "NotificationViewController.h"

@implementation NotificationViewController

- (void)didReceiveNotification:(UNNotification *)notification {
    self.titleLabel.text = notification.request.content.title;
    self.bodyLabel.text  = notification.request.content.body;

    UNNotificationAttachment *attachment = notification.request.content.attachments.firstObject;
    if (attachment && [attachment.URL startAccessingSecurityScopedResource]) {
        NSData *data = [NSData dataWithContentsOfURL:attachment.URL];
        [attachment.URL stopAccessingSecurityScopedResource];
        if (data) self.imageView.image = [UIImage imageWithData:data];
    }
}

@end
```

Wire `imageView`, `titleLabel`, and `bodyLabel` as `@IBOutlet` connections in `MainInterface.storyboard`.

---

## Background Fetch

The SDK uses a background task to keep subscription state and analytics in sync while the app is in the background. Register the handler at launch, schedule it once — iOS controls when it actually fires.

Add the task identifier to **Info.plist** first:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.appsonair.push.background-sync</string>
</array>
```

```swift
// Swift
AppsOnAirBackgroundSync.registerHandlers()              // call before any scene connects
AppsOnAirBackgroundSync.scheduleIfNeeded()              // default 15-min minimum interval
AppsOnAirBackgroundSync.scheduleIfNeeded(minimumDelay: 1800)  // custom interval (seconds)
AppsOnAirBackgroundSync.cancelPending()

let taskId = AppsOnAirBackgroundSync.taskIdentifier
```

```objc
// Objective-C
[AOAPushBackgroundSync registerHandlers];
[AOAPushBackgroundSync scheduleIfNeeded];
[AOAPushBackgroundSync scheduleIfNeededWithMinimumDelay:1800];
[AOAPushBackgroundSync cancelPending];

NSString *taskId = [AOAPushBackgroundSync taskIdentifier];
```

iOS controls actual run frequency — the minimum delay is a hint, not a guarantee.

---

## Push Payload Reference

The custom keys your backend sends alongside the standard `aps` dictionary. `notification_id` is the only required custom key — everything else is optional.

### Minimum payload
```json
{
  "aps": { "alert": { "title": "Hello", "body": "World" } },
  "notification_id": "notif-abc-123"
}
```

### With image (NSE required)
```json
{
  "aps": {
    "alert": { "title": "New offer", "body": "Tap to view" },
    "mutable-content": 1
  },
  "notification_id": "notif-abc-123",
  "image_url": "https://cdn.example.com/offer.jpg"
}
```

### With badge increment (NSE + App Group required)
```json
{
  "aps": {
    "alert": { "title": "New message" },
    "mutable-content": 1
  },
  "notification_id": "notif-abc-123",
  "badge_increment": 1
}
```

### Data keys (siblings of `aps`)

| Key | Type | Notes |
|---|---|---|
| `notification_id` | String | Available in callbacks as `notification.id` |
| `send_id` | String | Analytics send identifier. Available as `notification.sendId` |
| `title` | String | Overrides `aps.alert.title`. NSE only |
| `body` | String | Overrides `aps.alert.body`. NSE only |
| `subtitle` | String | Overrides `aps.alert.subtitle`. NSE only |
| `big_picture` | String (https) | Primary image. NSE only. Takes precedence over `image_url` and `large_icon` |
| `image_url` | String (https) | Image attachment fallback. NSE only. Used when `big_picture` is absent |
| `large_icon` | String (https) | Fallback image. NSE only. Used only when neither `big_picture` nor `image_url` is present |
| `video_url` | String (https) | Video attachment. NSE only. Used only when no image key is present |
| `attachments` | `[String]` or `[{"url":"…"}]` | Multiple attachments (first 3). NSE only. Wins over all other image/video keys |
| `actions` | `[{"id":"…","title":"…"}]` | Action buttons shown in the expanded notification. NSE only |
| `badge` | Int | Absolute badge count. NSE + App Group |
| `badge_increment` | Int | Delta added to running total. NSE + App Group. Wins over `badge` |

---

## Full API Reference

Every public method and property. Swift and ObjC side by side.

### `AppPushService` / `AOAPush`

| Method / Property | Swift | Objective-C | Notes |
|---|---|---|---|
| Initialize | `AppPushService.initialize(debug:swizzle:)` | `[AOAPush initializeWithDebug:swizzle:]` | Call once at launch — registers device automatically |
| Set Listener | `AppPushService.setListener(_:)` | `[AOAPush setListener:]` | Receive token, notification, and error callbacks |
| Device ID | `AppPushService.deviceId` | `[AOAPush deviceId]` | Stable unique device identifier, persists across reinstalls |
| Subscription ID | `AppPushService.subscriptionId` | `[AOAPush subscriptionId]` | Set automatically after registration |
| Set Subscription ID | `AppPushService.setSubscriptionId(_:)` | `[AOAPush setSubscriptionId:]` | Manual override — not required for normal use |
| APNs Environment | `AppPushService.apnsEnvironment` | `[AOAPush apnsEnvironment]` | Sandbox or production |
| Auto-register APNs | `AppPushService.autoRegisterForRemoteNotifications` | `[AOAPush setAutoRegisterForRemoteNotifications:]` | Default: `true` |
| Request Permission | `AppPushService.requestPermission()` | `[AOAPush requestPermission]` | Shows the OS permission dialog |
| Is Permission Granted | `await AppPushService.isPermissionGranted()` | `[AOAPush isPermissionGrantedWithCompletion:]` | Returns current permission status |
| Login | `AppPushService.login(_:)` | `[AOAPush login:]` | Links this device to your user account |
| Logout | `AppPushService.logout()` | `[AOAPush logout]` | Unlinks user — clears tags and aliases, device stays registered |
| Consent Required | `AppPushService.consentRequired` | `[AOAPush setConsentRequired:]` | Set before `initialize()` |
| Consent Given | `AppPushService.consentGiven` | `[AOAPush setConsentGiven:]` | Set after user accepts your consent dialog |
| Silent Push | `AppPushService.onSilentPushReceived` | `[AOAPush handleSilentPush:fetchCompletionHandler:]` | Handle background silent pushes |
| Clear Notifications | `AppPushService.clearAllNotifications()` | `[AOAPush clearAllNotifications]` | Removes all delivered notifications from the tray |
| Badge Count | `AppPushService.badgeCount` | `[AOAPush badgeCount]` | Current badge number |
| Set Badge | `AppPushService.setBadgeCount(_:)` | `[AOAPush setBadgeCount:]` | Sets absolute value |
| Increment Badge | `AppPushService.incrementBadgeCount(by:)` | `[AOAPush incrementBadgeCountBy:]` | Delta (can be negative) |
| Clear Badge | `AppPushService.clearBadgeCount()` | `[AOAPush clearBadgeCount]` | Resets to 0 |
| Auto-clear Badge | `AppPushService.autoClearBadgeOnForeground` | `[AOAPush setAutoClearBadgeOnForeground:]` | Default: `true` |
| APNs Token (manual) | `AppPushService.handleAPNsToken(_:)` | `[AOAPush handleAPNsToken:]` | Required when `swizzle: false` |
| APNs Error (manual) | `AppPushService.handleAPNsRegistrationError(_:)` | `[AOAPush handleAPNsRegistrationError:]` | Required when `swizzle: false` |
| Will Present (manual) | `AppPushService.handleWillPresent(notification:)` | `[AOAPush handleWillPresentWithNotification:]` | Required when `swizzle: false` |
| Did Receive (manual) | `AppPushService.handleDidReceive(response:)` | `[AOAPush handleDidReceiveWithResponse:]` | Required when `swizzle: false` |

### `AppPushService.Debug` / `AOAPushDebug`

| | Swift | Objective-C |
|---|---|---|
| Log Level | `AppPushService.Debug.logLevel` | `[AOAPushDebug logLevel]` / `[AOAPushDebug setLogLevel:]` |

### `AppPushService.User` / `AOAPushUser`

| Method / Property | Swift | Objective-C |
|---|---|---|
| AppsOnAir ID | `AppPushService.User.appsOnAirId` | `[AOAPushUser appsOnAirId]` |
| External ID | `AppPushService.User.externalId` | `[AOAPushUser externalId]` |
| Language (read) | `AppPushService.User.language` | `[AOAPushUser language]` |
| Set Language | `AppPushService.User.setLanguage(_:)` | `[AOAPushUser setLanguage:]` |
| Add Tag | `AppPushService.User.addTag(key:value:)` | `[AOAPushUser addTagWithKey:value:]` |
| Add Tags | `AppPushService.User.addTags(_:)` | `[AOAPushUser addTags:]` |
| Remove Tag | `AppPushService.User.removeTag(_:)` | `[AOAPushUser removeTag:]` |
| Remove Tags | `AppPushService.User.removeTags(_:)` | `[AOAPushUser removeTags:]` |
| Get Tags (cache) | `AppPushService.User.getTags()` | `[AOAPushUser getTags]` |
| Get Tags (backend) | `AppPushService.User.getTags { … }` | `[AOAPushUser fetchTagsFromBackendWithCompletion:]` |
| Add Alias | `AppPushService.User.addAlias(label:id:)` | `[AOAPushUser addAliasWithLabel:id:]` |
| Add Aliases | `AppPushService.User.addAliases(_:)` | `[AOAPushUser addAliases:]` |
| Remove Alias | `AppPushService.User.removeAlias(_:)` | `[AOAPushUser removeAlias:]` |
| Remove Aliases | `AppPushService.User.removeAliases(_:)` | `[AOAPushUser removeAliases:]` |
| Get Aliases (cache) | `AppPushService.User.getAliases()` | `[AOAPushUser getAliases]` |
| Get Aliases (backend) | `AppPushService.User.getAliases { … }` | `[AOAPushUser fetchAliasesFromBackendWithCompletion:]` |
| Add Email | `AppPushService.User.addEmail(_:)` | `[AOAPushUser addEmail:]` |
| Remove Email | `AppPushService.User.removeEmail(_:)` | `[AOAPushUser removeEmail:]` |
| Opt Out | `AppPushService.User.pushSubscription.optOut()` | `[AOAPushUser optOut]` |
| Opt In | `AppPushService.User.pushSubscription.optIn()` | `[AOAPushUser optIn]` |
| Opted In | `AppPushService.User.pushSubscription.optedIn` | `[AOAPushUser pushSubscriptionOptedIn]` |
| Sub Token | `AppPushService.User.pushSubscription.token` | `[AOAPushUser pushSubscriptionToken]` |
| Sub ID | `AppPushService.User.pushSubscription.id` | `[AOAPushUser pushSubscriptionId]` |
| Sub Observer | `pushSubscription.addObserver(_:)` | `[AOAPushUser addPushSubscriptionObserver:]` |
| User Observer | `AppPushService.User.addObserver(_:)` | `[AOAPushUser addUserStateObserver:]` |

### `AppPushService.Notifications` / `AOAPushNotifications`

| Method / Property | Swift | Objective-C |
|---|---|---|
| Request Permission | `Notifications.requestPermission(fallbackToSettings:)` | `[AOAPushNotifications requestPermissionWithFallbackToSettings:]` |
| Provisional Auth | `Notifications.registerForProvisionalAuthorization()` | `[AOAPushNotifications registerForProvisionalAuthorization]` |
| Permission | `Notifications.permission` | `[AOAPushNotifications permission]` |
| Permission Native | `Notifications.permissionNative` | `[AOAPushNotifications permissionNative]` |
| Can Request | `Notifications.canRequestPermission` | `[AOAPushNotifications canRequestPermission]` |
| Refresh Permission | `await Notifications.refreshPermission()` | `[AOAPushNotifications refreshPermissionWithCompletion:]` |
| Permission Observer | `Notifications.addPermissionObserver(_:)` | `[AOAPushNotifications addPermissionObserver:]` |
| Remove Permission Observer | `Notifications.removePermissionObserver(_:)` | `[AOAPushNotifications removePermissionObserver:]` |
| Lifecycle Listener | `Notifications.addForegroundLifecycleListener(_:)` | `[AOAPushNotifications addForegroundLifecycleListener:]` |
| Remove Lifecycle Listener | `Notifications.removeForegroundLifecycleListener(_:)` | `[AOAPushNotifications removeForegroundLifecycleListener:]` |
| Click Listener | `Notifications.addClickListener(_:)` | `[AOAPushNotifications addClickListener:]` |
| Remove Click Listener | `Notifications.removeClickListener(_:)` | `[AOAPushNotifications removeClickListener:]` |
| Clear All | `Notifications.clearAllNotifications()` | `[AOAPushNotifications clearAllNotifications]` |
| Remove by ID | `Notifications.removeNotification(withIdentifier:)` | `[AOAPushNotifications removeNotificationWithIdentifier:]` |
| Remove by IDs | `Notifications.removeNotifications(withIdentifiers:)` | `[AOAPushNotifications removeNotificationsWithIdentifiers:]` |

### `AppsOnAirBackgroundSync` / `AOAPushBackgroundSync`

Schedules and manages the background sync task.

| Method / Property | Swift | Objective-C |
|---|---|---|
| Register Handlers | `AppsOnAirBackgroundSync.registerHandlers()` | `[AOAPushBackgroundSync registerHandlers]` |
| Schedule | `AppsOnAirBackgroundSync.scheduleIfNeeded(minimumDelay:)` | `[AOAPushBackgroundSync scheduleIfNeededWithMinimumDelay:]` |
| Cancel | `AppsOnAirBackgroundSync.cancelPending()` | `[AOAPushBackgroundSync cancelPending]` |
| Task ID | `AppsOnAirBackgroundSync.taskIdentifier` | `[AOAPushBackgroundSync taskIdentifier]` |

### CE base class — `AppsOnAirContentViewController` / `AOAContentViewController`

| | Swift | Objective-C |
|---|---|---|
| Base class | `AppsOnAirContentViewController` | `AOAContentViewController` |
| Override hook | `configure(with notification: UNNotification)` | `configureWithNotification:` |
| Renders | Full-width image · bold title · multiline body | Same |
| ObjC subclassable | No (`objc_subclassing_restricted`) | Yes |

### NSE helper — `AppPushServiceExtension` / `AOAPushExtension`

Use inside a Notification Service Extension target only. Handles media downloads, text overrides, badge updates, and delivery analytics automatically.

| Method | Swift | Objective-C |
|---|---|---|
| Did Receive | `AppPushServiceExtension.didReceiveNotificationExtensionRequest(_:with:withContentHandler:)` | `[AOAPushExtension didReceiveNotificationRequest:withContentHandler:]` |
| Time Will Expire | `AppPushServiceExtension.serviceExtensionTimeWillExpireRequest(_:with:)` | `[AOAPushExtension serviceExtensionTimeWillExpireRequest:bestAttemptContent:contentHandler:]` |

---

## PushListener Protocol

Assign a listener via `AppPushService.setListener(_:)` to receive APNs token updates, foreground notifications, opens, and errors. In ObjC all four methods are `@optional`; in Swift implement all four (empty body is fine).

### Swift
```swift
public protocol PushListener: AnyObject {
    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment)
    func onNotificationReceived(notification: PushNotification)
    func onNotificationOpened(notification: PushNotification)
    func onError(_ error: PushError)
}
```

### Objective-C (`AOAPushListener`)
```objc
@protocol AOAPushListener <NSObject>
@optional
- (void)onAPNsTokenUpdatedWithToken:(NSString *)token
                        environment:(AOAAPNsEnvironment)environment;
- (void)onNotificationReceivedWithNotification:(AOAPushNotification *)notification;
- (void)onNotificationOpenedWithNotification:(AOAPushNotification *)notification;
- (void)onError:(NSError *)error;
@end
```

In Swift all four must be implemented (empty body is fine). In ObjC all four are `@optional`.

---

## Error Codes

Errors come through `onError` in `PushListener`. Swift gets a `PushError` enum; ObjC gets an `NSError` with domain `AppPushServiceErrorDomain`.

| Code | Meaning | Fix |
|---|---|---|
| `notInitialized` | SDK method called before `initialize()` | Call `initialize()` first |
| `permissionDenied` | User denied notification permission | Guide user to Settings → Notifications |
| `apnsRegistrationFailed` | APNs registration failed | Verify Push Notifications capability |
| `unknown` | Unexpected error | Check the error message for details |

---

## Simulator Notes

APNs tokens don't exist on simulator. Once the user grants permission, the SDK fires:
```
onAPNsTokenUpdated(token: "SIMULATOR-<deviceId>", environment: .sandbox)
```
This mock token works with all other SDK calls so you can test your registration flow without a device. If permission is denied, `onError` fires with `permissionDenied`.

---

## Troubleshooting

Most issues are a missing capability, wrong Info.plist key, or wrong call order. Enable verbose logging first — `AppPushService.Debug.logLevel = .verbose` — then check below.

| Problem | Likely cause | Fix |
|---|---|---|
| No APNs token | Push Notifications capability missing | Signing & Capabilities → + → Push Notifications |
| NSE not invoked | `mutable-content: 1` absent from payload | Add it to every push |
| NSE not invoked | App Group missing or mismatched | Add same group to main app AND NSE via Signing & Capabilities; then manually add `AppsOnAirAppGroup` to both Info.plists (Xcode does not do this automatically) |
| APNs token / permission not showing | `AppsOnAirAppGroup` missing from main app Info.plist | Adding App Group in Signing & Capabilities only updates `.entitlements` — you must also add `AppsOnAirAppGroup` to Info.plist manually |
| No Delivered analytics | Same as NSE not invoked | Check above |
| Background sync never fires | Handler registered too late | Call `registerHandlers()` before any scene connects |
| `BGTaskScheduler` error | Missing Info.plist entry | Add `com.appsonair.push.background-sync` to `BGTaskSchedulerPermittedIdentifiers` |
| Badge not updating | NSE not running | Verify `mutable-content: 1` and App Group are configured |
| ObjC compile error `objc_subclassing_restricted` | Trying to subclass `AppsOnAirNotificationServiceExtension` or `AppsOnAirContentViewController` from ObjC | NSE: use `AOAPushExtension` static methods. CE: subclass `AOAContentViewController` instead — see ObjC setup in each section |
| Xcode warning: "Extension version must match parent app" | `CURRENT_PROJECT_VERSION` (CFBundleVersion) differs between your main app and extension targets | In Xcode Build Settings, set the same `CURRENT_PROJECT_VERSION` value on all extension targets (NSE, CE) as the main app target |
| App Store / Xcode warning: "All interface orientations must be supported unless the app requires full screen" | `UISupportedInterfaceOrientations` not declared in Info.plist | Add `UISupportedInterfaceOrientations` (iPhone) and `UISupportedInterfaceOrientations~ipad` (iPad — all 4 orientations) to your main app `Info.plist` |
| `CFPrefsPlistSource` warning in console on real device | App Group not included in the Development provisioning profile | Regenerate both the main app and NSE provisioning profiles in Apple Developer Portal after adding the App Group to each App ID. CE profile does not need the App Group |
| Silent push: APNs returns 200 OK but device never receives it | Wrong `apns-push-type` / `apns-priority` headers | Silent push requires `apns-push-type: background` + `apns-priority: 5`. Alert push requires `apns-push-type: alert` + `apns-priority: 10`. Mixing them causes iOS to silently drop the notification |
| Silent push: `onSilentPushReceived` never fires | Background App Refresh is OFF | Enable: iPhone Settings → General → Background App Refresh → Wi-Fi & Cellular Data |
| Silent push: `onSilentPushReceived` never fires | Low Power Mode is ON | iOS suspends silent push entirely in Low Power Mode. Disable: iPhone Settings → Battery → Low Power Mode |
| Silent push: `onSilentPushReceived` never fires | App was force-killed | iOS will not wake a force-killed app for silent push. Background it by pressing Home — do not swipe up in App Switcher |
