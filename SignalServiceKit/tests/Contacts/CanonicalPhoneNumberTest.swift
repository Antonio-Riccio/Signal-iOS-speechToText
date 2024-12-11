//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class CanonicalPhoneNumberTest: XCTestCase {
    func testBenin() {
        let oldFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+22990011234")!)
        XCTAssertEqual(oldFormat.rawValue.stringValue, "+2290190011234")
        XCTAssertEqual(oldFormat.alternatePhoneNumbers().map(\.stringValue), ["+22990011234"])

        let newFormat = CanonicalPhoneNumber(nonCanonicalPhoneNumber: E164("+2290195123456")!)
        XCTAssertEqual(newFormat.rawValue.stringValue, "+2290195123456")
        XCTAssertEqual(newFormat.alternatePhoneNumbers().map(\.stringValue), ["+22995123456"])
    }
}
