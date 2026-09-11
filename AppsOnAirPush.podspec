Pod::Spec.new do |s|
  s.name             = 'AppsOnAirPush'
  # Source of truth for the runtime SDK version — AppsOnAirDeviceInfo.sdkVersion
  # reads this back via SdkManager (org.cocoapods.AppsOnAirPush). Keep
  # AppsOnAirDeviceInfo.fallbackSDKVersion in sync for the SPM-as-source case.
  s.version          = '0.0.1'
  s.summary          = 'AppsOnAir Push Notifications SDK for iOS'
  s.description      = <<-DESC
    Lightweight iOS push notification SDK using APNs directly. No Firebase dependency.
    Includes a Notification Service Extension base class for rich media attachments
    and a Notification Content Extension base view controller for custom UI.
  DESC
  s.homepage         = 'https://github.com/appsOnAir'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AppsOnAir' => 'dev@appsonair.com' }

  # Local path — CocoaPods will pick up files from here
  s.source           = { :path => '.' }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  # ── Default subspec (main app target) ─────────────────────────────────────────
  # `pod 'AppsOnAirPush'` installs only this subspec by default.
  s.default_subspecs = 'Core'

  # ── Core — link to your main app target ───────────────────────────────────────
  s.subspec 'Core' do |core|
    core.source_files = 'Sources/AppsOnAirPush/**/*.swift'
    core.frameworks   = 'UIKit', 'UserNotifications', 'Security', 'BackgroundTasks'
    # Shared device/app metadata + app-id resolution used by AppsOnAirDeviceInfo.
    core.dependency 'AppsOnAir-Core'
  end

  # ── ServiceExtension — link to your Notification Service Extension target ONLY ─
  # UIKit is unavailable inside a Notification Service Extension.
  # Usage: pod 'AppsOnAirPush/ServiceExtension'
  s.subspec 'ServiceExtension' do |ext|
    ext.source_files = 'Sources/AppsOnAirPushServiceExt/**/*.swift'
    ext.frameworks   = 'Foundation', 'UserNotifications'
  end

  # ── ContentExtension — link to your Notification Content Extension target ONLY ─
  # Usage: pod 'AppsOnAirPush/ContentExtension'
  s.subspec 'ContentExtension' do |content|
    content.source_files = 'Sources/AppsOnAirPushContentExt/**/*.swift'
    content.frameworks   = 'UIKit', 'UserNotifications', 'UserNotificationsUI'
  end
end
