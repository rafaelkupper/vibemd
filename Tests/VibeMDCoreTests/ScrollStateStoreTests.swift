import Foundation
import XCTest
@testable import VibeMDCore

final class ScrollStateStoreTests: XCTestCase {
    func testSavesAndLoadsScrollFraction() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ScrollStateStore(defaults: defaults)
        let fileURL = URL(fileURLWithPath: "/tmp/example.md")

        store.save(fraction: 0.42, for: fileURL, fingerprint: "fingerprint")
        let loaded = store.load(for: fileURL, fingerprint: "fingerprint")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.fraction ?? -1, 0.42, accuracy: 0.0001)
    }

    func testDifferentFingerprintProducesDifferentEntry() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ScrollStateStore(defaults: defaults)
        let fileURL = URL(fileURLWithPath: "/tmp/example.md")

        store.save(fraction: 0.9, for: fileURL, fingerprint: "old")

        XCTAssertNil(store.load(for: fileURL, fingerprint: "new"))
    }
}
