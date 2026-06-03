# NotchNotes

![NotchNotes preview](docs/assets/readme-hero.png)

NotchNotes is a small native macOS note app that lives in the menu bar. Hover over the menu bar icon to open a compact Markdown notebook for quick tasks, links, screenshots, and tiny reminders.

## Download

- [Download the latest release](https://github.com/snowraind/NotchNotes/releases/latest)
- [Open the homepage](https://snowraind.github.io/NotchNotes/)

After downloading, unzip the app, move it to Applications, then right-click and choose Open on the first launch.

## Features

- Menu bar notebook that opens on hover.
- Live Markdown editing with formatting shortcuts.
- Multiple note tabs for quick context switching.
- Archive notes with editable titles and restore them later.
- Paste images directly into notes.
- Dark, light, and automatic appearance modes.
- Keyboard shortcuts for editor font size.

## Stack

- Swift + AppKit for the menu bar item, floating panel, window levels, and cursor-triggered behavior.
- SwiftUI for the notebook interface.
- UserDefaults for lightweight local note storage.
- MarkdownEngine for live Markdown editing and embedded images.

## Run

```bash
swift run NotchNotes
```

After launch, move the cursor over the NotchNotes menu bar icon. The notebook panel opens from the top-right corner.

## Package

```bash
./Scripts/package-app.sh
open NotchNotes.app
```

## Distribution

The current downloadable ZIP is intended for testing. For public distribution outside the Mac App Store, sign the app with a Developer ID Application certificate and submit it for Apple notarization.
