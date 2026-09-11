# Integration notes

The host app owns UIApplicationDelegate and normally also owns
UNUserNotificationCenterDelegate.

For the POC, use explicit forwarding:

UIApplicationDelegate:
- didRegisterForRemoteNotificationsWithDeviceToken
- didFailToRegisterForRemoteNotificationsWithError

UNUserNotificationCenterDelegate:
- willPresent
- didReceive response

No method swizzling is used.
