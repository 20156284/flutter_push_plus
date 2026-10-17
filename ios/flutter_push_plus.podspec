#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_push_plus.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_push_plus'
  s.version          = '0.4.2'
  s.summary          = 'Unified remote push (APNs/FCM), local notifications and tap routing for Flutter.'
  s.description      = <<-DESC
Unified remote push (APNs/FCM), local notifications and tap routing for Flutter.
                       DESC
  s.homepage         = 'https://github.com/20156284/flutter_push_plus'
  s.license          = { :file => '../LICENSE' }
  s.author           = { '20156284' => 'https://github.com/20156284' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_push_plus/Sources/flutter_push_plus/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'flutter_push_plus_privacy' => ['flutter_push_plus/Sources/flutter_push_plus/PrivacyInfo.xcprivacy']}
end
