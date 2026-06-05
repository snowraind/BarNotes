import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp {
            onMouseEvent?(event)
        }

        super.sendEvent(event)
    }
}

@MainActor
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class NotchPanelController: NSObject {
    private let store = NoteStore()
    private let settingsStore = AppSettingsStore()
    private let imageStore = LocalImageStore()
    private let drawerState = DrawerState()
    private let editorInteractionState = EditorInteractionState()
    private lazy var settingsPopoverController = SettingsPopoverController(settingsStore: settingsStore)
    private let drawerPanel: NotchPanel
    private var hostingView: NSHostingView<NotebookView>?
    private var mousePollingTimer: Timer?
    private var globalMouseDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var cachedLayout: NotchLayout?
    private var statusItemFrameProvider: (() -> NSRect?)?
    private var isExpanded = false
    private var activeMenuTrackingCount = 0
    private var collapseTask: DispatchWorkItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var livePanelHeight: CGFloat?
    private var resizeStartHeight: CGFloat?
    private var isAnimatingVisibility = false

    override init() {
        drawerPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel(drawerPanel)
        rebuildContent()
        startMousePolling()
        observeScreenChanges()
        observePanelMouseEvents()
        observeGlobalSelectionMouseEvents()
        observeMenuTracking()
        observeAppearanceChanges()
    }

    func setStatusItemFrameProvider(_ provider: @escaping () -> NSRect?) {
        statusItemFrameProvider = provider
    }

    func increaseEditorFontSize() {
        settingsStore.increaseEditorFontSize()
        editorInteractionState.requestLayoutRefresh(searchingIn: hostingView)
    }

    func decreaseEditorFontSize() {
        settingsStore.decreaseEditorFontSize()
        editorInteractionState.requestLayoutRefresh(searchingIn: hostingView)
    }

    func statusItemHovered() {
        guard settingsStore.triggerMode == .hover else { return }
        expand(animated: true)
    }

    func statusItemClicked() {
        expand(animated: true)
    }

    func showDocked() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        isExpanded = false
        drawerState.isExpanded = false
        drawerState.revealProgress = 0
        drawerPanel.alphaValue = 0
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        drawerPanel.orderOut(nil)
    }

    func expand(animated: Bool) {
        guard !isExpanded else { return }
        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        rebuildContent(layout: layout)
        let finalFrame = drawerFrame(for: layout)
        if animated {
            drawerPanel.alphaValue = 0
            drawerPanel.setFrame(slideFrame(from: finalFrame), display: true)
        } else {
            drawerPanel.alphaValue = 1
            drawerPanel.setFrame(finalFrame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        drawerPanel.makeKeyAndOrderFront(nil)
        animatePanelIn(to: finalFrame, animated: animated)
        setDrawerExpanded(true, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            guard self.isExpanded else { return }
            self.editorInteractionState.restoreSelection(
                self.store.selectionRange(for: self.store.activeTabID),
                searchingIn: self.hostingView
            )
            self.editorInteractionState.requestLayoutRefresh(searchingIn: self.hostingView)
            self.editorInteractionState.requestFocus(searchingIn: self.hostingView)
        }
    }

    func collapse(animated: Bool) {
        guard isExpanded else { return }
        if let range = editorInteractionState.currentSelectionRange() {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        settingsPopoverController.close(animated: false)
        isExpanded = false
        setDrawerExpanded(false, animated: animated)
        animatePanelOut(animated: animated)
    }

    private func configurePanel(_ panel: NotchPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func rebuildContent(layout: NotchLayout? = nil) {
        let layout = layout ?? currentLayout()
        cachedLayout = layout
        drawerState.panelHeight = layout.expandedSize.height
        let view = NotebookView(
            store: store,
            settingsStore: settingsStore,
            imageStore: imageStore,
            drawerState: drawerState,
            editorInteractionState: editorInteractionState,
            layout: layout,
            onOpenSettings: { [weak self] in self?.openSettingsPopover() },
            onResizeHeight: { [weak self] delta, commit in
                self?.resizePanelHeight(by: delta, commit: commit)
            }
        )

        if let hostingView {
            hostingView.rootView = view
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        drawerPanel.contentView = host
        hostingView = host
    }

    private func setDrawerExpanded(_ expanded: Bool, animated: Bool) {
        guard animated else {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
            return
        }

        let animation: Animation = expanded
            ? .spring(response: 0.28, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)

        withAnimation(animation) {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
        }
    }

    private func startMousePolling() {
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(mousePollingTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        mousePollingTimer = timer
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observePanelMouseEvents() {
        drawerPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            self.editorInteractionState.handleMouseEvent(event, searchingIn: self.hostingView)
        }
    }

    private func observeGlobalSelectionMouseEvents() {
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseDragged()
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseUp()
            }
        }
    }

    private func observeMenuTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    private func observeAppearanceChanges() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.settingsStore.appearanceMode == .system else { return }
                let layout = self.currentLayout()
                self.rebuildContent(layout: layout)
                self.drawerPanel.setFrame(self.drawerFrame(for: layout), display: true)
                self.editorInteractionState.requestLayoutRefresh(searchingIn: self.hostingView)
            }
        }
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        cancelCollapse()
        rebuildContent(layout: layout)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
    }

    @objc private func mousePollingTick(_ timer: Timer) {
        handleMouseLocation(NSEvent.mouseLocation)
    }

    @objc private func menuTrackingDidBegin(_ notification: Notification) {
        activeMenuTrackingCount += 1
        cancelCollapse()
    }

    @objc private func menuTrackingDidEnd(_ notification: Notification) {
        activeMenuTrackingCount = max(0, activeMenuTrackingCount - 1)
        guard activeMenuTrackingCount == 0, isExpanded else { return }
        handleMouseLocation(NSEvent.mouseLocation)
    }

    private func handleMouseLocation(_ point: NSPoint) {
        if isExpanded {
            if activeMenuTrackingCount > 0 {
                cancelCollapse()
                return
            }

            if editorInteractionState.isDraggingSelection {
                cancelCollapse()
                return
            }

            if isPointInExpandedStayRegion(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if settingsStore.triggerMode == .hover, activationFrame().contains(point) {
            expand(animated: true)
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        guard activeMenuTrackingCount == 0 else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.activeMenuTrackingCount == 0 else { return }
            guard !self.editorInteractionState.isDraggingSelection else { return }
            guard !self.isPointInExpandedStayRegion(NSEvent.mouseLocation) else { return }
            self.collapse(animated: true)
        }

        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: task)
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func activationFrame() -> NSRect {
        statusItemFrameProvider?() ?? .zero
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 10
        return drawerPanel.frame.insetBy(dx: -margin, dy: -margin).contains(point)
            || activationFrame().insetBy(dx: -margin, dy: -margin).contains(point)
            || settingsPopoverController.contains(point)
    }

    private func openSettingsPopover() {
        cancelCollapse()
        settingsPopoverController.show(relativeTo: drawerPanel)
    }

    private func currentLayout() -> NotchLayout {
        let baseLayout = NotchGeometry.layout(for: targetScreen())
        let storedHeight = livePanelHeight
            ?? CGFloat(settingsStore.panelHeight == 0 ? baseLayout.expandedSize.height : settingsStore.panelHeight)
        let height = clampedPanelHeight(
            storedHeight,
            baseLayout: baseLayout
        )
        return NotchLayout(
            notchSize: baseLayout.notchSize,
            compactSize: baseLayout.compactSize,
            expandedSize: NSSize(width: baseLayout.expandedSize.width, height: height),
            compactTopOffset: baseLayout.compactTopOffset,
            expandedTopOffset: baseLayout.expandedTopOffset
        )
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func drawerFrame(for layout: NotchLayout) -> NSRect {
        let anchor = statusItemFrameProvider?()
        let screen = anchor.flatMap { screenContaining($0) } ?? targetScreen()
        let screenFrame = screen?.visibleFrame
            ?? screen?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        let anchorFrame = anchor ?? NSRect(
            x: screenFrame.maxX - 22,
            y: screenFrame.maxY - 22,
            width: 22,
            height: 22
        )
        let x = min(
            max(anchorFrame.maxX - layout.expandedSize.width, screenFrame.minX + 10),
            screenFrame.maxX - layout.expandedSize.width - 10
        )
        let y = min(
            max(anchorFrame.minY - layout.expandedSize.height - gap, screenFrame.minY + 10),
            screenFrame.maxY - layout.expandedSize.height - 10
        )

        return NSRect(origin: NSPoint(x: x, y: y), size: layout.expandedSize)
    }

    private func resizePanelHeight(by delta: CGFloat, commit: Bool) {
        let baseLayout = NotchGeometry.layout(for: targetScreen())
        if resizeStartHeight == nil {
            resizeStartHeight = currentLayout().expandedSize.height
        }
        let startHeight = resizeStartHeight ?? baseLayout.expandedSize.height
        let clampedHeight = clampedPanelHeight(startHeight + delta, baseLayout: baseLayout)
        livePanelHeight = clampedHeight
        cancelCollapse()
        guard commit else { return }

        let layout = currentLayout()
        cachedLayout = layout
        drawerState.panelHeight = layout.expandedSize.height
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        if commit {
            settingsStore.setPanelHeight(Double(clampedHeight))
            livePanelHeight = nil
            resizeStartHeight = nil
            editorInteractionState.requestLayoutRefresh(searchingIn: hostingView)
        }
    }

    private func slideFrame(from finalFrame: NSRect) -> NSRect {
        finalFrame.offsetBy(dx: 0, dy: 10)
    }

    private func animatePanelIn(to finalFrame: NSRect, animated: Bool) {
        guard animated else {
            drawerPanel.alphaValue = 1
            drawerPanel.setFrame(finalFrame, display: true)
            return
        }
        isAnimatingVisibility = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            drawerPanel.animator().alphaValue = 1
            drawerPanel.animator().setFrame(finalFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isAnimatingVisibility = false
            }
        }
    }

    private func animatePanelOut(animated: Bool) {
        let finalFrame = drawerPanel.frame
        let endFrame = slideFrame(from: finalFrame)
        guard animated else {
            let layout = currentLayout()
            drawerPanel.alphaValue = 0
            drawerPanel.orderOut(nil)
            drawerPanel.setFrame(drawerFrame(for: layout), display: false)
            return
        }
        isAnimatingVisibility = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drawerPanel.animator().alphaValue = 0
            drawerPanel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isExpanded else { return }
                let layout = self.currentLayout()
                self.drawerPanel.orderOut(nil)
                self.drawerPanel.alphaValue = 1
                self.drawerPanel.setFrame(self.drawerFrame(for: layout), display: false)
                self.isAnimatingVisibility = false
            }
        }
    }

    private func clampedPanelHeight(_ height: CGFloat, baseLayout: NotchLayout) -> CGFloat {
        let anchor = statusItemFrameProvider?()
        let screen = anchor.flatMap { screenContaining($0) } ?? targetScreen()
        let screenFrame = screen?.visibleFrame
            ?? screen?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8
        let anchorFrame = anchor ?? NSRect(
            x: screenFrame.maxX - 22,
            y: screenFrame.maxY - 22,
            width: 22,
            height: 22
        )
        let maxHeight = max(
            AppSettingsStore.panelHeightRange.lowerBound,
            Double(anchorFrame.minY - gap - screenFrame.minY - 10)
        )
        let upperBound = min(Double(baseLayout.expandedSize.height) + 420, maxHeight)
        return CGFloat(min(max(Double(height), AppSettingsStore.panelHeightRange.lowerBound), upperBound))
    }

    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }
}
