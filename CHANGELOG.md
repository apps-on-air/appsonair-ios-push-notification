## 1.0.6-beta
- New `AppsOnAir-AppPush-ServiceExt` and `AppsOnAir-AppPush-ContentExt` pods for the notification extensions (modules match the SPM products). Fixes "Multiple commands produce AppsOnAir_AppPush.framework" on archive with `use_frameworks!`. The `ServiceExtension` / `ContentExtension` subspecs are deprecated.
- With swizzling on, AppsOnAir pushes now reach the SDK when another component owns the notification delegate (e.g. Notifee in React Native, a Flutter plugin, the host AppDelegate). No AppDelegate push code is needed.
- Foreground and tap handling process each notification once, even if the host also forwards it manually.
- APNs callbacks are hooked immediately at `initialize()` when the app delegate is already set.

## 1.0.4-beta
- Minor SDK improvements.
- Minor Cross SDK improvements.

## 1.0.3-beta
- Minor SDK improvements.

## 1.0.2-beta
- Minor SDK improvements.

## 1.0.1-beta
- Minor SDK improvements.
- Email and Alias method integration.


## 1.0.0-beta
- Minor SDK improvements.

## 0.0.4-alpha
- SDK improvements.

* Minor NSE SDK improvements (Sound).
* Analytics integration.

## 0.0.2-alpha
* SDK improvements.
* Code of conduct file added.
* CocoaPods warning fixes.

## 0.0.1-alpha
* AppsOnAir Push Notification service. (Alpha Internal Release).