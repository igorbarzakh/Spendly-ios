import SwiftUI

enum AppColor {
    static let blue = Color(hex: 0x0066CC)
    static let white = Color(hex: 0xFFFFFF)
    static let gray = Color(hex: 0xF5F5F7)
    static let black = Color(hex: 0x1D1D1F)
    static let muted = Color(hex: 0x8A8A8D)
    static let placeholder = Color(hex: 0xC5C5C6)
    static let border = Color.black.opacity(0.08)
    static let danger = Color.red
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
