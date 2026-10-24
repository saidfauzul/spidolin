# Spidolin

**Draw on your screen on macOS.** A native Swift/AppKit screen annotation tool
inspired by [Gromit-MPX](https://github.com/bk138/gromit-mpx).

🇮🇩 Baca dalam Bahasa Indonesia: [BACASAYA.md](BACASAYA.md)

Spidolin lives in the menu bar and lets you draw over anything on screen (slides,
code, videos, full-screen apps) during presentations, screen sharing or recordings.
It is a rewrite in Swift/AppKit rather than a port, because Gromit-MPX relies on
X11/XInput (global key grabs, multi-pointer), which macOS doesn't have.

## Features

- Draw over every display, every Space and full-screen apps
- Tools: pen, highlighter, arrow, line, rectangle, ellipse, eraser
- 8 colors and adjustable stroke width
- Tablet pen pressure (Wacom etc.) changes the width
- Undo/redo (100 steps), including undoable clear
- Hide/show the drawing without losing it
- Global hotkeys compatible with Gromit-MPX (F9, F8, …)
- Never steals keyboard focus from the app you are presenting
- Command-line control (`--toggle`, `--clear`, …) like `gromit-mpx`
- Launch at login
- No Accessibility permission needed

## Download

Get `Spidolin-<version>.zip` from the
[Releases page](https://github.com/saidfauzul/spidolin/releases/latest), unzip it and
drag `Spidolin.app` into `/Applications` (or `~/Applications`). It is a universal app
for macOS 13 or later on Apple Silicon and Intel Macs.

Spidolin is ad-hoc signed, not notarized by Apple, so macOS blocks it the first time
you open it. To allow it, do one of these once:

- Right-click `Spidolin.app` and choose Open, then Open again; or
- Try to open it, then go to System Settings > Privacy & Security and click
  "Open Anyway" (on macOS 15 and later this is the only way through Finder); or
- In the Terminal, remove the quarantine flag:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Spidolin.app
  ```

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools, only to build from source (`xcode-select --install`)

## Build from source

```bash
git clone https://github.com/saidfauzul/spidolin.git
cd spidolin
./build.sh
open build/Spidolin.app
```

A pencil icon appears in the menu bar.

To install into `~/Applications` (recommended, and a stable location for
"Launch at login"):

```bash
bash build.sh install
open ~/Applications/Spidolin.app
```

`bash build.sh release` builds a universal app and zips it for a release.

## Usage

### Global hotkeys

| Key | Action | Gromit-MPX equivalent |
|---|---|---|
| F9 or ⌃⌥D | Start/stop drawing | F9 |
| ⇧F9 or ⌃⌥C | Clear screen (undoable) | Shift-F9 |
| ⌃F9 or ⌃⌥H | Hide/show drawing | Ctrl-F9 |
| ⌥F9 | Quit | Alt-F9 |
| F8 or ⌃⌥Z | Undo | F8 |
| ⇧F8 or ⌃⌥⇧Z | Redo | Shift-F8 |

On a MacBook, F8/F9 are media keys, so press Fn+F9 or use ⌃⌥D.

### While drawing

These keys are only captured while drawing mode is on:

- `P` pen, `M` highlighter, `A` arrow, `L` line, `R` rectangle, `O` ellipse, `E` eraser
- `1`–`8` color (red, blue, green, yellow, orange, purple, white, black)
- `[` / `]` width, `⌘Z` / `⌘⇧Z` undo/redo, `Delete` clear, `Esc` finish
- Right-click + drag = eraser (like Button3 in Gromit-MPX)
- Hold Shift when you start dragging = straight line with the current tool

Everything is also available from the pencil icon menu.

## Command line

Like `gromit-mpx --toggle`, a running instance can be controlled from the Terminal:

```bash
~/Applications/Spidolin.app/Contents/MacOS/Spidolin --toggle   # -t
```

| Option | Action |
|---|---|
| `--toggle`, `-t` | Start/stop drawing |
| `--clear`, `-c` | Clear screen |
| `--undo`, `-z` | Undo |
| `--redo`, `-y` | Redo |
| `--visibility`, `-v` | Hide/show drawing |
| `--quit`, `-q` | Quit |

## Launch at login

Turn it on or off from the pencil icon menu > "Launch at login". If macOS asks for
approval, System Settings > General > Login Items opens; you can change the same
setting there too.

## Architecture

- `Sources/Overlay.swift`: one transparent, borderless `NSPanel` per screen at screen
  saver level, present on every Space and over full-screen apps. The panel never
  activates the app, so keyboard focus stays in the app being presented.
  When drawing mode is off, the panel passes clicks through (`ignoresMouseEvents`).
- `Sources/Ink.swift`: vector document (global screen coordinates, so one stroke can
  span several displays), snapshot-based undo/redo, Core Graphics renderer.
  Finished strokes are cached as a bitmap; only the stroke in progress is redrawn
  on each mouse move.
- `Sources/HotKeys.swift`: global hotkeys via Carbon `RegisterEventHotKey`.
- `Sources/AppController.swift`: menu bar status item, tool/color/width selection, commands.
- `Sources/main.swift`: entry point and command-line commands (via distributed notification).

## Roadmap

Not yet implemented compared with Gromit-MPX:

- A tool configuration file (custom tools, colors and hotkeys)
- The SMOOTH and ORTHOGONAL tools
- Opacity settings
- Multi-pointer (MPX has no macOS equivalent, so this is unlikely)

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright © 2026 Said Fauzul. Spidolin is free software under the GNU GPL v2 or
later (see [LICENSE](LICENSE)). It is an independent Swift rewrite inspired by
Gromit-MPX by Christian Beier and contributors; it contains no Gromit-MPX code.
