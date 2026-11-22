<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="SwiftPress">
</p>

<p align="center">
  <a href="https://www.swift.org/"><img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15%2B-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS 15+"></a>
  <a href="https://github.com/whynbnb/SwiftPress/blob/main/LICENSE"><img src="https://img.shields.io/github/license/whynbnb/SwiftPress?style=flat-square" alt="License"></a>
  <a href="https://github.com/whynbnb/SwiftPress/commits/main"><img src="https://img.shields.io/github/last-commit/whynbnb/SwiftPress?style=flat-square" alt="Last commit"></a>
</p>

# SwiftPress

> Vibe Coded with DeepSeek V4.1 Flash / OpenCode

A simple macOS DMG installer maker built with SwiftUI.

[中文说明](README.zh.md)

![English Preview](docs/preview-en.png)

## Features

### DMG creation
- Drag & drop (or browse) a `.app` file to create a DMG installer
- Automatically creates an `/Applications` symlink inside the DMG
- Auto-reads the app version from `Info.plist` and includes it in the DMG filename
- Adds the build date to the output filename (e.g. `MyApp v2.1.0 20260615.dmg`)
- DMG volume name matches the filename
- Configurable icon size when opening the DMG — presets (64 / 96 / 128 / 160), a custom size, or “No setting” to use the Finder default; remembered across launches
- Configurable Finder window size — presets (480×320 / 640×400 / 800×500 / 1000×620), a custom size, or “No setting” to use the Finder default; remembered across launches
- Clean installer layout: toolbar, sidebar, path bar and status bar are hidden, and the app/Applications icons are laid out automatically
- Packaging runs off the main thread and can be cancelled mid-way

> The layout is written directly into the image, so no Finder window opens during packaging and no automation permission is needed.

### Watch folders
- Add multiple watched folders; each can be enabled/disabled individually
- Per-folder content filter (file extension, default `.app`)
- Per-folder scan depth: top level / one level of subfolders / fully recursive
- Real-time updates via FSEvents — new files appear immediately and deletions are reflected
- Newly found items are flagged with a `NEW` badge; click an item to select it for packaging
- Large folders are scanned in the background with progressive results

### Appearance & language
- Language switch (System / English / 中文)
- Appearance switch (System / Light / Dark)
- Preferences are persisted across launches

## Command line

```bash
# Default output name (next to the app, version + date)
SwiftPress --app /path/MyApp.app

# Custom output path
SwiftPress --app /path/MyApp.app --output /path/MyApp.dmg
SwiftPress --app=/path/MyApp.app -o /path/MyApp.dmg

# Help
SwiftPress --help
```

Options:

- `--app <path>` — the `.app` to package (required)
- `--output, -o <path>` — output DMG path (optional)
- `-h, --help` — show help

The CLI applies the icon size and window size saved in the app's Advanced Settings.

Without `--output`, the DMG is written next to the app. If that folder isn't writable, it falls back to Downloads, and an existing name gets a numeric suffix (` 2`, ` 3`, …).

## How it works

The DMG layout is written directly into the image, without talking to Finder at packaging time.

- A pre-generated `.DS_Store` template is bundled with the app. It hides the toolbar, sidebar, path bar and status bar, selects icon view, and arranges icons by name.
- While packaging, the template is copied into the staging folder and patched in place:
  - **Window size** — the `WindowBounds` string in the `bwsp` record is replaced with an equally long, space-padded string. `WindowBounds` uses a bottom-left origin, so the position is converted from the top of the screen (120 pt margin).
  - **Icon size** — the `iconSize` value in the `icvp` record is replaced with the selected size.
- `hdiutil create -srcfolder … -format UDZO` then builds the final image.
- Choosing **No setting** leaves that dimension to Finder: the `WindowBounds` key is renamed so Finder uses its default window size, and the icon size falls back to Finder's default (48).

Because the `.DS_Store` is written before `hdiutil` runs, no image is mounted and no Finder window or automation permission is involved.

## Requirements

- macOS 15.0+
- Xcode 16.0+ (Swift 6)

## Build

### Xcode

Open `SwiftPress.xcodeproj` and build.

### SPM

```bash
swift build
swift run
```

## License

MIT
