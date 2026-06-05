import Foundation

enum DefaultsMigration {
    private static let migrationFlagKey = "barNotes.didMigrateNotchNotesDefaults.v1"
    private static let oldBundleID = "io.github.oiloil.NotchNotes"
    private static let migratedKeys = [
        "notchNotes.text",
        "notchNotes.tabs.v1",
        "notchNotes.activeTabID",
        "notchNotes.archivedNotes.v1",
        "notchNotes.triggerMode",
        "notchNotes.appearanceMode",
        "notchNotes.editorFontSize",
        "notchNotes.panelHeight"
    ]

    static func migrateIfNeeded() {
        let destination = UserDefaults.standard
        guard !destination.bool(forKey: migrationFlagKey) else { return }
        guard let source = UserDefaults(suiteName: oldBundleID) else {
            destination.set(true, forKey: migrationFlagKey)
            return
        }

        for key in migratedKeys where destination.object(forKey: key) == nil {
            if let value = source.object(forKey: key) {
                destination.set(value, forKey: key)
            }
        }

        destination.set(true, forKey: migrationFlagKey)
    }
}
