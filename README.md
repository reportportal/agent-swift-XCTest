# XCTest Agent for ReportPortal


[![Version](https://img.shields.io/cocoapods/v/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![License](https://img.shields.io/cocoapods/l/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![Platform](https://img.shields.io/cocoapods/p/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)

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

## Report Portal properties

The properties for Report Portal configuration should be set in the `Info.plist` file of your Test Target. If you Test Target does't have an `Info.plist`, follow these steps to add:

1. In your Test Target Folder, create a Property List named `Info.plist`.
2. In Test Target Settings, configure 'Info.plist File' with the path `TestTargetFolderName/Info.plist`.

Now, you can specify the Report Portal properties:

* ReportPortalURL - URL to API of report portal (exaple https://report-portal.company.com/api/v1).
* ReportPortalToken - token for authentication which you can get from RP account settings.
* ReportPortalLaunchName - name of launch.
* Principal class - use ReportPortalAgent.RPListener from ReportPortalAgent lib. Also you can specify your own Observer which should conform to [XCTestObservation](https://developer.apple.com/documentation/xctest/xctestobservation) protocol.
* PushTestDataToReportPortal - can be used to switch off/on reporting
* ReportPortalProjectName - project name from Report Portal
* ReportPortalTags(optional) - can be used to specify tags, separated by comma.
* IsFinalTestBundle - use to mark last test target as YES, and all others as NO to allow single launch for them

Example:
![Alt text](./Screen%20Shot.png)

## Important Notes

Please be aware that this Report Portal agent is designed to work correctly only when tests are run sequentially. Parallel execution of tests is currently not supported.

## Authors

DarthRumata, stas.kirichok@windmill.ch ([Windmill Smart Solutions](https://github.com/Windmill-Smart-Solutions))

SergeVKom, sergvkom@gmail.com (original library)

## License

ReportPortalAgent is available under the MIT license. See the LICENSE file for more info.
