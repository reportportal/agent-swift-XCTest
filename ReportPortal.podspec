Pod::Spec.new do |s|
    s.name             = 'ReportPortal'
    s.version          = '4.0.1'
    s.summary          = 'Agent to push test results on Report Portal with parallel execution support'

    s.description      = <<-DESC
        This agent allows to see test results on the Report Portal - http://reportportal.io
        Version 4.0+ supports parallel test execution using Swift Concurrency.
    DESC

    s.homepage         = 'https://github.com/reportportal/agent-swift-XCTest'
    s.license          = { :type => 'Apache 2.0', :file => 'LICENSE' }
    s.author           = { 'ReportPortal Team' => 'support@reportportal.io' }
    s.source           = { :git => 'https://github.com/reportportal/agent-swift-XCTest.git', :tag => s.version.to_s }

    s.ios.deployment_target = '18.6'
    s.osx.deployment_target = '14.0'
    s.tvos.deployment_target = '18.2'
    s.swift_version = '5.5'
    s.source_files = 'Sources/**/*.swift'

    s.weak_frameworks = 'XCTest', 'AppIntents'
    s.pod_target_xcconfig = {
        'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(PLATFORM_DIR)/Developer/Library/Frameworks"',
        'ENABLE_TESTING_SEARCH_PATHS' => 'YES'
    }
end
