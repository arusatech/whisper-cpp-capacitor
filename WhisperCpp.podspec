require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'WhisperCpp'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository'] && package['repository']['url'] ? package['repository']['url'] : ''
  s.author = package['author'] || ''
  s.source = { :git => (package['repository'] && package['repository']['url']) || '', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,mm}'
  s.ios.deployment_target = '13.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.0'
  s.vendored_frameworks = 'ios/Frameworks/WhisperCpp.framework'
end
