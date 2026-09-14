# AppPushService — iOS SDK

APNs token registration, rich media attachments, badge management, background sync, and user targeting — all in one SDK. Works with UIKit, SwiftUI, and Objective-C.

> **Alpha — Internal Use Only**
> ⚠️ This SDK is in active development and is not yet ready for production. APIs may change without notice. Do not distribute or use in customer-facing apps. Internal team and approved QA reviewers only.

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
22. [Backend Integration Status](#backend-integration-status)
23. [Changelog](#changelog)

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

### Swift Package Manager

File → Add Package Dependencies → paste the repo URL.

Link the right product to each target:

| Product | Add to |
|---|---|
| `AppsOnAir-AppPush` | Main app target |
| `AppsOnAir-AppPush-ServiceExt` | Notification Service Extension target **only** |
| `AppsOnAir-AppPush-ContentExt` | Notification Content Extension target **only** |

### CocoaPods

```ruby
target 'MyApp' do
  pod 'AppsOnAir-AppPush'
end

target 'MyNotificationServiceExtension' do
  pod 'AppsOnAir-AppPush/ServiceExtension'
end

target 'MyNotificationContentExtension' do
  pod 'AppsOnAir-AppPush/ContentExtension'
end
```

---

## Apple Setup

1. **Push Notifications capability**
   Target → Signing & Capabilities → + Capability → Push Notifications

2. **Background Modes**
   + Capability → Background Modes → check **Background fetch**

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

        AppPushService.Debug.logLevel = .verbose       // set before initialize — captures startup logs
        AppsOnAirBackgroundSync.registerHandlers()     // must be called before any scene connects
        AppPushService.initialize(debug: true)
        AppPushService.setListener(self)
        AppPushService.Notifications.requestPermission()
        AppsOnAirBackgroundSync.scheduleIfNeeded()
        return true
    }
}

extension AppDelegate: PushListener {

