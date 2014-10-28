#
# Be sure to run `pod lib lint SIEnsemblesExtensions.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SIEnsemblesExtensions"
  s.version          = "0.1.0"
  s.summary          = "A short description of SIEnsemblesExtensions."
  s.description      = <<-DESC
                       An optional longer description of SIEnsemblesExtensions

                       * Markdown format.
                       * Don't worry about the indent, we strip it!
                       DESC
  s.homepage         = "https://github.com/iiiyu/SIEnsemblesExtensions"
  # s.screenshots     = "www.example.com/screenshots_1", "www.example.com/screenshots_2"
  s.license          = 'MIT'
  s.author           = { "Xiao ChenYu" => "apple.iiiyu@gmail.com" }
  s.source           = { :git => "https://github.com/iiiyu/SIEnsemblesExtensions.git", :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.7'
  s.requires_arc = true

  s.source_files = 'Pod/Classes'
  # s.resource_bundles = {
  #   'SIEnsemblesExtensions' => ['Pod/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
