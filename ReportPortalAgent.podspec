Pod::Spec.new do |s|
    s.name             = 'ReportPortalAgent'
    s.version          = '3.0.0'
    s.summary          = 'Agent to push test results on Report Portal'

    s.description      = <<-DESC
        This agent allows to see test results on the Report Portal - http://reportportal.io
    DESC

    s.homepage         = 'https://github.com/Windmill-Smart-Solutions/ReportPortalAgent'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'DarthRumata' => 'stas.kirichok@windmill.ch' }
    s.source           = { :git => 'https://github.com/Windmill-Smart-Solutions/ReportPortalAgent.git', :tag => s.version.to_s }

    s.ios.deployment_target = '10.3'
    s.tvos.deployment_target = '10.3'
    s.swift_version = '4.1.2'
    s.source_files = 'Sources/**/*.swift'

    s.weak_framework = "XCTest"
    s.pod_target_xcconfig = {
        'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(PLATFORM_DIR)/Developer/Library/Frameworks"',
    }
end