    func onAPNsTokenUpdated(token: String, environment: APNsEnvironment) {
        // Send token + AppPushService.deviceId to your backend.
        // When the backend returns a subscription ID:
        // AppPushService.setSubscriptionId("sub_from_backend")
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

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        AppsOnAirBackgroundSync.registerHandlers()
        AppPushService.initialize(debug: true)
        AppPushService.setListener(self)
        AppPushService.Notifications.requestPermission()
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

// AppDelegate.m
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    [AOAPushDebug setLogLevel:AOALogLevelVerbose];
    [AOAPushBackgroundSync registerHandlers];
    [AOAPush initializeWithDebug:YES swizzle:YES];
    [AOAPush setListener:self];
    [AOAPushNotifications requestPermission];
    [AOAPushBackgroundSync scheduleIfNeeded];
    return YES;
}

// AOAPushListener — all methods are optional
- (void)onAPNsTokenUpdatedWithToken:(NSString *)token
                        environment:(AOAAPNsEnvironment)environment {
    // [AOAPush setSubscriptionId:@"sub_from_backend"];
}

- (void)onNotificationReceivedWithNotification:(AOAPushNotification *)notification { }
- (void)onNotificationOpenedWithNotification:(AOAPushNotification *)notification { }
- (void)onError:(NSError *)error { }
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
| `.error` | Errors that affect SDK behaviour |
| `.warn` | Unexpected but recoverable situations |
| `.info` | Key lifecycle events |
| `.debug` | Detailed SDK flow |
| `.verbose` | Everything |

---

## User Identity

Call `login` when your user signs in and `logout` when they sign out. Tags, aliases, and language are wiped on logout; the APNs token and device ID stay — the device keeps receiving pushes as an anonymous user until the next login.

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

// Read from local cache (synchronous)
let tags = AppPushService.User.getTags()

// Fetch fresh copy from backend (async)
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

// Local cache
NSDictionary *tags = [AOAPushUser getTags];

// Backend fetch
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
```

```objc
// Objective-C
[AOAPushUser addAliasWithLabel:@"crm_id" id:@"CRM-9876"];
[AOAPushUser addAliases:@{@"crm_id": @"CRM-9876", @"hubspot_id": @"HS-42"}];
[AOAPushUser removeAlias:@"crm_id"];
[AOAPushUser removeAliases:@[@"crm_id", @"hubspot_id"]];
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

Lets the user stop receiving pushes without revoking OS-level permission. The APNs token is kept — opt back in and pushes resume immediately.

```swift
// Swift
AppPushService.User.pushSubscription.optOut()   // stop receiving pushes (token preserved)
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

React to subscription state changes (opt-in/out, token rotation) and login/logout events without polling. Add observers early — they fire immediately with the current state on first add.

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

```swift
// Swift
AppPushService.Notifications.addForegroundLifecycleListener(self)

func onWillDisplay(event: NotificationWillDisplayEvent) {
    // Call preventDefault() to suppress the banner; omit to show it normally
    event.preventDefault()
}
```

```objc
// Objective-C — AOANotificationLifecycleListener
[AOAPushNotifications addForegroundLifecycleListener:self];

- (void)onWillDisplayWithEvent:(AOANotificationWillDisplayEvent *)event {
    [event preventDefault];
}
```

### Click / Open Listener

Fired when the user taps a notification or one of its action buttons. Use `event.result.actionId` to distinguish which button was tapped, and `event.result.url` for deep link handling.

```swift
// Swift
AppPushService.Notifications.addClickListener(self)

func onClick(event: NotificationClickEvent) {
    print(event.result.actionId ?? "body tap")
    print(event.result.url ?? "")
}
```

```objc
// Objective-C — AOANotificationClickListener
[AOAPushNotifications addClickListener:self];

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

Set `consentRequired = true` **before** `initialize()` if your app needs explicit user consent before any data is sent. The SDK starts up normally but holds all network calls until you set `consentGiven = true`. Consent is persisted — you don't need to set it again on relaunch.

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
    handler([AOAPush handleWillPresentNotification:notification]);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))handler {
    [AOAPush handleDidReceiveResponse:response];
    handler();
}
```

---

## Notification Service Extension

One NSE gives you **rich media** (image/video attachments, text overrides) and **Delivered analytics**.

### Setup

**1. Add App Group to your main app target**

Target → Signing & Capabilities → + → App Groups → `group.com.yourcompany.app.appsonair`

Add the key to both the **main app** and **NSE** Info.plist:
```xml
<key>AppsOnAirAppGroup</key>
<string>group.com.yourcompany.app.appsonair</string>
```

If you name the group following the convention `group.<main-bundle-id>.appsonair` exactly, the SDK finds it automatically without the Info.plist key.

**2. Add a Notification Service Extension target**

File → New Target → Notification Service Extension.
Add the same App Group capability to the NSE target.

**3. Link `AppsOnAir-AppPush-ServiceExt` to the NSE target only**

Never link it to the main app — UIKit is unavailable in an NSE process.

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

> ObjC cannot subclass `AppsOnAirNotificationServiceExtension` (Swift 6.2 `@MainActor` restriction). Subclass `UNNotificationServiceExtension` directly and call `AOAPushExtension` static methods — behaviour is identical.

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

    // SDK calls contentHandler before returning.
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

Replaces the expanded (long-press) notification view with custom UI. `AppsOnAir-AppPush-ContentExt` provides `AppsOnAirContentViewController` — full-width image, bold title, multiline body.

### Setup

1. File → New Target → Notification Content Extension
2. Link `AppsOnAir-AppPush-ContentExt` to the CE target only
3. Configure Info.plist:

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
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.usernotifications.content-extension</string>
    <key>NSExtensionPrincipalClass</key>
    <string>AppsOnAirContentViewController</string>
</dict>
```

Delete the generated `MainInterface.storyboard` and its `NSExtensionMainStoryboard` key — the SDK builds its UI in code.

Send `"aps": { "category": "your-category-id" }` in the payload to route the notification to this extension.

### Swift — use the built-in view controller directly

Set `NSExtensionPrincipalClass` to `AppsOnAirContentViewController` in Info.plist — done.

### Swift — subclass for custom behaviour

```swift
import AppsOnAir_AppPush_ContentExt

class MyContentVC: AppsOnAirContentViewController {
    override func configure(with notification: UNNotification) {
        super.configure(with: notification)  // keeps image + title + body
        // add your own views here
    }
}
```

