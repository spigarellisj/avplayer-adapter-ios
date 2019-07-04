# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

workspace 'YouboraAVPlayerAdapter.xcworkspace'

def common_pods
    pod 'YouboraLib',:path => '../lib-plugin-ios'
    #pod 'YouboraLib', '~> 6.5.0'
end

target 'YouboraAVPlayerAdapter' do
  project 'YouboraAVPlayerAdapter.xcodeproj'
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  platform :ios, '9.2'

  # Pods for YouboraAVPlayerAdapter
    common_pods
    pod 'AVPlayerDNAPlugin', '~> 1.1.8'
end 

target 'YouboraAVPlayerAdapter tvOS' do
    project 'YouboraAVPlayerAdapter.xcodeproj'
    # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
    use_frameworks!

    platform :tvos, '9.0' 

    # Pods for YouboraAVPlayerAdapter
    common_pods
end

target 'YouboraAVPlayerAdapter OSX' do
    project 'YouboraAVPlayerAdapter.xcodeproj'
    # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
    use_frameworks!

    platform :osx, '10.10' 

    # Pods for YouboraAVPlayerAdapter
    common_pods
end

target 'AVPlayerAdapterExampleP2P' do
  project 'ExampleP2P/AVPlayerAdapterExampleP2P.xcodeproj'
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!
  
  platform :osx, '10.10'

  # Pods for YouboraAVPlayerAdapter
  common_pods
end

target 'AVPlayerAdapterExample' do
  project 'Example/AVPlayerAdapterExample.xcodeproj'
  # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
  use_frameworks!

  platform :ios, '9.2'

  # Pods for AVPlayerAdapterExample
  #pod 'YouboraLib',:path => '../lib-plugin-ios'
  pod 'AVPlayerDNAPlugin', '~> 1.1.8'
end

target 'AVPlayerAdaptertvOSExample' do
    project 'AVPlayerAdaptertvOSExample/AVPlayerAdaptertvOSExample.xcodeproj'
    # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
    use_frameworks!
    
    platform :tvos, '9.0' 
    
    # Pods for AVPlayerAdapterExample
    #pod 'YouboraLib',:path => '../lib-plugin-ios'
end

target 'AVPlayerAdapterOSXExample' do
    project 'AVPlayerAdapterOSXExample/AVPlayerAdapterOSXExample.xcodeproj'
    # Uncomment the next line if you're using Swift or would like to use dynamic frameworks
    use_frameworks!
    
    platform :macos, '10.10' 
    
    # Pods for AVPlayerAdapterExample
    #pod 'YouboraLib',:path => '../lib-plugin-ios'
    #pod 'YouboraLib', '~> 6.4.0'
end
