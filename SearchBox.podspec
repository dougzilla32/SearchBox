#
# Be sure to run `pod lib lint SearchBox.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SearchBox'
  s.version          = '1.0.0'
  s.summary          = 'A subclass of NSSearchField that provides a completions drop-down menu'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
This CocoaPod provides a subclass of NSSearchField called 'SearchBox', which has a completions drop-down menu akin to modern search fields such as the google search field.  It is a modified Swift port of the "CustomMenus" sample project from Apple:

https://developer.apple.com/library/content/samplecode/CustomMenus
                       DESC

  s.homepage         = 'https://github.com/dougzilla32/SearchBox'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'dougzilla32' => 'dougzilla32@gmail.com' }
  s.source           = { :git => 'https://github.com/dougzilla32/SearchBox.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.platform = :osx
  s.osx.deployment_target = "10.11"

  s.source_files = 'SearchBox/Classes/**/*'

  s.swift_version = "5.0"
  
  s.resources = 'SearchBox/**/*.xcassets'

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'Cocoa'
  
  s.dependency 'PromiseKit/CorePromise', '~> 7.0'
  s.dependency 'SwiftyBeaver', '~> 1.5'
end
