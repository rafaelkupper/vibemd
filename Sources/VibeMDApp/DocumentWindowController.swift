import AppKit

final class DocumentWindowController: NSWindowController {
    static let initialContentSize = NSSize(width: 1040, height: 760)
    static let cascadeOffset: CGFloat = 28

    init(contentViewController: NSViewController, cascadeFrom sourceWindow: NSWindow? = nil) {
        let initialContentSize = Self.initialContentSize
        contentViewController.loadViewIfNeeded()
        contentViewController.view.frame = NSRect(origin: .zero, size: initialContentSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = contentViewController
        window.setContentSize(initialContentSize)
        window.minSize = NSSize(width: 520, height: 360)
        window.titlebarSeparatorStyle = .line
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        let visibleFrame = sourceWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        if let visibleFrame {
            window.setFrame(
                Self.initialFrame(
                    contentSize: initialContentSize,
                    visibleFrame: visibleFrame,
                    cascadeFrom: sourceWindow?.frame
                ),
                display: false
            )
        } else {
            window.center()
        }

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    static func initialFrame(
        contentSize: NSSize,
        visibleFrame: NSRect,
        cascadeFrom sourceFrame: NSRect?
    ) -> NSRect {
        let unclampedOrigin: NSPoint
        if let sourceFrame {
            unclampedOrigin = NSPoint(
                x: sourceFrame.minX + cascadeOffset,
                y: sourceFrame.minY - cascadeOffset
            )
        } else {
            unclampedOrigin = NSPoint(
                x: visibleFrame.midX - (contentSize.width / 2),
                y: visibleFrame.midY - (contentSize.height / 2)
            )
        }

        let clampedOrigin = clampedOrigin(
            unclampedOrigin,
            contentSize: contentSize,
            visibleFrame: visibleFrame
        )

        return NSRect(origin: clampedOrigin, size: contentSize)
    }

    private static func clampedOrigin(
        _ origin: NSPoint,
        contentSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - contentSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - contentSize.height)

        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }
}
