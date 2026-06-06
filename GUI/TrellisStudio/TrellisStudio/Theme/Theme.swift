import SwiftUI

struct Theme {
    static let background = Color(hex: 0x0F1117)
    static let slateGray = Color(hex: 0x8B8FA3)
    static let accentIndigo = Color(hex: 0x5D5CDE)
    static let accentViolet = Color(hex: 0x9F5CDE)
    static let border = Color(hex: 0x2C2F3E)
    
    // Light mode support
    static let backgroundLight = Color(hex: 0xF5F6F8)
    static let textMutedLight = Color(hex: 0x6B6D7A)
    static let borderLight = Color(hex: 0xE2E4EB)
    
    // Accents for tags/status
    static let successGreen = Color(hex: 0x2ECC71)
    static let warningAmber = Color(hex: 0xF39C12)
    static let errorRed = Color(hex: 0xE74C3C)
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
    
    struct CornerRadius {
        static let button: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 20
    }
    
    static var accentGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [accentIndigo, accentViolet]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
