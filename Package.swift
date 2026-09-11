// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppsOnAir-iOS-Push",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        // Main app target — APNs token, foreground/tap callbacks, background sync.
        .library(
            name: "AppsOnAirPush",
            targets: ["AppsOnAirPush"]
        ),
        // Link to your Notification Service Extension target only (not the main app).
        // Provides: AppsOnAirNotificationServiceExtension — rich media download,
        // title/body overrides, 30-s expiry fallback.
        .library(
            name: "AppsOnAirPushServiceExt",
            targets: ["AppsOnAirPushServiceExt"]
        ),
        // Link to your Notification Content Extension target only (not the main app).
        // Provides: AppsOnAirContentViewController — image + title/body UI.
        .library(
            name: "AppsOnAirPushContentExt",
            targets: ["AppsOnAirPushContentExt"]
        )
    ],
    dependencies: [
        // Shared device/app metadata, app-id resolution, and network-reachability
        // helpers used across the AppsOnAir SDK family. UIKit-based — main app
        // target only (never the notification extensions).
        // TODO: Switch back to remote before release
        .package(
            url: "https://github.com/apps-on-air/AppsOnAir-iOS-Core.git",
            from: "1.2.3"
        )
    ],
    targets: [
        // ── Main app target ──────────────────────────────────────────────────────
        // Link to your app target. Imports: UIKit, UserNotifications,
        // Security, BackgroundTasks.
        .target(
            name: "AppsOnAirPush",
            dependencies: [
                .product(name: "AppsOnAir-Core", package: "AppsOnAir-iOS-Core")
            ],
            path: "Sources/AppsOnAirPush"
        ),

        // ── Notification Service Extension target ────────────────────────────────
        // Link to your Notification Service Extension target only.
        // UIKit is NOT available inside a Notification Service Extension —
        // this target imports only Foundation + UserNotifications.
        .target(
            name: "AppsOnAirPushServiceExt",
            dependencies: [],
            path: "Sources/AppsOnAirPushServiceExt"
        ),

        // ── Notification Content Extension target ────────────────────────────────
        // Link to your Notification Content Extension target only.
        // Imports: UIKit, UserNotifications, UserNotificationsUI.
        .target(
            name: "AppsOnAirPushContentExt",
            dependencies: [],
            path: "Sources/AppsOnAirPushContentExt"
        ),

        // ── Tests ────────────────────────────────────────────────────────────────
        .testTarget(
            name: "AppsOnAirPushTests",
            dependencies: ["AppsOnAirPush"]
        )
    ]
)
