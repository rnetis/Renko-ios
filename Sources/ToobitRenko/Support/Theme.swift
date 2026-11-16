import SwiftUI

/// Dark terminal palette used across the app.
enum Theme {
    static let background = Color(hex: 0x0B0E11)
    static let surface = Color(hex: 0x151A20)
    static let grid = Color(hex: 0x1E2530)
    static let text = Color(hex: 0xEAECEF)
    static let secondary = Color(hex: 0x848E9C)
    static let up = Color(hex: 0x0ECB81)
    static let down = Color(hex: 0xF6465D)
    static let accent = Color(hex: 0xF0B90B)
    static let emaFast = Color(hex: 0x4FC3F7)
    static let emaSlow = Color(hex: 0xB388FF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
