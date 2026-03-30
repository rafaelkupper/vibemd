# VibeMD Rendering Showcase

Open this file in VibeMD to preview the current reader surface. It is meant to exercise readable width, spacing, lists, tables, code blocks, images, links, and fallback styling in a single document.

Quick links:
- External link: [swift-markdown](https://github.com/swiftlang/swift-markdown)
- Local markdown link: [Linked Note](LinkedNote.md)
- Local non-markdown link: [MIT License](LICENSE)

## Heading Ladder

# Level 1 Heading

## Level 2 Heading

### Level 3 Heading

#### Level 4 Heading

##### Level 5 Heading

###### Level 6 Heading

## Paragraph Rhythm

The goal of this pass is a calmer reader surface: a centered column, native typography, clearer hierarchy, and enough spacing to make dense markdown easier to scan without feeling like a web page inside a wrapper.

This second paragraph exists mostly to make line height, paragraph spacing, and column width obvious. Resize the window narrower and wider to see how the content reflows while staying inside a readable text measure.

## Inline Styling

Plain text should feel neutral. `Inline code` should read like a soft utility chip instead of a selected region. You should also see **strong emphasis**, *emphasis*, ***combined emphasis***, and ~~strikethrough~~ render distinctly without feeling heavy.

You can also mix styles in one sentence: **bold text with `inline code` inside it** and a link to [Apple](https://www.apple.com).

## Blockquote

> VibeMD should feel like a quiet native document reader, not a browser tab pretending to be a Mac app.
>
> This quote includes `inline code` and an [external link](https://developer.apple.com/documentation/foundation/nsattributedstring) so you can verify that nested styling still holds together inside the quote block.

## Lists

- Top-level bullet item
- Bullet item with enough copy to wrap onto another line so the hanging indent is visible and the marker column stays separate from the body text.
  - Nested bullet item
  - Nested bullet item with `inline code`
  - Nested bullet item with a [markdown link](LinkedNote.md)
- Another top-level bullet item

1. Ordered item one
2. Ordered item two with a slightly longer sentence to show how wrapped lines align after the marker.
3. Ordered item three
   - Nested unordered item
   - Another nested unordered item

## Task Lists

- [x] Completed task item
- [ ] Pending task item
- [x] A longer completed task that should wrap and still keep the checkbox aligned against the text body instead of drifting into the paragraph.

## Code Blocks

```swift
struct ReaderTheme {
    let readableWidth: Double
    let outerGutter: Double
    let bodyLineSpacing: Double
}

let longLine = "This intentionally long line exists to check that fenced code wraps inside the reading column instead of forcing an ugly horizontal reading experience."

func render(_ markdown: String) -> String {
    markdown.trimmingCharacters(in: .whitespacesAndNewlines)
}
```

```bash
./scripts/build-app.sh release
open build/VibeMD.app
```

## Tables

| Surface | Current Treatment | What To Look For | Score |
| --- | --- | --- | ---: |
| Paragraphs | Native text layout | Comfortable rhythm and readable width | 9 |
| Headings | Strong hierarchy | Distinct scale without giant spacing cliffs | 9 |
| Inline code | Soft chip styling | Monospaced text with restrained contrast | 8 |
| Code blocks | Native text blocks | Padded container, calmer border, wrapped lines | 8 |
| Blockquotes | Left rule and soft fill | Separation without looking like a callout card | 8 |
| Tables | Native text tables | Real cells, subtle borders, alternating rows | 8 |

## Image

The app should load this local image asynchronously after the first text paint:

![VibeMD App Icon Preview](App/Resources/VibeMD-preview.png)

## Thematic Break

The section below is separated by a thematic break so you can judge how subtle or strong the rule feels.

---

## Fallback Styling

Raw HTML block fallback:

<aside>
This HTML block is intentionally unsupported in the reader and should degrade into a calm styled fallback block instead of disappearing or looking broken.
</aside>

Block directive fallback:

:::note
This block directive should also degrade into a styled fallback block.
:::

Inline HTML fallback should appear inline without exploding the paragraph: press <kbd>Cmd</kbd> + <kbd>O</kbd> to open another file.

## Scroll Check

If you can scroll smoothly from here back to the top, the centered-column layout, text sizing, and content height calculation are all behaving correctly.

This last section is only here to make the document a bit taller. Native document readers feel much better when they are tested with enough content to expose layout, scrolling, and reflow behavior rather than a tiny README-sized snippet.
