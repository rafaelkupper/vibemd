# VibeMD

You guessed it. This is entirely vibe-coded. I didn't look at a single line of code. I just wanted a small light `.md` viewer, but apparently it doesn't exist or I'm really bad at looking for things on the internet. 

VibeMD uses a small AppKit document shell with a WebKit-based reader surface for fast, read-only markdown viewing. The current app includes unified dark window chrome, document stats in the titlebar, and a left sidebar for linked-document navigation and document outline browsing.

## Build

Build a local unsigned app bundle:

```sh
scripts/build-app.sh release
open build/VibeMD.app
```

For local installation, copy `build/VibeMD.app` into `~/Applications` or `/Applications`.
Because this open-source path is unsigned, macOS may require the usual manual approval steps.

## Release Confidence Checks

Before treating a local `0.2.0` build as release-ready on one Mac, run:

```sh
swift test
scripts/build-app.sh release
test -d build/VibeMD.app
test -f build/VibeMD.app/Contents/Resources/VibeMD_VibeMDCore.bundle/reader-theme.css
```

Then do a short single-machine smoke pass:

- open `RenderingShowcase.md`
- confirm `Cmd-F` opens the native find bar and `Cmd-G` / `Shift-Cmd-G` move between matches in the current document
- confirm the titlebar blends into the reader background and the stats pill appears after load
- switch the stats pill between words, minutes, lines, and characters and confirm the choice persists
- open and close the sidebar and confirm the window frame stays fixed while the reader reflows smoothly
- switch between `Documents` and `Outline` and confirm the sidebar stays visually stable
- in `Documents`, open a linked markdown file and confirm it loads in the current window
- in `Outline`, click a heading and confirm it scrolls to the right section and tracks the active section while reading
- click a same-document anchor and confirm it scrolls in place instead of opening a new window
- click a cross-document anchor and confirm the target file opens at the requested section
- confirm callouts, symbol links, inline attributes, and inline markdown inside table cells render correctly
- confirm the richer fenced-code highlighting renders for showcase languages like `html`, `css`, `toml`, `diff`, and `dockerfile`
- confirm the local preview image renders
- open the local markdown link and verify it reuses an existing window for the same file, otherwise cascades a new window
- use Finder `Open With` / default-app launch on a markdown file and confirm it opens without crashing
- open the external link and verify it hands off to the default browser
- scroll, close the file, reopen it, and verify the reading position restores

## Behavior

- Finder-open markdown documents via `.md`, `.markdown`, `.mdown`, and `.mkd`
- Read-only multi-window AppKit document UI
- Dark WebKit reader styling with local CSS resources
- Unified dark titlebar chrome with a trailing document-stats pill
- Native macOS find for the current document via `Cmd-F`, `Cmd-G`, and `Shift-Cmd-G`
- Titlebar stats pill with app-wide preference for words, minutes, lines, or characters
- Left sidebar with `Documents` and `Outline` views toggled from the titlebar
- Sidebar document navigation that replaces the current file in the same window
- Sidebar outline navigation with active-section tracking while scrolling
- Off-main-thread parsing
- Same-document anchors that scroll in place and cross-document anchors that open at the target section
- Semantic callouts for curated block directives like `note`, `tip`, `important`, `warning`, and `caution`
- Rendered symbol links and class-preserving inline attributes
- Syntax-highlighted fenced code blocks for common languages including Swift, shell, JSON, YAML, Markdown, Go, Ruby, Python, Elixir, JavaScript, TypeScript, PHP, C, C++, Rust, Zig, Haskell, Java, HTML/XML, CSS/SCSS, TOML, Diff, and Dockerfile
- External links open in the default browser
- Local markdown links reuse open windows by file identity and cascade new windows when needed
- Local images load through a custom local asset scheme in WebKit
- Scroll position is remembered per file fingerprint
