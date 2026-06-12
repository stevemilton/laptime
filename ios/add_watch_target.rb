#!/usr/bin/env ruby
# Adds the WatchApp target to the Xcode project programmatically.
# Run once, then delete this file.

require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Check if WatchApp target already exists
if project.targets.any? { |t| t.name == 'WatchApp' }
  puts "WatchApp target already exists, skipping."
  exit 0
end

# Find the Runner target (for embedding)
runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found" unless runner_target

# Create the WatchApp target
watch_target = project.new_target(:application, 'WatchApp', :watchos, '9.0')
watch_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.laptime.laptime.watchkitapp'
  config.build_settings['INFOPLIST_FILE'] = 'WatchApp/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = '6FK49H335R'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'  # Watch
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '9.0'
  config.build_settings['SDKROOT'] = 'watchos'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  # HealthKit entitlement
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'WatchApp/WatchApp.entitlements'
end

# Create WatchApp group
watch_group = project.main_group.new_group('WatchApp', 'WatchApp')

# Add Swift source files
swift_files = %w[
  TestTrackWatchApp.swift
  ContentView.swift
  RecordingManager.swift
  LapDetector.swift
  WatchSessionManager.swift
  SessionData.swift
]

swift_files.each do |filename|
  file_ref = watch_group.new_file(filename)
  watch_target.source_build_phase.add_file_reference(file_ref)
end

# Add Info.plist (as reference, not compiled)
watch_group.new_file('Info.plist')

# Add Assets.xcassets
assets_ref = watch_group.new_file('Assets.xcassets')
watch_target.resources_build_phase.add_file_reference(assets_ref)

# Add "Embed Watch Content" build phase to Runner
embed_phase = runner_target.new_copy_files_build_phase('Embed Watch Content')
embed_phase.dst_subfolder_spec = '16'  # Watch content
embed_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'

watch_product = watch_target.product_reference
embed_file = embed_phase.add_file_reference(watch_product)
embed_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# Add target dependency
runner_target.add_dependency(watch_target)

# Save
project.save

puts "WatchApp target added successfully!"
puts "Next: Open Xcode, select WatchApp target, add HealthKit and Background Modes capabilities."
