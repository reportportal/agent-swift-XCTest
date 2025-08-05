# XCTest Agent for ReportPortal


[![CocoaPods](https://img.shields.io/cocoapods/v/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![Platform](https://img.shields.io/cocoapods/p/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![Validate](https://github.com/reportportal/agent-swift-XCTest/actions/workflows/validate.yml/badge.svg)](https://github.com/reportportal/agent-swift-XCTest/actions/workflows/validate.yml)
[![Join Slack chat!](https://img.shields.io/badge/slack-join-brightgreen.svg)](https://slack.epmrpp.reportportal.io/)
[![stackoverflow](https://img.shields.io/badge/reportportal-stackoverflow-orange.svg?style=flat)](http://stackoverflow.com/questions/tagged/reportportal)
[![Build with Love](https://img.shields.io/badge/build%20with-❤%EF%B8%8F%E2%80%8D-lightgrey.svg)](http://reportportal.io?style=flat)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Installation

ReportPortalAgent is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'ReportPortal'
```
and install it:
```bash
cd <project>
pod install
```

Also available through SPM by name "agent-swift-xctest" or URL of current repo

## Report Portal properties

The properties for Report Portal configuration should be set in the `Info.plist` file of your Test Target. If you Test Target does't have an `Info.plist`, follow these steps to add:

1. In your Test Target Folder, create a Property List named `Info.plist`.
2. In Test Target Settings, configure 'Info.plist File' with the path `TestTargetFolderName/Info.plist`.

Now, you can specify the Report Portal properties:

* ReportPortalURL - URL to API of report portal (exaple https://report-portal.company.com/api/v1).
* ReportPortalToken - token for authentication which you can get from RP account settings.
* ReportPortalLaunchName - name of launch.
* Principal class - use ReportPortalAgent.RPListener from ReportPortalAgent lib for SPM or ReportPortal.RPListener for Cocoapods. Also you can specify your own Observer which should conform to [XCTestObservation](https://developer.apple.com/documentation/xctest/xctestobservation) protocol.
* PushTestDataToReportPortal - can be used to switch off/on reporting
* ReportPortalProjectName - project name from Report Portal
* ReportPortalTags(optional) - can be used to specify tags, separated by comma.
* IsFinalTestBundle - use to mark last test target as YES, and all others as NO to allow single launch for them

Example:
![Alt text](./Screen%20Shot.png)

## Test Plan Name in Launch Names

To include test plan names in ReportPortal launch names, add the `TEST_PLAN_NAME` environment variable to your `.xctestplan` file:

```json
{
  "defaultOptions": {
    "environmentVariableEntries": [
      {
        "key": "TEST_PLAN_NAME",
        "value": "Smoke Tests"
      }
    ]
  }
}
```

**Result:** Launch names will appear as `YourLaunchName: Smoke_Tests` in ReportPortal.

**Note:** Spaces in test plan names are automatically replaced with underscores for better compatibility.

**CI Override:** CI can override this value: `TEST_PLAN_NAME="Nightly Tests" xcodebuild test ...`

## Important Notes

Please be aware that this Report Portal agent is designed to work correctly only when tests are run sequentially. Parallel execution of tests is currently not supported.

## Authors
ReportPortal Team, <support@reportportal.io>

([@rusel95](https://github.com/rusel95))

@DarthRumata, <stas.kirichok@windmill.ch> ([Windmill Smart Solutions](https://github.com/Windmill-Smart-Solutions))

@SergeVKom, <sergvkom@gmail.com> (original library)

## License

Licensed under the [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) license (see the LICENSE file).
