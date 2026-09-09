import SwiftUI

enum AppColor {
    static let blue = Color(hex: 0x0066CC)
    static let white = Color(hex: 0xFFFFFF)
    static let gray = Color(hex: 0xF5F5F7)
    static let black = Color(hex: 0x1D1D1F)
    static let muted = Color(hex: 0x8A8A8D)
    static let weekend = Color(hex: 0x8B8B8B)
    static let placeholder = Color(hex: 0xC5C5C6)
    static let border = Color.black.opacity(0.08)
    static let danger = Color.red

    static let dashboardBackground = Color(uiColor: .systemGroupedBackground)
    static let dashboardSurface = Color(uiColor: .systemBackground)
    static let dashboardPrimaryText = Color(uiColor: .label)
    static let dashboardSecondaryText = Color(uiColor: .secondaryLabel)
    static let dashboardSeparator = Color(uiColor: .separator)
    static let dashboardProgressTrack = Color(uiColor: .systemGray5)
    static let dashboardAccent = Color(hex: 0x615FFF)
    static let dashboardAccentSoft = dashboardAccent.opacity(0.12)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct ExpenseCategoryPresentation: Equatable, Hashable {
    static let customSymbolName = "tag.fill"
    static let customTintHex: UInt32 = 0x71717A

    static let standardCategories: [ExpenseCategoryPresentation] = [
        .init(name: "Продукты", symbolName: "basket.fill", tintHex: 0x238636),
        .init(name: "Транспорт", symbolName: "car.fill", tintHex: 0xF97316),
        .init(name: "Кафе", symbolName: "cup.and.saucer.fill", tintHex: 0x8B5E3C),
        .init(name: "Развлечения", symbolName: "theatermasks.fill", tintHex: 0x7C3AED),
        .init(name: "Дом", symbolName: "house.fill", tintHex: 0xC75C3C),
        .init(name: "Здоровье", symbolName: "heart.fill", tintHex: 0xD92D20),
        .init(name: "Подарки", symbolName: "gift.fill", tintHex: 0xD69E00),
        .init(name: "Подписки", symbolName: "music.note", tintHex: 0x008A83),
        .init(name: "Одежда", symbolName: "tshirt.fill", tintHex: 0x2563EB),
        .init(name: "Счета и услуги", symbolName: "doc.text.fill", tintHex: 0x596579),
        .init(name: "Образование", symbolName: "book.fill", tintHex: 0x4F46A5),
        .init(name: "Путешествия", symbolName: "airplane", tintHex: 0x0891B2),
        .init(name: "Красота", symbolName: "sparkles", tintHex: 0xD63384)
    ]

    private static let legacyCategories: [ExpenseCategoryPresentation] = [
        .init(name: "Покупки", symbolName: "bag.fill", tintHex: 0x2563EB)
    ]

    let name: String
    let symbolName: String
    let tintHex: UInt32

    static func standard(matching name: String) -> ExpenseCategoryPresentation? {
        let normalized = normalizedName(name)
        let canonicalName = normalized == normalizedName("Кафе и рестораны")
            ? normalizedName("Кафе")
            : normalized
        return standardCategories.first { normalizedName($0.name) == canonicalName }
            ?? legacyCategories.first { normalizedName($0.name) == canonicalName }
    }

    static func resolved(for name: String) -> ExpenseCategoryPresentation {
        standard(matching: name) ?? ExpenseCategoryPresentation(
            name: displayName(name),
            symbolName: customSymbolName,
            tintHex: customTintHex
        )
    }

    static func normalizedName(_ value: String) -> String {
        displayName(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ru_RU"))
            .lowercased()
    }

    static func displayName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
