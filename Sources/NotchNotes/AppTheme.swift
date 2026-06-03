import AppKit
import SwiftUI

struct AppTheme: Equatable {
    let isDark: Bool
    let panelBackground: NSColor
    let contentBackground: NSColor
    let toolbarBackground: NSColor
    let rowBackground: NSColor
    let separator: NSColor
    let stroke: NSColor
    let primaryText: NSColor
    let secondaryText: NSColor
    let mutedText: NSColor
    let disabledText: NSColor
    let accent: NSColor
    let shadow: NSColor

    static let dark = AppTheme(
        isDark: true,
        panelBackground: NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.025, alpha: 0.98),
        contentBackground: NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1),
        toolbarBackground: NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.065, alpha: 1),
        rowBackground: NSColor.white.withAlphaComponent(0.045),
        separator: NSColor.white.withAlphaComponent(0.045),
        stroke: NSColor.white.withAlphaComponent(0.09),
        primaryText: NSColor(white: 0.92, alpha: 1),
        secondaryText: NSColor(white: 0.72, alpha: 1),
        mutedText: NSColor(white: 0.58, alpha: 1),
        disabledText: NSColor(white: 0.38, alpha: 1),
        accent: .systemBlue,
        shadow: NSColor.black.withAlphaComponent(0.45)
    )

    static let light = AppTheme(
        isDark: false,
        panelBackground: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.94, alpha: 0.98),
        contentBackground: NSColor(calibratedRed: 0.995, green: 0.995, blue: 0.985, alpha: 1),
        toolbarBackground: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.91, alpha: 1),
        rowBackground: NSColor.black.withAlphaComponent(0.045),
        separator: NSColor.black.withAlphaComponent(0.08),
        stroke: NSColor.black.withAlphaComponent(0.10),
        primaryText: NSColor(white: 0.13, alpha: 1),
        secondaryText: NSColor(white: 0.28, alpha: 1),
        mutedText: NSColor(white: 0.45, alpha: 1),
        disabledText: NSColor(white: 0.62, alpha: 1),
        accent: .systemBlue,
        shadow: NSColor.black.withAlphaComponent(0.20)
    )

    static func resolve(mode: AppearanceMode, colorScheme: ColorScheme) -> AppTheme {
        switch mode {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return colorScheme == .dark ? .dark : .light
        }
    }

    func color(_ nsColor: NSColor) -> Color {
        Color(nsColor: nsColor)
    }

    func textColor(opacity: CGFloat) -> Color {
        color(primaryText.withAlphaComponent(opacity))
    }

    func surfaceColor(opacity: CGFloat) -> Color {
        color((isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity))
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
