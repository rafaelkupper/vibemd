# VibeMD

You guessed it. This is entirely vibe-coded. I didn't look at a single line of code. I just wanted a small light `.md` viewer, but apparently it doesn't exist or I'm really bad at looking for things on the internet. 

VibeMD uses a small AppKit document shell with a WebKit-based reader surface for fast, read-only markdown viewing.

## Build

Build a local unsigned app bundle:

```sh
scripts/build-app.sh release
open build/VibeMD.app
```

For local installation, copy `build/VibeMD.app` into `~/Applications` or `/Applications`.
Because this open-source path is unsigned, macOS may require the usual manual approval steps.

## Release Confidence Checks

Before treating a local build as release-ready, run:

```sh
swift test
scripts/build-app.sh release
test -d build/VibeMD.app
test -f build/VibeMD.app/Contents/Resources/VibeMD_VibeMDCore.bundle/reader-theme.css
```

Then do a short manual smoke pass:

- open `RenderingShowcase.md`
- confirm the titlebar blends into the reader background and the stats pill appears after load
- switch the stats pill between words, minutes, lines, and characters and confirm the choice persists
- confirm the local preview image renders
- open the local markdown link and verify it reuses an existing window for the same file, otherwise cascades a new window
- open the external link and verify it hands off to the default browser
- scroll, close the file, reopen it, and verify the reading position restores

## Behavior

- Finder-open markdown documents via `.md`, `.markdown`, `.mdown`, and `.mkd`
- Read-only multi-window AppKit document UI
- Dark WebKit reader styling with local CSS resources
- Unified dark titlebar chrome with a trailing document-stats pill
- Off-main-thread parsing
- External links open in the default browser
- Local markdown links reuse open windows by file identity and cascade new windows when needed
- Local images load through a custom local asset scheme in WebKit
- Scroll position is remembered per file fingerprint
