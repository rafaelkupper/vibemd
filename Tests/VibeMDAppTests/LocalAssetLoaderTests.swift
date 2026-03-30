import Foundation
import XCTest
@testable import VibeMDApp

final class LocalAssetLoaderTests: XCTestCase {
    func testFileURLExtractionRejectsInvalidLocalAssetURLs() {
        XCTAssertThrowsError(try LocalAssetLoader.fileURL(for: URL(string: "vibemd-local://wrong?path=/tmp/file.png")!))
        XCTAssertThrowsError(try LocalAssetLoader.fileURL(for: URL(string: "vibemd-local://asset")!))
    }

    func testLoadReturnsDataAndMimeTypeForLocalFiles() throws {
        let tempDirectory = try TemporaryTestDirectory()
        defer { tempDirectory.remove() }
        let fileURL = try tempDirectory.createTextFile(named: "note.txt", contents: "hello")
        let requestURL = URL(string: "vibemd-local://asset?path=\(fileURL.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)")!

        let response = try LocalAssetLoader.load(from: requestURL)

        XCTAssertEqual(response.data, Data("hello".utf8))
        XCTAssertEqual(response.response.mimeType, "text/plain")
    }
}
