import AppKit
import MarkdownEngine
import SwiftUI

@MainActor
final class DrawerState: ObservableObject {
    @Published var isExpanded = false
    @Published var revealProgress: CGFloat = 0
}

private enum NotebookMode: Equatable {
    case editor
    case archiveList
    case archiveDetail(UUID)
}

struct NotebookView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    let layout: NotchLayout
    let onOpenSettings: () -> Void
    @State private var mode: NotebookMode = .editor
    @State private var pendingDeleteArchive: ArchivedNote?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            drawer
        }
        .environment(\.appTheme, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .alert("Delete archived note?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                guard let pendingDeleteArchive else { return }
                if mode == .archiveDetail(pendingDeleteArchive.id) {
                    mode = .archiveList
                }
                store.deleteArchivedNote(pendingDeleteArchive.id)
                self.pendingDeleteArchive = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteArchive = nil
            }
        } message: {
            Text(pendingDeleteArchive?.title ?? "This archived note will be deleted.")
        }
    }

    private var drawer: some View {
        expandedContent
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .background(theme.color(theme.panelBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.color(theme.stroke), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .allowsHitTesting(drawerState.isExpanded)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            header
                .frame(height: toolbarHeight, alignment: .center)

            content
                .frame(width: contentSize.width, height: contentSize.height)
                .background(theme.color(theme.contentBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.top, toolbarTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .onAppear {
            editorInteractionState.onSelectionChange = { [weak store] range in
                guard let store else { return }
                store.updateSelection(for: store.activeTabID, range: range)
            }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
        }
        .onChange(of: store.activeTabID) { _, newTabID in
            if case .editor = mode {
                editorInteractionState.restoreSelection(store.selectionRange(for: newTabID))
                editorInteractionState.requestLayoutRefresh(resetScroll: false)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            switch mode {
            case .editor:
                TabPagerControl(store: store, editorInteractionState: editorInteractionState)

                Spacer()

                Button(action: archiveActiveTab) {
                    Image(systemName: "archivebox")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Archive current note")

                Button {
                    mode = .archiveList
                } label: {
                    Image(systemName: "tray.full")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Archived notes")

            case .archiveList:
                HeaderTitle(systemImage: "tray.full", title: "Archive")

                Spacer()

                Button {
                    mode = .editor
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Back to editor")

            case .archiveDetail:
                Button {
                    mode = .archiveList
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Back to archive")

                HeaderTitle(systemImage: "doc.text", title: selectedArchive?.title ?? "Archive")

                Spacer()
            }

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(DarkIconButtonStyle())
            .help("Settings")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .editor:
            MarkdownEditorPanel(
                store: store,
                settingsStore: settingsStore,
                imageStore: imageStore,
                editorInteractionState: editorInteractionState,
                size: contentSize
            )

        case .archiveList:
            ArchiveListView(
                store: store,
                onOpen: { mode = .archiveDetail($0) },
                onDelete: { pendingDeleteArchive = $0 }
            )

        case .archiveDetail(let id):
            if let archivedNote = store.archivedNotes.first(where: { $0.id == id }) {
                ArchiveDetailView(
                    note: archivedNote,
                    onRestore: {
                        store.restoreArchivedNote(id)
                        mode = .editor
                        editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
                        editorInteractionState.requestLayoutRefresh(resetScroll: true)
                    },
                    onDelete: {
                        pendingDeleteArchive = archivedNote
                    }
                )
            } else {
                ArchiveMissingView {
                    mode = .archiveList
                }
            }
        }
    }

    private var contentSize: CGSize {
        CGSize(
            width: layout.expandedSize.width - contentHorizontalPadding * 2,
            height: layout.expandedSize.height - toolbarTopPadding - contentBottomPadding - toolbarHeight - editorSpacing
        )
    }

    private var toolbarTopPadding: CGFloat {
        16
    }

    private var contentHorizontalPadding: CGFloat {
        18
    }

    private var contentBottomPadding: CGFloat {
        18
    }

    private var toolbarHeight: CGFloat {
        32
    }

    private var editorSpacing: CGFloat {
        12
    }

    private var selectedArchive: ArchivedNote? {
        guard case .archiveDetail(let id) = mode else { return nil }
        return store.archivedNotes.first { $0.id == id }
    }

    private var theme: AppTheme {
        AppTheme.resolve(mode: settingsStore.appearanceMode, colorScheme: colorScheme)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteArchive != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteArchive = nil
                }
            }
        )
    }

    private func archiveActiveTab() {
        _ = store.archiveActiveTab()
        mode = .editor
        editorInteractionState.resetSelectionToDocumentStart()
        editorInteractionState.requestLayoutRefresh(resetScroll: true)
    }
}

private struct HeaderTitle: View {
    let systemImage: String
    let title: String
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(theme.textColor(opacity: 0.88))
    }
}

private struct ArchiveListView: View {
    @ObservedObject var store: NoteStore
    let onOpen: (UUID) -> Void
    let onDelete: (ArchivedNote) -> Void

    var body: some View {
        Group {
            if store.archivedNotes.isEmpty {
                ArchiveEmptyView()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.archivedNotes) { note in
                            ArchiveRow(
                                note: note,
                                title: titleBinding(for: note),
                                onOpen: { onOpen(note.id) },
                                onDelete: { onDelete(note) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func titleBinding(for note: ArchivedNote) -> Binding<String> {
        Binding(
            get: {
                store.archivedNotes.first(where: { $0.id == note.id })?.title ?? note.title
            },
            set: {
                store.renameArchivedNote(note.id, title: $0)
            }
        )
    }
}

private struct ArchiveRow: View {
    let note: ArchivedNote
    @Binding var title: String
    let onOpen: () -> Void
    let onDelete: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                TextField("Untitled Note", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textColor(opacity: 0.90))

                Text(note.archivedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.color(theme.mutedText))
            }

            Spacer(minLength: 8)

            Button(action: onOpen) {
                Image(systemName: "doc.text.magnifyingglass")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(DarkIconButtonStyle())
            .help("Open archived note")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(DarkIconButtonStyle())
            .help("Delete archived note")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.color(theme.rowBackground))
        )
    }
}

private struct ArchiveDetailView: View {
    let note: ArchivedNote
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textColor(opacity: 0.90))
                        .lineLimit(1)

                    Text("Archived \(note.archivedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.color(theme.mutedText))
                }

                Spacer()

                Button(action: onRestore) {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Restore from archive")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(DarkIconButtonStyle())
                .help("Delete archived note")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Rectangle()
                .fill(theme.color(theme.separator))
                .frame(height: 1)

            ScrollView {
                Text(note.text.isEmpty ? "Empty note" : note.text)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(note.text.isEmpty ? theme.color(theme.disabledText) : theme.textColor(opacity: 0.88))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ArchiveEmptyView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.color(theme.disabledText))

            Text("No archived notes")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.color(theme.secondaryText))

            Text("Archive a note to keep it here with its date.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.color(theme.mutedText))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ArchiveMissingView: View {
    let onBack: () -> Void
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Text("Archived note not found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.color(theme.secondaryText))

            Button("Back to Archive", action: onBack)
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MarkdownEditorPanel: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    let size: CGSize
    @Environment(\.appTheme) private var theme

    private let toolbarHeight: CGFloat = 36
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            MarkdownNoteEditor(
                store: store,
                settingsStore: settingsStore,
                imageStore: imageStore,
                editorInteractionState: editorInteractionState
            )
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(theme.color(theme.separator))
                .frame(width: size.width, height: separatorHeight)

            MarkdownShortcutToolbar(editorInteractionState: editorInteractionState)
                .frame(width: size.width, height: toolbarHeight)
                .background(theme.color(theme.toolbarBackground))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - toolbarHeight - separatorHeight, 120)
    }
}

struct MarkdownShortcutToolbar: View {
    let editorInteractionState: EditorInteractionState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MarkdownCommand.allCases) { command in
                Button {
                    editorInteractionState.applyMarkdownCommand(command)
                } label: {
                    MarkdownCommandLabel(command: command)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help(command.help)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }
}

struct MarkdownCommandLabel: View {
    let command: MarkdownCommand

    var body: some View {
        switch command {
        case .bold:
            Image(systemName: "bold")
                .font(.system(size: 13, weight: .semibold))
        case .italic:
            Image(systemName: "italic")
                .font(.system(size: 13, weight: .semibold))
        case .strikethrough:
            Image(systemName: "strikethrough")
                .font(.system(size: 13, weight: .semibold))
        case .inlineCode:
            Text("`")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
        case .link:
            Image(systemName: "link")
                .font(.system(size: 13, weight: .semibold))
        case .quote:
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .semibold))
        case .unorderedList:
            Image(systemName: "list.bullet")
                .font(.system(size: 13, weight: .semibold))
        case .orderedList:
            Image(systemName: "list.number")
                .font(.system(size: 13, weight: .semibold))
        case .todoList:
            Image(systemName: "checklist")
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

struct TabPagerControl: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @Namespace private var tabAnimation
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.removeActiveTab()
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .disabled(store.tabs.count <= 1)
            .help("Remove current tab")

            HStack(spacing: 6) {
                ForEach(store.tabs) { tab in
                    let isSelected = tab.id == store.activeTabID
                    Button {
                        rememberCurrentSelection()
                        withAnimation(tabSwitchAnimation) {
                            store.selectTab(tab.id)
                        }
                    } label: {
                        Capsule()
                            .fill(isSelected ? theme.textColor(opacity: 0.82) : theme.textColor(opacity: 0.34))
                            .frame(width: isSelected ? 20 : 6, height: 6)
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                            .matchedGeometryEffect(id: tab.id, in: tabAnimation)
                            .animation(tabSwitchAnimation, value: isSelected)
                    }
                    .buttonStyle(TabDotButtonStyle(isSelected: isSelected))
                    .help("Switch tab")
                }
            }
            .frame(minWidth: 20, alignment: .center)
            .frame(height: 28, alignment: .center)

            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.addTab()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .help("New tab")
        }
        .frame(height: 28, alignment: .center)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.color(theme.rowBackground))
        )
    }

    private var tabSwitchAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.82)
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct MarkdownNoteEditor: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    let editorInteractionState: EditorInteractionState
    @State private var isWikiLinkActive = false
    @State private var pendingInlineReplacement: InlineReplacementRequest?
    @Environment(\.appTheme) private var theme

    var body: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ),
            isWikiLinkActive: $isWikiLinkActive,
            pendingInlineReplacement: $pendingInlineReplacement,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: CGFloat(settingsStore.editorFontSize),
            documentId: store.activeTabID.uuidString,
            isEditable: true,
            onPasteImage: savePastedImage
        )
        .background {
            EditorFocusBinder(state: editorInteractionState)
        }
    }

    private func savePastedImage(_ pasteboard: NSPasteboard) -> String? {
        imageStore.saveImage(from: pasteboard)
    }

    private var configuration: MarkdownEditorConfiguration {
        let theme = MarkdownEditorTheme(
            bodyText: self.theme.primaryText,
            mutedText: self.theme.mutedText,
            disabledText: self.theme.disabledText,
            headingMarker: self.theme.mutedText,
            link: self.theme.accent,
            incompleteLink: self.theme.accent.withAlphaComponent(0.75),
            findMatchHighlight: NSColor.systemYellow.withAlphaComponent(0.55),
            findCurrentMatchHighlight: NSColor.systemYellow,
            latexLightModeText: self.theme.primaryText,
            latexDarkModeText: self.theme.primaryText,
            strikethroughColor: self.theme.mutedText
        )

        let services = MarkdownEditorServices(images: imageStore)

        return MarkdownEditorConfiguration(
            theme: theme,
            services: services,
            lists: ListStyle(indentPerLevel: 18, extraLineHeight: 1),
            imageEmbed: ImageEmbedStyle(fallbackMaxWidth: 440, paragraphSpacing: 6, imageGap: 6),
            overscroll: OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0),
            dragSelection: DragSelectionPolicy(movementThreshold: 8, edgeTriggerDistance: 8, scrollStepPerTick: 4, ticksPerSecond: 30),
            scrollers: .vertical,
            textInsets: TextInsets(horizontal: 12, vertical: 12)
        )
    }
}

struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct DarkIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0.055,
            hoverOpacity: 0.085,
            pressedOpacity: 0.12,
            strokeOpacity: 0.06,
            foregroundOpacity: 0.76,
            pressedForegroundOpacity: 0.55
        )
    }
}

struct TabIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .bold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.48
        )
    }
}

struct TabDotButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: isSelected ? 0.045 : 0,
            hoverOpacity: isSelected ? 0.075 : 0.055,
            pressedOpacity: isSelected ? 0.10 : 0.08,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.58
        )
    }
}

struct MarkdownToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.66,
            hoverForegroundOpacity: 0.84,
            pressedForegroundOpacity: 0.54
        )
    }
}

private struct RoundedHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font?
    let normalOpacity: CGFloat
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat
    let strokeOpacity: CGFloat
    let foregroundOpacity: CGFloat
    let hoverForegroundOpacity: CGFloat
    let pressedForegroundOpacity: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    init(
        configuration: ButtonStyle.Configuration,
        font: Font?,
        normalOpacity: CGFloat,
        hoverOpacity: CGFloat,
        pressedOpacity: CGFloat,
        strokeOpacity: CGFloat,
        foregroundOpacity: CGFloat,
        hoverForegroundOpacity: CGFloat? = nil,
        pressedForegroundOpacity: CGFloat
    ) {
        self.configuration = configuration
        self.font = font
        self.normalOpacity = normalOpacity
        self.hoverOpacity = hoverOpacity
        self.pressedOpacity = pressedOpacity
        self.strokeOpacity = strokeOpacity
        self.foregroundOpacity = foregroundOpacity
        self.hoverForegroundOpacity = hoverForegroundOpacity ?? foregroundOpacity
        self.pressedForegroundOpacity = pressedForegroundOpacity
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(theme.textColor(opacity: currentForegroundOpacity))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.surfaceColor(opacity: currentBackgroundOpacity))
            )
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .pointingHandCursor(isEnabled: isEnabled)
    }

    private var currentBackgroundOpacity: CGFloat {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return pressedOpacity
        }
        return isHovering ? hoverOpacity : normalOpacity
    }

    private var currentForegroundOpacity: CGFloat {
        guard isEnabled else { return 0.22 }
        if configuration.isPressed {
            return pressedForegroundOpacity
        }
        return isHovering ? hoverForegroundOpacity : foregroundOpacity
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled, !isCursorActive {
                    NSCursor.pointingHand.push()
                    isCursorActive = true
                } else if (!hovering || !isEnabled), isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onDisappear {
                if isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
    }
}
