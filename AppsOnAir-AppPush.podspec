Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush'
  # Source of truth for the runtime SDK version — AppsOnAirDeviceInfo.sdkVersion
  # reads this back via SdkManager (org.cocoapods.AppsOnAir-AppPush). Keep
  # AppsOnAirDeviceInfo.fallbackSDKVersion in sync for the SPM-as-source case.
  s.version          = '0.0.4-alpha'
  s.summary          = 'AppsOnAir Push Notifications SDK for iOS'
  s.description      = <<-DESC
    Lightweight iOS push notification SDK using APNs directly. No Firebase dependency.
    Includes a Notification Service Extension base class for rich media attachments
    and a Notification Content Extension base view controller for custom UI.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/AppPushService/ios-sdk-setup'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  # ── Default subspec (main app target) ─────────────────────────────────────────
  # `pod 'AppsOnAir-AppPush'` installs only this subspec by default.
  s.default_subspecs = 'Core'

  # ── Core — link to your main app target ───────────────────────────────────────
  s.subspec 'Core' do |core|
    core.source_files = 'Sources/AppsOnAirPush/**/*.swift'
    core.frameworks   = 'UIKit', 'UserNotifications', 'Security', 'BackgroundTasks'
    # Shared device/app metadata + app-id resolution used by AppsOnAirDeviceInfo.
    core.dependency 'AppsOnAir-Core', '>= 1.2.3'
  end

  # ── ServiceExtension — link to your Notification Service Extension target ONLY ─
  # UIKit is unavailable inside a Notification Service Extension.
  # Usage: pod 'AppsOnAir-AppPush/ServiceExtension'
  s.subspec 'ServiceExtension' do |ext|
    ext.source_files = 'Sources/AppsOnAirPushServiceExt/**/*.swift'
    ext.frameworks   = 'Foundation', 'UserNotifications'
  end

  # ── ContentExtension — link to your Notification Content Extension target ONLY ─
  # Usage: pod 'AppsOnAir-AppPush/ContentExtension'
  s.subspec 'ContentExtension' do |content|
    content.source_files = 'Sources/AppsOnAirPushContentExt/**/*.swift'
    content.frameworks   = 'UIKit', 'UserNotifications', 'UserNotificationsUI'
  end
end
