require 'xcodeproj'
project = Xcodeproj::Project.new(File.join(__dir__, 'PocketLibre.xcodeproj'))
app = project.new_target(:application, 'PocketLibre', :ios, '17.0')
app.product_name = 'PocketLibre'
group = project.main_group.new_group('PocketLibre', 'PocketLibre')
Dir.glob(File.join(__dir__, 'PocketLibre', '*.swift')).sort.each { |p| app.source_build_phase.add_file_reference(group.new_file(File.basename(p))) }
app.resources_build_phase.add_file_reference(group.new_file('Assets.xcassets'))
app.resources_build_phase.add_file_reference(group.new_file('ThirdPartyNotices.txt'))
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/argmaxinc/argmax-oss-swift.git'
package.requirement = { 'kind' => 'exactVersion', 'version' => '1.1.1' }
project.root_object.package_references << package
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'WhisperKit'
app.package_product_dependencies << product
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product
app.frameworks_build_phase.files << build_file
app.build_configurations.each do |c|
  c.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.maxonary.pocketlibre',
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'Pocket Libre',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'TARGETED_DEVICE_FAMILY' => '1', 'CODE_SIGN_STYLE' => 'Automatic',
    'MARKETING_VERSION' => '0.3.2', 'CURRENT_PROJECT_VERSION' => '7',
    'CODE_SIGN_ENTITLEMENTS' => 'PocketLibre/PocketLibre.entitlements',
    'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription' => 'Pocket Libre verbindet sich lokal mit deinem Pocket, um ausgewählte Aufnahmen zu importieren.',
    'INFOPLIST_KEY_NSLocalNetworkUsageDescription' => 'Pocket Libre liest ausgewählte Aufnahmen direkt über den lokalen Pocket-Hotspot, ohne Cloud.',
    'SUPPORTS_MACCATALYST' => 'NO', 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD' => 'NO',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES'
  })
end
tests = project.new_target(:unit_test_bundle, 'PocketLibreTests', :ios, '17.0')
tests.add_dependency(app)
test_group = project.main_group.new_group('PocketLibreTests', 'PocketLibreTests')
Dir.glob(File.join(__dir__, 'PocketLibreTests', '*.swift')).sort.each { |p| tests.source_build_phase.add_file_reference(test_group.new_file(File.basename(p))) }
tests.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER' => 'com.maxonary.pocketlibre.tests', 'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/PocketLibre.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PocketLibre', 'BUNDLE_LOADER' => '$(TEST_HOST)'})
end
ui_tests = project.new_target(:ui_test_bundle, 'PocketLibreUITests', :ios, '17.0')
ui_tests.add_dependency(app)
ui_group = project.main_group.new_group('PocketLibreUITests', 'PocketLibreUITests')
Dir.glob(File.join(__dir__, 'PocketLibreUITests', '*.swift')).sort.each { |p| ui_tests.source_build_phase.add_file_reference(ui_group.new_file(File.basename(p))) }
ui_tests.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER' => 'com.maxonary.pocketlibre.uitests', 'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES', 'TEST_TARGET_NAME' => 'PocketLibre'})
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.add_test_target(ui_tests)
env = REXML::Element.new('EnvironmentVariables')
entry = env.add_element('EnvironmentVariable')
entry.add_attributes({'key' => 'POCKET_TEST_AUDIO', 'value' => '$(POCKET_TEST_AUDIO)', 'isEnabled' => 'YES'})
scheme.launch_action.xml_element.add_element(env)
scheme.save_as(project.path, 'PocketLibre', true)
