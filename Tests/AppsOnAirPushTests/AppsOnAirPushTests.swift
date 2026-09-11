import XCTest
@testable import AppsOnAirPush

final class AppsOnAirPushTests: XCTestCase {

    func testDeviceIdIsStable() {
        let first = AppsOnAirPush.deviceId
        let second = AppsOnAirPush.deviceId

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    func testAPNsTokenHexConversion() {
        let data = Data([0x01, 0xAF, 0x00])
        let value = APNsProvider.hexToken(from: data)

        XCTAssertEqual(value, "01af00")
    }
}
