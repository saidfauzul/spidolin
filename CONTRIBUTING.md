# Contributing to Spidolin

Thanks for your interest! Bug reports, ideas and pull requests are welcome.

## Before you start

- For small fixes, just open a pull request.
- For bigger changes (new tools, new dependencies, architectural changes), please
  open an issue first so we can agree on the approach.

## Building

You need macOS 13 or later and the Xcode Command Line Tools
(`xcode-select --install`). No Xcode project is needed:

```bash
./build.sh                 # builds build/Spidolin.app
bash build.sh install      # also copies it to ~/Applications
```

## Code style

- Keep to the style of the surrounding code: Swift/AppKit, no third-party
  dependencies, small focused files under `Sources/`.
- Start every new source file with the copyright and SPDX header used by the
  existing files.
- Keep comments short and explain *why*, not *what*.

## Testing

Test your change on macOS 13 or later before submitting. Please check at least:
drawing on more than one display if you can, full-screen apps, undo/redo, the
global hotkeys, and that keyboard focus stays in the app underneath.

## License

Spidolin is licensed under GPL-2.0-or-later. By submitting a contribution you
agree that it is licensed under the same terms.
