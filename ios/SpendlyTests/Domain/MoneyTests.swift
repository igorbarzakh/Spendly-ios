import XCTest
@testable import Spendly

final class MoneyTests: XCTestCase {
    func testMinorUnitsUseInt64() throws {
        let money = try Money(minorUnits: 12_345, currencyCode: "RUB")

        let minorUnits: Int64 = money.minorUnits
        XCTAssertEqual(minorUnits, 12_345)
    }

    func testAddingDifferentCurrenciesFails() throws {
        let rubles = try Money(minorUnits: 100, currencyCode: "RUB")
        let dollars = try Money(minorUnits: 100, currencyCode: "USD")

        XCTAssertThrowsError(try rubles.adding(dollars)) { error in
            XCTAssertEqual(error as? Money.ValidationError, .currencyMismatch)
        }
    }

    func testNegativeMinorUnitsFailValidation() {
        XCTAssertThrowsError(try Money(minorUnits: -1, currencyCode: "RUB")) { error in
            XCTAssertEqual(error as? Money.ValidationError, .negativeMinorUnits)
        }
    }

    func testAddingOverflowFailsValidation() throws {
        let maximum = try Money(minorUnits: .max, currencyCode: "RUB")
        let one = try Money(minorUnits: 1, currencyCode: "RUB")

        XCTAssertThrowsError(try maximum.adding(one)) { error in
            XCTAssertEqual(error as? Money.ValidationError, .overflow)
        }
    }
}

