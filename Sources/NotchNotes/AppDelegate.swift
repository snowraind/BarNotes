import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var statusButtonTrackingArea: NSTrackingArea?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = NotchPanelController()
        buildStatusItem()
        panelController?.setStatusItemFrameProvider { [weak self] in
            self?.statusButtonFrame()
        }
        panelController?.showDocked()
        buildMenu()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "NotchNotes")
        item.button?.imagePosition = .imageOnly
        item.menu = makeAppMenu()
        statusItem = item
        installStatusButtonTrackingArea()
    }

    private func installStatusButtonTrackingArea() {
        guard let button = statusItem?.button else { return }
        if let statusButtonTrackingArea {
            button.removeTrackingArea(statusButtonTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        statusButtonTrackingArea = trackingArea
    }

    private func statusButtonFrame() -> NSRect? {
        guard let button = statusItem?.button, let window = button.window else { return nil }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonFrameInWindow)
    }

    private func buildMenu() {
        let rootItem = NSMenuItem()
        rootItem.submenu = makeAppMenu()

        let editItem = NSMenuItem()
        editItem.submenu = makeEditMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(rootItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let appMenu = NSMenu()
        let showItem = NSMenuItem(title: "Show Notes", action: #selector(showNotes), keyEquivalent: "n")
        showItem.target = self
        appMenu.addItem(showItem)

        let hideItem = NSMenuItem(title: "Hide Notes", action: #selector(hideNotes), keyEquivalent: "w")
        hideItem.target = self
        appMenu.addItem(hideItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit NotchNotes", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        return appMenu
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        editMenu.addItem(pasteItem)

        editMenu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
        editMenu.addItem(selectAllItem)

        editMenu.addItem(.separator())

        let biggerTextItem = NSMenuItem(title: "Bigger Text", action: #selector(increaseEditorFontSize), keyEquivalent: "=")
        biggerTextItem.target = self
        editMenu.addItem(biggerTextItem)

        let smallerTextItem = NSMenuItem(title: "Smaller Text", action: #selector(decreaseEditorFontSize), keyEquivalent: "-")
        smallerTextItem.target = self
        editMenu.addItem(smallerTextItem)

        return editMenu
    }

    @objc private func showNotes() {
        panelController?.expand(animated: true)
    }

    @objc private func hideNotes() {
        panelController?.collapse(animated: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func increaseEditorFontSize() {
        panelController?.increaseEditorFontSize()
    }

    @objc private func decreaseEditorFontSize() {
        panelController?.decreaseEditorFontSize()
    }

    func mouseEntered(with event: NSEvent) {
        panelController?.expand(animated: true)
    }
}
