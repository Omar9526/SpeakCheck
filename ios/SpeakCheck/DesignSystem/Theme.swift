import SwiftUI

/// Палитра и метрики дизайн-системы SpeakCheck (ТЗ, раздел 5). Стиль строго тёмный.
enum Theme {
    enum Colors {
        static let background = Color(hex: 0x101C32)
        static let backgroundDeep = Color(hex: 0x0B1426)
        static let surface = Color(hex: 0x1E293B)
        static let surfaceRaised = Color(hex: 0x263449)
        static let stroke = Color.white.opacity(0.07)

        static let accent = Color(hex: 0x2563EB)
        static let accentLight = Color(hex: 0x38BDF8)
        static let success = Color(hex: 0x34D399)
        static let warning = Color(hex: 0xFBBF24)
        static let danger = Color(hex: 0xFB7185)
        static let violet = Color(hex: 0xA78BFA)

        static let textPrimary = Color(hex: 0xF8FAFC)
        static let textSecondary = Color(hex: 0x94A3B8)
        static let textTertiary = Color(hex: 0x64748B)

        static let accentGradient = LinearGradient(
            colors: [accent, accentLight],
            startPoint: .leading, endPoint: .trailing
        )
    }

    enum Radius {
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 20
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Фон экранов: глубокий синий с мягким свечением сверху, как в макете.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Theme.Colors.background
            RadialGradient(
                colors: [Theme.Colors.accent.opacity(0.18), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Стандартный фон экрана + тёмная навигация.
    func screenBackground() -> some View {
        background(ScreenBackground())
            .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
