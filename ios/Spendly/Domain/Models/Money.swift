import Foundation

struct Money: Codable, Sendable, Hashable {
    enum ValidationError: Error, Equatable {
        case negativeMinorUnits
        case invalidCurrencyCode
        case currencyMismatch
        case overflow
    }

    let minorUnits: Int64
    let currencyCode: String

    init(minorUnits: Int64, currencyCode: String) throws {
        guard minorUnits >= 0 else {
            throw ValidationError.negativeMinorUnits
        }

        let currencyBytes = Array(currencyCode.utf8)
        guard currencyBytes.count == 3,
              currencyBytes.allSatisfy({ (65...90).contains($0) })
        else {
            throw ValidationError.invalidCurrencyCode
        }

        self.minorUnits = minorUnits
        self.currencyCode = currencyCode
    }

    func adding(_ other: Money) throws -> Money {
        guard currencyCode == other.currencyCode else {
            throw ValidationError.currencyMismatch
        }

        let result = minorUnits.addingReportingOverflow(other.minorUnits)
        guard !result.overflow else {
            throw ValidationError.overflow
        }

        return try Money(minorUnits: result.partialValue, currencyCode: currencyCode)
    }
}

