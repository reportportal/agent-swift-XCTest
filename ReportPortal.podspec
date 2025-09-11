Pod::Spec.new do |s|
    s.name             = 'ReportPortal'
    s.version          = '3.1.4'
    s.summary          = 'Agent to push test results on Report Portal'

    s.description      = <<-DESC
        This agent allows to see test results on the Report Portal - http://reportportal.io
    DESC

    s.homepage         = 'https://github.com/reportportal/agent-swift-XCTest'
    s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.author           = { 'ReportPortal Team' => 'support@reportportal.io' }
    s.source           = { :git => 'https://github.com/reportportal/agent-swift-XCTest.git', :tag => s.version.to_s }

    s.ios.deployment_target = '12.0'
    s.tvos.deployment_target = '12.0'
    s.swift_version = '4.2'
    s.source_files = 'Sources/**/*.swift'

    s.weak_framework = "XCTest"
    s.pod_target_xcconfig = {
        'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(PLATFORM_DIR)/Developer/Library/Frameworks"',
    }
end
