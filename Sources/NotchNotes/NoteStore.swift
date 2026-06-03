import Combine
import Foundation

struct NoteTab: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var selectionLocation: Int?
    var selectionLength: Int?

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        selectionLocation = 0
        selectionLength = 0
    }
}

struct ArchivedNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var text: String
    var createdAt: Date
    var archivedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        text: String,
        createdAt: Date = Date(),
        archivedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var tabs: [NoteTab]
    @Published private(set) var activeTabID: UUID
    @Published private(set) var archivedNotes: [ArchivedNote]

    private static let legacyTextKey = "notchNotes.text"
    private static let tabsKey = "notchNotes.tabs.v1"
    private static let activeTabIDKey = "notchNotes.activeTabID"
    private static let archivedNotesKey = "notchNotes.archivedNotes.v1"

    init() {
        let storedTabs = Self.loadStoredTabs()
        let initialTabs: [NoteTab]

        if storedTabs.isEmpty {
            let legacyText = UserDefaults.standard.string(forKey: Self.legacyTextKey) ?? ""
            initialTabs = [NoteTab(text: legacyText)]
        } else {
            initialTabs = storedTabs
        }

        tabs = initialTabs
        archivedNotes = Self.loadArchivedNotes()

        let activeIDString = UserDefaults.standard.string(forKey: Self.activeTabIDKey)
        let storedActiveID = activeIDString.flatMap(UUID.init(uuidString:))
        activeTabID = storedActiveID.flatMap { activeID in
            initialTabs.contains(where: { $0.id == activeID }) ? activeID : nil
        } ?? initialTabs[0].id

        save()
    }

    var activeTab: NoteTab {
        tabs[activeIndex]
    }

    var text: String {
        tabs[activeIndex].text
    }

    func updateText(_ nextText: String) {
        tabs[activeIndex].text = nextText
        clampSelection(for: tabs[activeIndex].id)
        save()
    }

    func clear() {
        updateText("")
        updateSelection(for: activeTabID, range: NSRange(location: 0, length: 0))
    }

    func archiveActiveTab() -> ArchivedNote {
        let tab = activeTab
        let archive = ArchivedNote(
            title: Self.archiveTitle(for: tab.text),
            text: tab.text,
            createdAt: tab.createdAt,
            archivedAt: Date()
        )
        archivedNotes.insert(archive, at: 0)
        tabs[activeIndex] = NoteTab()
        activeTabID = tabs[activeIndex].id
        save()
        return archive
    }

    func renameArchivedNote(_ id: UUID, title: String) {
        guard let index = archivedNotes.firstIndex(where: { $0.id == id }) else { return }
        let nextTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        archivedNotes[index].title = nextTitle.isEmpty ? "Untitled Note" : nextTitle
        save()
    }

    func deleteArchivedNote(_ id: UUID) {
        archivedNotes.removeAll { $0.id == id }
        save()
    }

    func restoreArchivedNote(_ id: UUID) {
        guard let index = archivedNotes.firstIndex(where: { $0.id == id }) else { return }
        let archivedNote = archivedNotes.remove(at: index)
        let tab = NoteTab(text: archivedNote.text, createdAt: archivedNote.createdAt)
        tabs.append(tab)
        activeTabID = tab.id
        save()
    }

    func addTab() {
        let tab = NoteTab()
        tabs.append(tab)
        activeTabID = tab.id
        save()
    }

    func removeActiveTab() {
        guard tabs.count > 1 else { return }
        let removedIndex = activeIndex
        tabs.remove(at: removedIndex)
        let nextIndex = min(removedIndex, tabs.count - 1)
        activeTabID = tabs[nextIndex].id
        save()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        save()
    }

    func updateSelection(for id: UUID, range: NSRange) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
        save()
    }

    func selectionRange(for id: UUID) -> NSRange {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return NSRange(location: 0, length: 0)
        }

        return clampedRange(
            NSRange(location: tab.selectionLocation ?? 0, length: tab.selectionLength ?? 0),
            text: tab.text
        )
    }

    private var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    private func clampSelection(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let range = NSRange(location: tabs[index].selectionLocation ?? 0, length: tabs[index].selectionLength ?? 0)
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
    }

    private func clampedRange(_ range: NSRange, text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: Self.tabsKey)
        }
        if let data = try? JSONEncoder().encode(archivedNotes) {
            UserDefaults.standard.set(data, forKey: Self.archivedNotesKey)
        }
        UserDefaults.standard.set(activeTabID.uuidString, forKey: Self.activeTabIDKey)
        UserDefaults.standard.set(text, forKey: Self.legacyTextKey)
    }

    private static func loadStoredTabs() -> [NoteTab] {
        guard let data = UserDefaults.standard.data(forKey: tabsKey),
              let tabs = try? JSONDecoder().decode([NoteTab].self, from: data) else {
            return []
        }

        return tabs.isEmpty ? [] : tabs
    }

    private static func loadArchivedNotes() -> [ArchivedNote] {
        guard let data = UserDefaults.standard.data(forKey: archivedNotesKey),
              let notes = try? JSONDecoder().decode([ArchivedNote].self, from: data) else {
            return []
        }

        return notes.sorted { $0.archivedAt > $1.archivedAt }
    }

    private static func archiveTitle(for text: String) -> String {
        let firstLine = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return firstLine.isEmpty ? "Untitled Note" : firstLine
    }
}
