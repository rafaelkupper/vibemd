import AppKit
import Foundation

public enum ReaderTheme {
    public static let backgroundHex = "#383E44"
    public static let secondaryTextHex = "#A1A7AE"
    public static let bodyFontStack = "\"Helvetica Neue\", Helvetica, Arial, \"Segoe UI Emoji\", \"SF Pro\", sans-serif"
    public static let contentMaxWidth = 928
    public static let contentHorizontalPadding = 31
    public static let bodyLineHeight = "1.66rem"

    static let sidebarBackgroundHex = "#212427"
    static let sidebarSelectionHex = "#1C2023"
    static let sidebarHoverAlpha: CGFloat = 0.028
    static let sidebarChromeFillAlpha: CGFloat = 0.024
    static let sidebarChromeBorderAlpha: CGFloat = 0.035
    static let sidebarChromeSelectedFillAlpha: CGFloat = 0.065
    static let sidebarChromeHoverFillAlpha: CGFloat = 0.04

    public static let backgroundColor = NSColor.reader(hex: 0x383E44)
    public static let sidebarBackgroundColor = NSColor.reader(hex: 0x212427)
    public static let sidebarSelectionColor = NSColor.reader(hex: 0x1C2023)
    public static let sidebarHoverColor = NSColor.white.withAlphaComponent(sidebarHoverAlpha)
    public static let sidebarChromeFillColor = NSColor.white.withAlphaComponent(sidebarChromeFillAlpha)
    public static let sidebarChromeBorderColor = NSColor.white.withAlphaComponent(sidebarChromeBorderAlpha)
    public static let sidebarChromeSelectedFillColor = NSColor.white.withAlphaComponent(sidebarChromeSelectedFillAlpha)
    public static let sidebarChromeHoverFillColor = NSColor.white.withAlphaComponent(sidebarChromeHoverFillAlpha)
    public static let sidebarPrimaryTextColor = NSColor(white: 0.9, alpha: 0.96)
    public static let sidebarSecondaryTextColor = NSColor(white: 0.66, alpha: 0.92)

    public static let styleSheet = loadStyleSheet()

    private static func loadStyleSheet() -> String {
        for candidate in styleSheetCandidateURLs() {
            if let styleSheet = try? String(contentsOf: candidate, encoding: .utf8) {
                return styleSheet
            }
        }

        return fallbackStyleSheet
    }

    private static func styleSheetCandidateURLs() -> [URL] {
        let resourceBundleName = "VibeMD_VibeMDCore.bundle"
        let resourceFileName = "reader-theme.css"
        let markerBundle = Bundle(for: ResourceBundleMarker.self)
        let mainBundle = Bundle.main
        let candidateResourceRoots = [
            markerBundle.resourceURL,
            markerBundle.bundleURL,
            mainBundle.resourceURL,
            mainBundle.bundleURL,
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources"),
        ]
        let directCandidates = candidateResourceRoots.compactMap { root -> [URL]? in
            guard let root else {
                return nil
            }
            return [
                root.appendingPathComponent(resourceFileName),
                root.appendingPathComponent(resourceBundleName).appendingPathComponent(resourceFileName),
                root.appendingPathComponent("Contents/Resources").appendingPathComponent(resourceFileName),
                root.appendingPathComponent("Contents/Resources").appendingPathComponent(resourceBundleName).appendingPathComponent(resourceFileName),
            ]
        }.flatMap { $0 }

        return deduplicatedURLs(directCandidates + allLoadedBundleCandidates(resourceFileName: resourceFileName))
    }

    private static func allLoadedBundleCandidates(resourceFileName: String) -> [URL] {
        (Bundle.allBundles + Bundle.allFrameworks).compactMap { bundle in
            bundle.resourceURL?.appendingPathComponent(resourceFileName)
        }
    }

    private static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var ordered: [URL] = []

        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                ordered.append(url)
            }
        }

        return ordered
    }
}

private final class ResourceBundleMarker {}

