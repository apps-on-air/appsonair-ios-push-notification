Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush'
  # Source of truth for the runtime SDK version — AppsOnAirDeviceInfo.sdkVersion
  # reads this back via SdkManager (org.cocoapods.AppsOnAir-AppPush). Keep
  # AppsOnAirDeviceInfo.fallbackSDKVersion in sync for the SPM-as-source case.
  s.version          = '1.0.6-beta'
  s.summary          = 'AppsOnAir Push Notifications SDK for iOS'
  s.description      = <<-DESC
    Lightweight iOS push notification SDK using APNs directly. No Firebase dependency.
    Includes a Notification Service Extension base class for rich media attachments
    and a Notification Content Extension base view controller for custom UI.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/PushNotification/ios-sdk-setup'
  s.readme           = "https://github.com/apps-on-air/appsonair-ios-push-notification/blob/main/README.md"
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  # ── Default subspec (main app target) ─────────────────────────────────────────
  # `pod 'AppsOnAir-AppPush'` installs only this subspec by default.
  s.default_subspecs = 'Core'

  # ── Core — link to your main app target ───────────────────────────────────────
  # AppsOnAirPushShared sources (EnvironmentConfig, AppsOnAirStorageKeys) are
  # compiled directly into this target. Under CocoaPods, shared sources are
  # included via source_files glob — no separate subspec needed. Under SPM,
  # sharing is handled by the AppsOnAir-AppPush-Shared target dependency.
  s.subspec 'Core' do |core|
    core.source_files = 'Sources/AppsOnAirPush/**/*.swift',
                        'Sources/AppsOnAirPushShared/**/*.swift'
    core.frameworks   = 'UIKit', 'UserNotifications', 'Security', 'BackgroundTasks'
    # Shared device/app metadata + app-id resolution used by AppsOnAirDeviceInfo.
    # ~> 1.2 allows >= 1.2.0, < 2.0 — mirrors the SPM `from: "1.2.3"` (upToNextMajor) rule
    # so CocoaPods and SPM resolve Core to the same compatible range.
    core.dependency 'AppsOnAir-Core', '>= 1.2.3'
    core.pod_target_xcconfig = { 'LM_SKIP_METADATA_EXTRACTION' => 'YES' }
  end

  # ── ServiceExtension — DEPRECATED, use pod 'AppsOnAir-AppPush-ServiceExt' ─────
  # Kept so existing Podfiles still resolve. A subspec shares the root's module name,
  # so this builds a second AppsOnAir_AppPush.framework next to Core's: with
  # use_frameworks! that fails archive ("Multiple commands produce …") and embeds the
  # wrong framework in the app. The AppsOnAir-AppPush-ServiceExt pod has its own
  # module (AppsOnAir_AppPush_ServiceExt, as with SPM) and has neither problem.
  # UIKit is unavailable inside a Notification Service Extension.
  # AppsOnAirPushShared sources included directly — same reason as Core above.
  # Usage: pod 'AppsOnAir-AppPush/ServiceExtension'
  s.subspec 'ServiceExtension' do |ext|
    ext.source_files = 'Sources/AppsOnAirPushServiceExt/**/*.swift',
                       'Sources/AppsOnAirPushShared/**/*.swift'
    ext.frameworks   = 'Foundation', 'UserNotifications'
    ext.pod_target_xcconfig = { 'LM_SKIP_METADATA_EXTRACTION' => 'YES' }
  end

  # ── ContentExtension — DEPRECATED, use pod 'AppsOnAir-AppPush-ContentExt' ─────
  # Kept so existing Podfiles still resolve; same module-name clash as ServiceExtension.
  # Usage: pod 'AppsOnAir-AppPush/ContentExtension'
  s.subspec 'ContentExtension' do |content|
    content.source_files = 'Sources/AppsOnAirPushContentExt/**/*.swift'
    content.frameworks   = 'UIKit', 'UserNotifications', 'UserNotificationsUI'
    content.pod_target_xcconfig = { 'LM_SKIP_METADATA_EXTRACTION' => 'YES' }
  end
end
