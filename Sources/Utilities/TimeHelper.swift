//  Created by Stas Kirichok on 23-08-2018.
//  Copyright 2025 EPAM Systems
//  
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//      https://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

enum TimeHelper {
  
  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    
    return formatter
  }()

  private static let lock = NSLock()
  private static var notBefore: Date?

  static func currentTimeAsString() -> String {
      lock.lock()
      let floor = notBefore
      lock.unlock()
      return formatter.string(from: max(Date(), floor ?? .distantPast))
  }

  /// Never stamp earlier than `date` from now on. A process that joins a launch another
  /// device created must not report items that start before that launch: ReportPortal
  /// rejects them, and the async v2 API drops them silently, so a device whose clock lags
  /// the creator's would lose every class it runs.
  static func clamp(notBefore date: Date) {
      lock.lock()
      defer { lock.unlock() }
      notBefore = max(notBefore ?? date, date)
  }

  /// Parses a ReportPortal timestamp ("2026-09-07T11:37:03.436Z" or "2026-09-07T13:28:14Z").
  static func date(fromServer string: String?) -> Date? {
      guard let string else { return nil }
      let parser = ISO8601DateFormatter()
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = parser.date(from: string) { return date }
      parser.formatOptions = [.withInternetDateTime]
      return parser.date(from: string)
  }

}
