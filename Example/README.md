# AppsOnAir iOS Push Notification — Example App

A SwiftUI example app demonstrating every feature of the AppsOnAir iOS push notification SDK:
push permission, tags, aliases, email, badge, background sync, NSE rich media, NCE long-press image, and silent push.

---

## What to Change Before Running

**All placeholders you need to replace are listed here. Nothing else needs to be touched.**

| File | Key / Setting | Replace with |
|---|---|---|
| `ExampleApp/Info.plist` | `AppsonairAppId` → `YOUR_APP_ID` | Your App ID from the AppsOnAir dashboard |
| `ExampleApp/Info.plist` | `AppsOnAirAppGroup` → `group.com.your-company.example-app.appsonair` | Your App Group ID |
| `ExampleApp/ExampleApp.entitlements` | `com.apple.security.application-groups` value | Your App Group ID |
| `AppsonairNotificationServiceExtension/Info.plist` | `AppsOnAirAppGroup` value | Your App Group ID |
| `AppsonairNotificationServiceExtension/*.entitlements` | `com.apple.security.application-groups` value | Your App Group ID |
| `ExampleApp.xcodeproj` → ExampleApp target | Bundle Identifier (`com.your-company.example-app`) | Your bundle ID |
| `ExampleApp.xcodeproj` → NSE target | Bundle Identifier (`com.your-company.example-app.AppsonairNotificationServiceExtension`) | `<your-bundle-id>.AppsonairNotificationServiceExtension` |
| `ExampleApp.xcodeproj` → NCE target | Bundle Identifier (`com.your-company.example-app.AppsonairNotificationContentExtension`) | `<your-bundle-id>.AppsonairNotificationContentExtension` |
| All targets | Signing & Capabilities → Team | Your Apple Developer team |

> **App Group ID convention:** use `group.<your-bundle-id>.appsonair` — e.g. `group.com.acme.myapp.appsonair`

---

## Prerequisites

- Xcode 16+
- Physical iOS device (push not available on simulator)
- Apple Developer account
- App ID from the [AppsOnAir dashboard](https://dashboard.appsonair.com)

---

## Steps to Run

### 1. Open the project

```
open Example/ExampleApp.xcodeproj
```

### 2. Fill in your values

Replace every placeholder in the table above. The quickest path:

1. `ExampleApp/Info.plist` — set `AppsonairAppId` and `AppsOnAirAppGroup`
2. `ExampleApp/ExampleApp.entitlements` — set App Group value
3. `AppsonairNotificationServiceExtension/Info.plist` — set `AppsOnAirAppGroup`
4. `AppsonairNotificationServiceExtension/*.entitlements` — set App Group value
5. Xcode → each target → General → Bundle Identifier → set your bundle IDs
6. Xcode → each target → Signing & Capabilities → Team → select your team

### 3. Add capabilities in Xcode

**ExampleApp target:**
- Signing & Capabilities → `+` → **Push Notifications**
- Signing & Capabilities → `+` → **App Groups** → add your group ID
- Signing & Capabilities → `+` → **Background Modes** → enable **Remote notifications** and **Background fetch**

> After adding App Group in Xcode, also add `AppsOnAirAppGroup` key to `Info.plist` manually — Xcode only updates `.entitlements` automatically.

**AppsonairNotificationServiceExtension target:**
- Signing & Capabilities → `+` → **App Groups** → add the same group ID
- Add `AppsOnAirAppGroup` to the NSE `Info.plist` manually

### 4. Register in Apple Developer Portal

For both the main app App ID and the NSE App ID:
1. Certificates, Identifiers & Profiles → Identifiers → select App ID → enable **App Groups** → assign your group
2. Regenerate provisioning profiles for all three targets (main app, NSE, NCE)

### 5. Build & run

Select your device and the **ExampleApp** scheme → Run (⌘R)

---

## SDK Integration

The project uses **Swift Package Manager** with a **local package** reference pointing to the SDK parent folder (`../`).

- `ExampleApp` target → `AppsOnAir-AppPush`
- `AppsonairNotificationServiceExtension` target → `AppsOnAir-AppPush-ServiceExt`
- `AppsonairNotificationContentExtension` target → `AppsOnAir-AppPush-ContentExt`

The project already uses the **remote published SDK** (`1.0.3-beta`, Up to Next Minor).
Xcode will fetch the package automatically when you open the project after `1.0.3-beta` is tagged and pushed to GitHub.

See `Podfile` for CocoaPods integration instructions.

---

## Sending a Test Push

```bash
curl -X POST https://push.appsonair.com/v1/notifications \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "YOUR_APP_ID",
    "notification": {
      "title": "Rich Push Test",
      "body": "Long-press to see the image.",
      "big_picture": "https://httpbin.org/image/png",
      "category": "aoa_rich",
      "mutable_content": true
    }
  }'
```

---

## What to Verify

| Feature | How to check |
|---|---|
| Permission dialog | Appears on first launch |
| Subscription ID | Tap "Subscription ID" row — value appears |
| APNs token | Appears in "Live Events" section after launch |
| NSE (image thumbnail) | Push arrives with image in banner thumbnail |
| NCE (full image) | Long-press the banner — full-width image appears |
| Foreground notification | Send push while app is open — "Notification Received" row updates |
| Tap / open event | Tap a notification — "Notification Opened" row updates |
| Silent push | Send `content-available: 1` payload — "Silent Push Received" row updates |

---

## Troubleshooting

See the full troubleshooting section in the [main SDK README](../README.md#troubleshooting).

Key points:
- NSE not running → check `IPHONEOS_DEPLOYMENT_TARGET` ≤ device iOS version (set to `15.0`)
- No image → verify `mutable-content: 1` in payload and App Group in both `.entitlements` and `Info.plist`
- NCE not shown → verify `UNNotificationExtensionCategory` in NCE `Info.plist` matches `aps.category` in payload
