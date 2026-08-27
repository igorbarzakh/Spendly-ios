import XCTest
@testable import Spendly

final class AppearanceConfigurationTests: XCTestCase {
    func testAppUsesLightInterfaceStyleUntilDarkModeIsDesigned() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIUserInterfaceStyle") as? String, "Light")
    }
}
