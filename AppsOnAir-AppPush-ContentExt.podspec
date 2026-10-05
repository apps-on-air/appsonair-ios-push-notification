Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush-ContentExt'
  # Released together with AppsOnAir-AppPush — keep the same version.
  s.version          = '1.0.6-beta'
  s.summary          = 'AppsOnAir Push Notification Content Extension for iOS'
  s.description      = <<-DESC
    Base view controller for your Notification Content Extension: renders the
    image, title and body of AppsOnAir pushes.
    Link to your Notification Content Extension target only.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/PushNotification/ios-sdk-setup'
  s.readme           = "https://github.com/apps-on-air/appsonair-ios-push-notification/blob/main/README.md"
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  # A pod of its own (module AppsOnAir_AppPush_ContentExt, same as the SPM product) —
  # see AppsOnAir-AppPush-ServiceExt.podspec for why this is not a subspec.
  s.source_files = 'Sources/AppsOnAirPushContentExt/**/*.swift'
  s.frameworks   = 'UIKit', 'UserNotifications', 'UserNotificationsUI'
  s.pod_target_xcconfig = { 'LM_SKIP_METADATA_EXTRACTION' => 'YES' }
end
