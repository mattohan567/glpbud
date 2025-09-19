import SwiftUI

// MARK: - Theme Colors & Design Tokens
enum Theme {
    // Gradient colors
    static let gradientTop = Color(hex: 0x0EA5E9)     // sky-500
    static let gradientBottom = Color(hex: 0x8B5CF6)  // violet-500

    // Semantic colors
    static let accent = Color(hex: 0x22C55E)          // emerald-500
    static let warn = Color(hex: 0xF59E0B)            // amber-500
    static let danger = Color(hex: 0xEF4444)          // red-500
    static let success = Color(hex: 0x22C55E)         // emerald-500
    static let actionPurple = Color(hex: 0x7C3AED)    // violet-600 (darker purple)

    // Card backgrounds
    static let cardBgLight = Color.white.opacity(0.18)
    static let cardBgDark = Color.black.opacity(0.25)

    // Convenience property for card background (adapts to color scheme)
    static let cardBackground = Color.white.opacity(0.18)

    // Text colors
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.8)
    static let textTertiary = Color.white.opacity(0.6)

    // Spacing
    static let spacing = (
        xs: CGFloat(4),
        sm: CGFloat(8),
        md: CGFloat(12),
        lg: CGFloat(16),
        xl: CGFloat(20),
        xxl: CGFloat(24)
    )

    // Corner radius
    static let cornerRadius = (
        sm: CGFloat(8),
        md: CGFloat(12),
        lg: CGFloat(16),
        xl: CGFloat(20),
        pill: CGFloat(100)
    )

    // Animation
    static let springAnimation = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let easeAnimation = Animation.easeOut(duration: 0.25)
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Gradient Presets
extension LinearGradient {
    static let appGradient = LinearGradient(
        colors: [Theme.gradientTop, Theme.gradientBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let accentGradient = LinearGradient(
        colors: [Theme.accent, Theme.gradientTop],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let tabBarGradient = LinearGradient(
        colors: [
            Color(hex: 0x7C3AED).opacity(0.95), // bluish purple top
            Color(hex: 0x3B82F6).opacity(0.8)   // lighter blue bottom
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - Font Extensions
extension Font {
    static let heroTitle = Font.system(.largeTitle, design: .rounded).bold()
    static let sectionTitle = Font.system(.title2, design: .rounded).bold()
    static let cardTitle = Font.system(.headline).weight(.semibold)
    static let bodyMedium = Font.system(.body).weight(.medium)
    static let captionMedium = Font.system(.caption).weight(.medium)
}