Set `$(PRODUCT_MODULE_NAME).MyContentVC` as `NSExtensionPrincipalClass`.

### Objective-C

> ObjC cannot subclass `AppsOnAirContentViewController` (same `@MainActor` restriction as the NSE). Subclass `UIViewController` and implement `UNNotificationContentExtension` — the UI is simple to build in ObjC.

```objc
// NotificationViewController.h
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

@interface NotificationViewController : UIViewController <UNNotificationContentExtension>
@end

// NotificationViewController.m
#import "NotificationViewController.h"

@interface NotificationViewController ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel     *titleLabel;
@property (nonatomic, strong) UILabel     *bodyLabel;
@end

@implementation NotificationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Build layout: imageView + titleLabel + bodyLabel
}

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

Set `NSExtensionPrincipalClass` to `NotificationViewController` (no module prefix for ObjC).

---

## Background Fetch

The SDK uses `BGProcessingTask` to sync subscription state and flush queued data while the app is in the background. Register the handler at launch, schedule it once — iOS controls when it actually fires.

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
| `title` | String | Overrides `aps.alert.title`. NSE only |
| `body` | String | Overrides `aps.alert.body`. NSE only |
| `subtitle` | String | Overrides `aps.alert.subtitle`. NSE only |
| `image_url` | String (https) | Attached as image. NSE only. Wins over `video_url` |
| `video_url` | String (https) | Attached as video. NSE only |
| `attachments` | `[String]` or `[{"url":"…"}]` | Multiple attachments (first 3). NSE only. Wins over `image_url` |
| `badge` | Int | Absolute badge count. NSE + App Group |
| `badge_increment` | Int | Delta added to running total. NSE + App Group. Wins over `badge` |

---

## Full API Reference

Every public method and property. Swift and ObjC side by side.

### `AppPushService` / `AOAPush`

| Method / Property | Swift | Objective-C |
|---|---|---|
| Initialize | `AppPushService.initialize(debug:swizzle:)` | `[AOAPush initializeWithDebug:swizzle:]` |
| Set Listener | `AppPushService.setListener(_:)` | `[AOAPush setListener:]` |
| Device ID | `AppPushService.deviceId` | `[AOAPush deviceId]` |
| Subscription ID | `AppPushService.subscriptionId` | `[AOAPush subscriptionId]` |
| Set Subscription ID | `AppPushService.setSubscriptionId(_:)` | `[AOAPush setSubscriptionId:]` |
| Test Device | `AppPushService.isTestDevice` | `[AOAPush isTestDevice]` |
| APNs Environment | `AppPushService.apnsEnvironment` | `[AOAPush apnsEnvironment]` |
| Auto-register APNs | `AppPushService.autoRegisterForRemoteNotifications` | `[AOAPush setAutoRegisterForRemoteNotifications:]` |
| Request Permission | `AppPushService.requestPermission()` | `[AOAPush requestPermission]` |
| Is Permission Granted | `await AppPushService.isPermissionGranted()` | `[AOAPush isPermissionGrantedWithCompletion:]` |
| Login | `AppPushService.login(_:)` | `[AOAPush login:]` |
| Logout | `AppPushService.logout()` | `[AOAPush logout]` |
| Consent Required | `AppPushService.consentRequired` | `[AOAPush setConsentRequired:]` |
| Consent Given | `AppPushService.consentGiven` | `[AOAPush setConsentGiven:]` |
| Silent Push | `AppPushService.onSilentPushReceived` | `[AOAPush handleSilentPush:fetchCompletionHandler:]` |
| Clear Notifications | `AppPushService.clearAllNotifications()` | `[AOAPush clearAllNotifications]` |
| Badge Count | `AppPushService.badgeCount` | `[AOAPush badgeCount]` |
| Set Badge | `AppPushService.setBadgeCount(_:)` | `[AOAPush setBadgeCount:]` |
| Increment Badge | `AppPushService.incrementBadgeCount(by:)` | `[AOAPush incrementBadgeCountBy:]` |
| Clear Badge | `AppPushService.clearBadgeCount()` | `[AOAPush clearBadgeCount]` |
| Auto-clear Badge | `AppPushService.autoClearBadgeOnForeground` | `[AOAPush setAutoClearBadgeOnForeground:]` |
| APNs Token (manual) | `AppPushService.handleAPNsToken(_:)` | `[AOAPush handleAPNsToken:]` |
| APNs Error (manual) | `AppPushService.handleAPNsRegistrationError(_:)` | `[AOAPush handleAPNsRegistrationError:]` |
| Will Present (manual) | `AppPushService.handleWillPresent(notification:)` | `[AOAPush handleWillPresentNotification:]` |
| Did Receive (manual) | `AppPushService.handleDidReceive(response:)` | `[AOAPush handleDidReceiveResponse:]` |

### `AppPushService.Debug` / `AOAPushDebug`

| | Swift | Objective-C |
|---|---|---|
| Log Level | `AppPushService.Debug.logLevel` | `[AOAPushDebug logLevel]` / `[AOAPushDebug setLogLevel:]` |

### `AppPushService.User` / `AOAPushUser`

| Method / Property | Swift | Objective-C |
|---|---|---|
| AppsOnAir ID | `AppPushService.User.appsOnAirId` | `[AOAPushUser appsOnAirId]` |
| External ID | `AppPushService.User.externalId` | `[AOAPushUser externalId]` |
| Language | `AppPushService.User.language` | `[AOAPushUser language]` |
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
| Lifecycle Listener | `Notifications.addForegroundLifecycleListener(_:)` | `[AOAPushNotifications addForegroundLifecycleListener:]` |
| Click Listener | `Notifications.addClickListener(_:)` | `[AOAPushNotifications addClickListener:]` |
| Clear All | `Notifications.clearAllNotifications()` | `[AOAPushNotifications clearAllNotifications]` |
| Remove by ID | `Notifications.removeNotification(withIdentifier:)` | `[AOAPushNotifications removeNotificationWithIdentifier:]` |
| Remove by IDs | `Notifications.removeNotifications(withIdentifiers:)` | `[AOAPushNotifications removeNotificationsWithIdentifiers:]` |

### `AppsOnAirBackgroundSync` / `AOAPushBackgroundSync`

| Method / Property | Swift | Objective-C |
|---|---|---|
| Register Handlers | `AppsOnAirBackgroundSync.registerHandlers()` | `[AOAPushBackgroundSync registerHandlers]` |
| Schedule | `AppsOnAirBackgroundSync.scheduleIfNeeded(minimumDelay:)` | `[AOAPushBackgroundSync scheduleIfNeededWithMinimumDelay:]` |
| Cancel | `AppsOnAirBackgroundSync.cancelPending()` | `[AOAPushBackgroundSync cancelPending]` |
| Task ID | `AppsOnAirBackgroundSync.taskIdentifier` | `[AOAPushBackgroundSync taskIdentifier]` |

### NSE helper — `AppPushServiceExtension` / `AOAPushExtension`

Use inside a Notification Service Extension target only.

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
| NSE not invoked | App Group missing or mismatched | Add same group to main app AND NSE; add `AppsOnAirAppGroup` to both Info.plists |
| No Delivered analytics | Same as NSE not invoked | Check above |
| Background sync never fires | Handler registered too late | Call `registerHandlers()` before any scene connects |
| `BGTaskScheduler` error | Missing Info.plist entry | Add `com.appsonair.push.background-sync` to `BGTaskSchedulerPermittedIdentifiers` |
| Badge not updating | NSE not running | Verify `mutable-content: 1` and App Group are configured |
| ObjC compile error `objc_subclassing_restricted` | Trying to subclass `AppsOnAirNotificationServiceExtension` or `AppsOnAirContentViewController` from ObjC | Use `AOAPushExtension` static methods (NSE) or pure `UIViewController` (CE) — see setup sections above |

---

## Backend Integration Status

The device-side SDK is complete. The HTTP calls that report data back to AppsOnAir are being wired up in parallel.

| Feature | Status |
|---|---|
| APNs token capture, environment detection | ✅ |
| Foreground / tap / action-button callbacks | ✅ |
| Rich media download + text overrides (NSE) | ✅ |
| Badge count — payload keys, manual APIs, auto-clear | ✅ |
| Background fetch scheduling | ✅ |
| Tags, aliases, emails, language — stored locally | ✅ |
| Device registration (POST /subscriptions) | Call your backend manually in `onAPNsTokenUpdated`, then call `setSubscriptionId()` |
| Open / click event reporting | Coming soon |
| Delivered analytics upload | NSE queues receipts locally; upload coming soon |
| GDPR consent gating | Stored today; active enforcement coming soon |
| SMS channel | Out of scope for now; future release |

---

## Changelog

### v0.1.0-alpha — 2026-09-11

First internal alpha release. Not for production use.

**Core SDK (`AppPushService`)**
- `initialize(debug:swizzle:)` — SDK entry point with optional debug mode and method swizzling
- `requestPermission()` and `requestPermission(fallbackToSettings:)` — UNUserNotificationCenter permission flow
- `registerForProvisionalAuthorization()` — provisional auth (iOS 12+, no prompt required)
- APNs token capture with environment detection (sandbox vs production)
- Simulator token fallback (`SIMULATOR-<deviceId>`) so the registration flow is testable without a device
- `login(_:)` / `logout()` — external user ID linking
- `isTestDevice`, `consentRequired`, `consentGiven` — device flags
- `isPermissionGranted(completion:)` — async permission check

**User Namespace (`AppPushService.User`)**
- Tags — `addTag`, `addTags`, `removeTag`, `removeTags`, `getTags` (local), `getTags(completion:)` (backend fetch)
- Aliases — `addAlias`, `addAliases`, `removeAlias`, `removeAliases`
- Email — `addEmail`, `removeEmail`
- Language — `setLanguage`, `language`
- Push subscription — `optIn()`, `optOut()`, `.optedIn`, `.token`, `.id`
- Observers — `PushSubscriptionObserver`, `UserStateObserver`

**Notifications Namespace (`AppPushService.Notifications`)**
- Permission — `permission`, `permissionNative`, `canRequestPermission`, `refreshPermission(completion:)`
- Foreground display — `NotificationLifecycleListener` with `preventDefault()` support
- Click handling — `NotificationClickListener` with `NotificationClickEvent` (action ID, notification)
- Notification centre — `clearAll()`, `remove(identifier:)`, `remove(identifiers:)`
- Observer — `NotificationPermissionObserver`

**Badge Count**
- `setBadgeCount(_:)`, `incrementBadgeCount(by:)`, `clearBadgeCount()`, `badgeCount`
- `autoClearBadgeOnForeground` — clears badge automatically when app comes to foreground

**Notification Service Extension**
- `AppsOnAirNotificationServiceExtension` — subclass to enable rich media download and badge management from payload keys (`aoa-badge`, `aoa-badge-inc`)

**Notification Content Extension**
- `AppsOnAirContentViewController` — base class for custom in-notification UI

**Background Sync**
- `BackgroundSync.registerHandlers()`, `scheduleIfNeeded(minimumDelay:)`, `cancelPending()`, `taskIdentifier`
- BGTaskScheduler-based periodic sync (default 15-minute minimum interval)

**Debug**
- `Debug.logLevel` — `.none`, `.fatal`, `.error`, `.warn`, `.info`, `.debug`, `.verbose`

**Objective-C Layer**
- Full ObjC facade via `AOA*` classes: `AOAPush`, `AOAPushUser`, `AOAPushNotifications`, `AOAPushDebug`, `AOAPushBackgroundSync`
- `AOAPushListener`, `AOANotificationPermissionObserver`, `AOANotificationLifecycleListener`, `AOANotificationClickListener`, `AOAPushSubscriptionObserver`, `AOAUserStateObserver` protocols
- `AOAPushNotification`, `AOANotificationWillDisplayEvent`, `AOANotificationClickEvent`, `AOAPushSubscriptionChangedState`, `AOAUserChangedState` model classes
- `AOAPushExtension` static helpers for NSE without Swift subclassing

**Known limitations in this release**
- Open / click event reporting to backend not yet wired
- Delivered analytics upload (NSE) pending
- GDPR consent gating stored but not enforced
- Remote backend URL is pointed at `push.dev.appsonair.com` (dev environment only)
