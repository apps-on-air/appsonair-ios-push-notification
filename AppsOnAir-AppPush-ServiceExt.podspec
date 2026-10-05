Pod::Spec.new do |s|
  s.name             = 'AppsOnAir-AppPush-ServiceExt'
  # Released together with AppsOnAir-AppPush — keep the same version.
  s.version          = '1.0.6-beta'
  s.summary          = 'AppsOnAir Push Notification Service Extension for iOS'
  s.description      = <<-DESC
    Base class for your Notification Service Extension: rich media download,
    title/body overrides, badge updates and delivery receipts for AppsOnAir pushes.
    Link to your Notification Service Extension target only.
  DESC
  s.homepage         = 'https://documentation.appsonair.com/MobileQuickstart/PushNotification/ios-sdk-setup'
  s.readme           = "https://github.com/apps-on-air/appsonair-ios-push-notification/blob/main/README.md"
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'devtools-logicwind' => 'devtools@logicwind.com' }

  s.source           = { :git => 'https://github.com/apps-on-air/appsonair-ios-push-notification.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  # A pod of its own (module AppsOnAir_AppPush_ServiceExt, same as the SPM product) rather
  # than a subspec of AppsOnAir-AppPush: subspecs share the root's module name, so an app
  # linking Core plus an NSE linking the ServiceExtension subspec produced two different
  # AppsOnAir_AppPush.framework products — "Multiple commands produce …" on archive and
  # the wrong framework embedded in the app with use_frameworks!.
  # AppsOnAirPushShared sources are compiled in, as in the Core subspec.
  s.source_files = 'Sources/AppsOnAirPushServiceExt/**/*.swift',
                   'Sources/AppsOnAirPushShared/**/*.swift'
  s.frameworks   = 'Foundation', 'UserNotifications'
  s.pod_target_xcconfig = { 'LM_SKIP_METADATA_EXTRACTION' => 'YES' }
end
