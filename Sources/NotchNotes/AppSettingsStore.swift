import Combine
import Foundation

enum TriggerMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover:
            return "Hover"
        case .click:
            return "Click"
        }
    }

    var systemImage: String {
        switch self {
        case .hover:
            return "cursorarrow.motionlines"
        case .click:
            return "cursorarrow.click.2"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        case .system:
            return "Auto"
        }
    }

    var systemImage: String {
        switch self {
        case .dark:
            return "moon"
        case .light:
            return "sun.max"
        case .system:
            return "circle.lefthalf.filled"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let editorFontSizeRange: ClosedRange<Double> = 12...24

    @Published var triggerMode: TriggerMode {
        didSet {
            UserDefaults.standard.set(triggerMode.rawValue, forKey: Self.triggerModeKey)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey)
        }
    }

    @Published private(set) var editorFontSize: Double {
        didSet {
            UserDefaults.standard.set(editorFontSize, forKey: Self.editorFontSizeKey)
        }
    }

    private static let triggerModeKey = "notchNotes.triggerMode"
    private static let appearanceModeKey = "notchNotes.appearanceMode"
    private static let editorFontSizeKey = "notchNotes.editorFontSize"

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.triggerModeKey)
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover

        let rawAppearance = UserDefaults.standard.string(forKey: Self.appearanceModeKey)
        appearanceMode = rawAppearance.flatMap(AppearanceMode.init(rawValue:)) ?? .system

        let storedFontSize = UserDefaults.standard.double(forKey: Self.editorFontSizeKey)
        editorFontSize = storedFontSize == 0 ? 15 : Self.clampedFontSize(storedFontSize)
    }

    func increaseEditorFontSize() {
        editorFontSize = Self.clampedFontSize(editorFontSize + 1)
    }

    func decreaseEditorFontSize() {
        editorFontSize = Self.clampedFontSize(editorFontSize - 1)
    }

    private static func clampedFontSize(_ fontSize: Double) -> Double {
        min(max(fontSize, editorFontSizeRange.lowerBound), editorFontSizeRange.upperBound)
    }
}
