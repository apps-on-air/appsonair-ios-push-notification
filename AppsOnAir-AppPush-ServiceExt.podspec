Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush-ServiceExt'
  s.version          = '1.0.2-beta'
  s.summary          = 'AppsOnAir Push Notifications — Notification Service Extension'
  s.description      = <<-DESC
    Notification Service Extension component of the AppsOnAir Push SDK.
    Provides rich media downloads, text overrides, badge management, and
    delivery receipt reporting. Link to your NSE target only — never the main app.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/AppPushService/ios-sdk-setup'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  s.source_files = 'Sources/AppsOnAirPushServiceExt/**/*.swift',
                   'Sources/AppsOnAirPushShared/**/*.swift'
  s.frameworks   = 'Foundation', 'UserNotifications'
end
