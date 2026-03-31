import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class DocumentSidebarViewControllerTests: XCTestCase {
    func testDocumentsModeKeepsRowsGroupedAtTopWhenContentIsSparse() {
        let controller = DocumentSidebarViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: DocumentSidebarViewController.sidebarWidth, height: 520)

        controller.apply(
            sidebarEntries: [
                DocumentSidebarEntry(
                    fileURL: URL(fileURLWithPath: "/tmp/Current.md"),
                    displayTitle: "Current",
                    previewText: "Preview",
                    isCurrent: true,
                    isAvailable: true
                ),
                DocumentSidebarEntry(
                    fileURL: URL(fileURLWithPath: "/tmp/Linked.md"),
                    displayTitle: "Linked",
                    previewText: "Preview",
                    isCurrent: false,
                    isAvailable: true
                ),
            ],
            outlineItems: []
        )
        controller.view.layoutSubtreeIfNeeded()

        let frames = controller.arrangedRowFramesForTesting
        XCTAssertEqual(frames.count, 2)

        let sorted = frames.sorted { $0.minY > $1.minY }
        let gap = sorted[0].minY - sorted[1].maxY
        XCTAssertLessThan(gap, 60)
    }

    func testOutlineModeUsesActualIndentedLeadingInsetsPerLevel() {
        let controller = DocumentSidebarViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: DocumentSidebarViewController.sidebarWidth, height: 520)
        controller.setMode(.outline)
        controller.apply(
            sidebarEntries: [],
            outlineItems: [
                DocumentOutlineItem(title: "One", level: 1, anchorID: "one"),
                DocumentOutlineItem(title: "Two", level: 2, anchorID: "two"),
                DocumentOutlineItem(title: "Three", level: 3, anchorID: "three"),
                DocumentOutlineItem(title: "Four", level: 4, anchorID: "four"),
            ]
        )

        XCTAssertEqual(controller.outlineLeadingInsetsForTesting, [16, 32, 48, 64])

        let positions = controller.outlineLabelMinXPositionsForTesting
        XCTAssertEqual(positions.count, 4)
        XCTAssertLessThan(positions[0], positions[1])
        XCTAssertLessThan(positions[1], positions[2])
        XCTAssertLessThan(positions[2], positions[3])
    }

    func testOutlineRowsStayCompactAndOverflowIntoScrollView() {
        let controller = DocumentSidebarViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: DocumentSidebarViewController.sidebarWidth, height: 520)
        controller.setMode(.outline)
        controller.apply(
            sidebarEntries: [],
            outlineItems: (1...40).map { index in
                DocumentOutlineItem(
                    title: "Heading \(index)",
                    level: min((index % 6) + 1, 6),
                    anchorID: "heading-\(index)"
                )
            }
        )
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(controller.arrangedRowHeightsForTesting.isEmpty)
        XCTAssertLessThan(controller.arrangedRowHeightsForTesting.max() ?? 0, 28)
        XCTAssertGreaterThan(controller.scrollDocumentHeightForTesting, controller.scrollViewportHeightForTesting)
    }
}
