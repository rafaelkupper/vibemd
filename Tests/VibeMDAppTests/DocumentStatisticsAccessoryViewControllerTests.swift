import AppKit
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

@MainActor
final class DocumentStatisticsAccessoryViewControllerTests: XCTestCase {
    func testAccessoryStartsHiddenAndShowsWordCountByDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notificationCenter = NotificationCenter()
        let store = DocumentStatisticPreferenceStore(defaults: defaults, notificationCenter: notificationCenter)
        let controller = DocumentStatisticsAccessoryViewController(
            preferenceStore: store,
            notificationCenter: notificationCenter
        )

        controller.loadViewIfNeeded()
        XCTAssertNil(controller.displayedTextForTesting)

        controller.apply(statistics: DocumentStatistics(words: 870, minutes: 5, lines: 306, characters: 6708))

        XCTAssertEqual(controller.displayedTextForTesting, "870 Words")
        XCTAssertGreaterThan(controller.preferredWidthForTesting, 100)
    }

    func testSelectingDifferentMetricUpdatesDisplayImmediately() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notificationCenter = NotificationCenter()
        let store = DocumentStatisticPreferenceStore(defaults: defaults, notificationCenter: notificationCenter)
        let controller = DocumentStatisticsAccessoryViewController(
            preferenceStore: store,
            notificationCenter: notificationCenter
        )
        controller.loadViewIfNeeded()
        controller.apply(statistics: DocumentStatistics(words: 870, minutes: 5, lines: 306, characters: 6708))

        let item = NSMenuItem(title: "Lines", action: nil, keyEquivalent: "")
        item.representedObject = DocumentStatisticKind.lines.rawValue
        controller.selectKind(item)

        XCTAssertEqual(store.selectedKind, .lines)
        XCTAssertEqual(controller.displayedTextForTesting, "306 Lines")
    }

    func testChangingMetricBroadcastUpdatesMultipleOpenWindows() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notificationCenter = NotificationCenter()
        let store = DocumentStatisticPreferenceStore(defaults: defaults, notificationCenter: notificationCenter)
        let first = DocumentStatisticsAccessoryViewController(
            preferenceStore: store,
            notificationCenter: notificationCenter
        )
        let second = DocumentStatisticsAccessoryViewController(
            preferenceStore: store,
            notificationCenter: notificationCenter
        )
        first.loadViewIfNeeded()
        second.loadViewIfNeeded()

        let stats = DocumentStatistics(words: 870, minutes: 5, lines: 306, characters: 6708)
        first.apply(statistics: stats)
        second.apply(statistics: stats)

        store.selectedKind = .characters

        let expected = stats.displayText(for: .characters)
        XCTAssertEqual(first.displayedTextForTesting, expected)
        XCTAssertEqual(second.displayedTextForTesting, expected)
    }

    func testSidebarToggleCallbackCanBeTriggered() {
        let controller = DocumentStatisticsAccessoryViewController()
        controller.loadViewIfNeeded()

        var activationCount = 0
        controller.onToggleSidebar = {
            activationCount += 1
        }

        controller.triggerSidebarToggleForTesting()

        XCTAssertEqual(activationCount, 1)
    }
}
