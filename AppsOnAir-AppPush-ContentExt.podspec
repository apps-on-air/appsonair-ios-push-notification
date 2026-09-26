Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush-ContentExt'
  s.version          = '1.0.2-beta'
  s.summary          = 'AppsOnAir Push Notifications — Notification Content Extension'
  s.description      = <<-DESC
    Notification Content Extension component of the AppsOnAir Push SDK.
    Provides AppsOnAirContentViewController and AOAContentViewController — a built-in
    full-width image, title, and body layout for the expanded notification view.
    Link to your NCE target only — never the main app or NSE.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/AppPushService/ios-sdk-setup'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  s.source_files = 'Sources/AppsOnAirPushContentExt/**/*.swift'
  s.frameworks   = 'UIKit', 'UserNotifications', 'UserNotificationsUI'
end
