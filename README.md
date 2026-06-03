# BarNotes

BarNotes is a small native macOS note app that lives in the menu bar. Hover over the menu bar icon to open a compact Markdown notebook for quick tasks, links, screenshots, and tiny reminders.

BarNotes is forked from / based on [oil-oil/NotchNotes](https://github.com/oil-oil/NotchNotes), with modifications by [snowraind](https://github.com/snowraind). The original app focused on a note panel that unfolded from the MacBook notch. This fork changes the interaction model into a menu bar notebook, which works better on Macs without a notch and keeps the app anchored in the top-right system area.

## Download

- [Download the latest release](https://github.com/snowraind/BarNotes/releases/latest)
- [Open the homepage](https://snowraind.github.io/BarNotes/)

After downloading, unzip the app, move it to Applications, then right-click and choose Open on the first launch.

## Features

- Menu bar notebook that opens on hover by default.
- Optional click trigger that opens the notebook from the menu bar icon.
- Live Markdown editing with formatting shortcuts.
- Multiple note tabs for quick context switching.
- Archive notes with editable titles and restore them later.
- Paste images directly into notes.
- Dark, light, and automatic appearance modes.
- Keyboard shortcuts for editor font size.

## Changes From The Original

- Replaced the notch-centered hot zone with a menu bar icon trigger.
- Removed the always-visible notch mask for non-notch Macs.
- Added note archiving, restore, and delete flows.
- Added dark, light, and automatic appearance modes.
- Added editor font size shortcuts.

## Stack
- Swift + AppKit for the menu bar item, floating panel, window levels, and cursor-triggered behavior.
- SwiftUI for the notebook interface.
- UserDefaults for lightweight local note storage.
- MarkdownEngine for live Markdown editing and embedded images.

## Run

```bash
swift run BarNotes
```

After launch, move the cursor over the BarNotes menu bar icon. The notebook panel opens from the top-right corner.

## Package

```bash
./Scripts/package-app.sh
open BarNotes.app
```

## Distribution

The current downloadable ZIP is intended for testing. For public distribution outside the Mac App Store, sign the app with a Developer ID Application certificate and submit it for Apple notarization.
