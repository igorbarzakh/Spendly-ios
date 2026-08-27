import Foundation

enum MoneyFormatter {
    static let groupingSeparator = " "
    static let decimalSeparator = ","
    static let maxIntegerDigits = 12
    static let maxFractionDigits = 2

    static func rubles(_ amount: Int64) -> String {
        let formatter = groupedIntegerFormatter
        let value = NSNumber(value: amount)
        return (formatter.string(from: value) ?? "\(amount)") + " ₽"
    }

    static func inputText(from raw: String) -> String {
        let sanitized = sanitizedInput(raw)
        guard !sanitized.isEmpty else { return "" }

        let parts = sanitized.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let integerPart = String(parts[0].prefix(maxIntegerDigits))
        let groupedInteger = groupedDigits(integerPart)

        guard parts.count == 2 else {
            return groupedInteger
        }

        let fractionalPart = String(parts[1].prefix(maxFractionDigits))
        return groupedInteger + decimalSeparator + fractionalPart
    }

    static func minorUnits(from input: String) -> Int? {
        let normalized = sanitizedInput(input)
            .replacingOccurrences(of: decimalSeparator, with: ".")

        guard
            let value = Decimal(string: normalized),
            value > 0
        else {
            return nil
        }

        let minorUnits = value * 100
        return NSDecimalNumber(decimal: minorUnits).intValue
    }

    private static var groupedIntegerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = groupingSeparator
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }

    private static func groupedDigits(_ digits: String) -> String {
        let integerDigits = digits.filter(\.isNumber)
        guard !integerDigits.isEmpty else { return "0" }

        let reversed = Array(integerDigits.reversed())
        var chunks: [String] = []
        chunks.reserveCapacity((integerDigits.count + 2) / 3)

        for start in stride(from: 0, to: reversed.count, by: 3) {
            let end = min(start + 3, reversed.count)
            chunks.append(String(reversed[start..<end].reversed()))
        }

        return chunks.reversed().joined(separator: groupingSeparator)
    }

    private static func sanitizedInput(_ raw: String) -> String {
        let withoutSpaces = raw
            .replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: " ", with: "")

        var result = ""
        var hasSeparator = false

        for character in withoutSpaces {
            if character.isNumber {
                result.append(character)
            } else if (character == "," || character == ".") && !hasSeparator {
                result.append(decimalSeparator)
                hasSeparator = true
            }
        }

        return result
    }
}