private let fallbackStyleSheet = """
@charset "UTF-8";

:root {
    --bg-color: #383E44;
    --text-color: #BCC3CA;
    --heading-color: #E2E4E7;
    --secondary-text-color: #A1A7AE;
    --link-color: #D7DDE3;
    --rule-color: #4C525A;
    --code-block-bg: #2F3135;
    --selection-bg-color: #4B84D1;
}

html {
    font-size: 16px;
    -webkit-font-smoothing: antialiased;
}

html,
body {
    -webkit-text-size-adjust: 100%;
    -ms-text-size-adjust: 100%;
    background: var(--bg-color);
    color: var(--text-color);
    fill: currentColor;
    line-height: 1.66rem;
    overflow-x: hidden;
    overscroll-behavior-x: none;
}

body,
button,
input,
select,
textarea {
    font-family: "Helvetica Neue", Helvetica, Arial, "Segoe UI Emoji", "SF Pro", sans-serif;
    color: var(--text-color);
    border-color: transparent;
    margin: 0;
}

#write {
    box-sizing: border-box;
    max-width: 928px;
    margin: 0 auto;
    padding: 0 31px 43px;
}

@media only screen and (min-width: 1400px) {
    #write {
        max-width: 1038px;
    }
}

@media only screen and (min-width: 1800px) {
    #write {
        max-width: 1218px;
    }
}

::selection,
*.in-text-selection {
    background: var(--selection-bg-color);
    color: #fff;
    text-shadow: none;
}

h1,
h2,
h3,
h4,
h5,
h6 {
    font-family: "Lucida Grande", "Corbel", sans-serif;
    font-weight: normal;
    clear: both;
    word-wrap: break-word;
    margin: 0;
    padding: 0;
    color: var(--heading-color);
}

h1 {
    font-size: 2.5rem;
    line-height: 2.78rem;
    margin-top: 2.04em;
    margin-bottom: 1.54rem;
    letter-spacing: -1.45px;
}

h2 {
    font-size: 1.63rem;
    line-height: 1.9rem;
    margin-bottom: 1.54rem;
    letter-spacing: -0.98px;
    font-weight: bold;
}

h3 {
    font-size: 1.17rem;
    line-height: 1.52rem;
    margin-bottom: 1.54rem;
    letter-spacing: -0.96px;
    font-weight: bold;
}

h4 {
    font-size: 1.12rem;
    line-height: 1.39rem;
    margin-bottom: 1.54rem;
    color: #FFF;
}

h5 {
    font-size: 0.97rem;
    line-height: 1.27rem;
    margin-bottom: 1.52rem;
    font-weight: bold;
}

h6 {
    font-size: 0.93rem;
    line-height: 1.03rem;
    margin-bottom: 0.78rem;
    color: #FFF;
}

p {
    word-wrap: break-word;
}

p,
ul,
dd,
ol,
hr,
address,
pre,
table {
    margin-top: 0;
    margin-bottom: 1.54rem;
}

ul,
ol {
    padding: 0 0 0 1.95rem;
}

ul {
    list-style: square;
}

ol {
    list-style: decimal;
}

ul ul,
ol ol,
ul ol,
ol ul {
    margin: 0;
}

b,
th,
dt,
strong {
    font-weight: bold;
    color: var(--heading-color);
}

i,
em,
dfn,
cite {
    font-style: italic;
}

a {
    color: var(--link-color);
    text-decoration: underline;
    outline: 0;
    transition: color .2s ease-in-out;
}

a:hover {
    color: #FFF;
}

blockquote {
    padding-left: 31px;
    margin: 36px 0 1.95rem 1.95rem;
    border-left: solid 2px var(--rule-color);
}

blockquote p:last-child {
    margin-bottom: 0;
}

pre,
code,
kbd,
tt,
var {
    font-size: 0.875em;
    font-family: Monaco, Consolas, "Andale Mono", "DejaVu Sans Mono", monospace;
}

:not(pre) > code,
tt,
var {
    background: var(--code-block-bg);
    padding: 2px 5px;
}

kbd {
    padding: 2px 4px;
    font-size: 90%;
    color: #FFF;
    background-color: var(--code-block-bg);
    border: 1px solid #727880;
    border-radius: 3px;
    box-shadow: inset 0 -1px 0 rgba(0, 0, 0, 0.22);
}

.md-callout {
    margin: 0 0 1.54rem;
    padding: 0.86rem 1rem 0.95rem;
    border-left: 3px solid transparent;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.04);
}

.md-callout-label {
    margin: 0 0 0.48rem;
    font-size: 0.76rem;
    line-height: 1.05rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    font-weight: 600;
    color: var(--heading-color);
}

.md-callout-body > :first-child {
    margin-top: 0;
}

.md-callout-body > :last-child {
    margin-bottom: 0;
}

.md-callout-note {
    border-left-color: rgba(125, 161, 188, 0.9);
    background: rgba(125, 161, 188, 0.11);
}

.md-callout-tip {
    border-left-color: rgba(127, 181, 151, 0.9);
    background: rgba(127, 181, 151, 0.11);
}

.md-callout-important {
    border-left-color: rgba(143, 152, 213, 0.92);
    background: rgba(143, 152, 213, 0.11);
}

.md-callout-warning {
    border-left-color: rgba(191, 152, 102, 0.94);
    background: rgba(191, 152, 102, 0.12);
}

.md-callout-caution {
    border-left-color: rgba(190, 125, 125, 0.94);
    background: rgba(190, 125, 125, 0.12);
}

.md-symbol-link {
    color: #C8D6F0;
    border: 1px solid rgba(200, 214, 240, 0.14);
}

.md-inline-chip {
    display: inline-block;
    padding: 0 0.5rem;
    border-radius: 999px;
    border: 1px solid rgba(255, 255, 255, 0.08);
    background: rgba(255, 255, 255, 0.055);
    color: var(--heading-color);
}

.md-inline-muted {
    color: var(--secondary-text-color);
}

pre.md-fences {
    padding: 11px 11px 11px 31px;
    margin-bottom: 21px;
    background: var(--code-block-bg);
    white-space: pre-wrap;
    overflow-wrap: anywhere;
}

pre.md-fences code {
    background: transparent;
    padding: 0;
    color: inherit;
    font-size: inherit;
}

.cm-s-inner,
.cm-s-inner span {
    font-family: Monaco, Consolas, "Andale Mono", "DejaVu Sans Mono", monospace;
}

.cm-s-inner {
    color: var(--text-color);
}

.cm-s-inner .cm-variable,
.cm-s-inner .cm-property {
    color: #D2D8EA;
}

.cm-s-inner .cm-operator {
    color: var(--text-color);
}

.cm-s-inner .cm-keyword {
    color: #CB94D4;
}

.cm-s-inner .cm-string {
    color: #D87272;
}

.cm-s-inner .cm-comment {
    color: #D59452;
}

.cm-s-inner .cm-number {
    color: #68AE95;
}

.cm-s-inner .cm-atom {
    color: #87B8CC;
}

.cm-s-inner .cm-link {
    color: #D2D8EA;
}

.cm-s-inner .cm-variable-2 {
    color: #A2BCD7;
}

.cm-s-inner .cm-header,
.cm-s-inner .cm-def {
    color: #9496EF;
}

.cm-s-inner .cm-positive {
    color: #88C09D;
}

.cm-s-inner .cm-negative {
    color: #D48D8D;
}

table {
    max-width: 100%;
    width: 100%;
    border-collapse: collapse;
    border-spacing: 0;
}

th,
td {
    padding: 6px 11px;
    vertical-align: top;
    border: solid 1px var(--rule-color);
}

table a {
    color: var(--heading-color);
}

hr {
    height: 2px;
    border: 0;
    margin: 24px 0 !important;
    background: var(--rule-color);
}

img {
    display: block;
    max-width: 100%;
    height: auto;
}

.task-list {
    padding-left: 0;
}

.md-task-list-item {
    list-style: none;
    padding-left: 1.3rem;
}

.md-task-list-item > input {
    -webkit-appearance: none;
    appearance: none;
    width: 0.875rem;
    height: 0.875rem;
    margin: 0 0.5rem 0 -1.3rem;
    vertical-align: middle;
    border: 1px solid var(--text-color);
    background-color: var(--bg-color);
    position: relative;
    top: auto;
    pointer-events: none;
}

.md-task-list-item > input:checked::before,
.md-task-list-item > input[checked]::before {
    content: "\\221A";
    font-size: 0.625rem;
    line-height: 0.625rem;
    color: var(--heading-color);
    position: absolute;
    top: 0.05rem;
    left: 0.1rem;
}

.fallback-block {
    color: var(--secondary-text-color);
    white-space: pre-wrap;
}
"""

private extension NSColor {
    static func reader(hex: Int, alpha: CGFloat = 1) -> NSColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
