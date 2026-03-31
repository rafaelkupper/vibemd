import Foundation
import XCTest
@testable import VibeMDApp
@testable import VibeMDCore

final class DocumentStatisticPreferenceStoreTests: XCTestCase {
    func testDefaultsToWordsWhenUnsetOrInvalid() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("invalid", forKey: "documentStatisticKind")
        let store = DocumentStatisticPreferenceStore(defaults: defaults)

        XCTAssertEqual(store.selectedKind, .words)
    }

    func testPersistsSelectedKindAndBroadcastsChange() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let notificationCenter = NotificationCenter()
        let store = DocumentStatisticPreferenceStore(defaults: defaults, notificationCenter: notificationCenter)
        let expectation = expectation(description: "statistic kind change")

        let token = notificationCenter.addObserver(
            forName: .documentStatisticKindDidChange,
            object: nil,
            queue: nil
        ) { note in
            XCTAssertEqual(note.userInfo?["kind"] as? String, DocumentStatisticKind.characters.rawValue)
            expectation.fulfill()
        }

        store.selectedKind = .characters

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(defaults.string(forKey: "documentStatisticKind"), DocumentStatisticKind.characters.rawValue)
        XCTAssertEqual(store.selectedKind, .characters)
        notificationCenter.removeObserver(token)
    }
}
