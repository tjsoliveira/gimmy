import SwiftUI

// Kinetic Dark Minimal — tokens from DESIGN.md.

extension Color {
    // Surfaces & elevation
    static let appBackground = Color(hex: "0E0E10")      // surface-dim / container-lowest
    static let appSurface = Color(hex: "131315")         // surface
    static let appSurfaceLow = Color(hex: "1C1B1E")      // surface-container-low
    static let appSurfaceMid = Color(hex: "222126")      // surface-container
    static let appSurfaceHigh = Color(hex: "262529")     // surface-container-high
    static let appSurfaceHighest = Color(hex: "323135")  // surface-container-highest

    // Borders
    static let appBorder = Color.white.opacity(0.08)
    static let appBorderSubtle = Color.white.opacity(0.06)
    static let appBorderDefault = Color.white.opacity(0.10)
    static let appBorderStrong = Color.white.opacity(0.16)

    // Text
    static let textPrimary = Color(hex: "F4F4F5")
    static let textSecondary = Color(hex: "A1A1AA")
    static let textMuted = Color(hex: "71717A")
    static let textInverse = Color(hex: "0E0E10")

    // Brand
    static let linearBlue = Color(hex: "5E6AD2")
    static let linearBlueHover = Color(hex: "4E5AC0")
    static let linearBlueContainer = Color(hex: "5E6AD2").opacity(0.15)

    // Set types
    static let setWarmup = Color(hex: "F59E0B")
    static let setNormal = Color(hex: "71717A")
    static let setDropset = Color(hex: "A855F7")
    /// Not in DESIGN.md yet: rest-pause needs its own hue, distinct from drop.
    static let setRestPause = Color(hex: "14B8A6")
    static let setFailure = Color(hex: "EF4444")

    // Status
    static let statusSuccess = Color(hex: "22C55E")
    static let statusWarning = Color(hex: "F59E0B")
    static let statusDanger = Color(hex: "EF4444")
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    }
}

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let card: CGFloat = 16
}

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Type scale from DESIGN.md. Numbers use SF Rounded.
enum AppFont {
    static let display = Font.system(size: 28, weight: .bold)
    static let titleLarge = Font.system(size: 20, weight: .bold)
    static let titleMedium = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let bodyBold = Font.system(size: 15, weight: .semibold)
    static let caption = Font.system(size: 12, weight: .medium)
    static let captionBold = Font.system(size: 10, weight: .bold)

    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Card: surface, subtle border, 16 pt radius.
    func appCard(padding: CGFloat = Spacing.md, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.appBorder, lineWidth: 1))
    }

    /// Uppercase 10 pt label with 0.05em tracking.
    func captionLabel(_ color: Color = .textMuted) -> some View {
        self
            .font(AppFont.captionBold)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.bodyBold)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(configuration.isPressed ? Color.linearBlueHover : Color.linearBlue,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .shadow(color: Color.linearBlue.opacity(isEnabled ? 0.3 : 0), radius: 8, y: 4)
            .opacity(isEnabled ? 1 : 0.55)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 40
    var foreground: Color = .textPrimary
    var background: Color = .appSurfaceHigh
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? Color.appSurfaceHighest : background,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(Color.appBorderDefault, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.55)
    }
}

/// Small square-ish button used by the − / + steppers.
struct StepperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 44, height: 44)
            .background(configuration.isPressed ? Color.appSurfaceHighest : Color.appSurfaceHigh,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
