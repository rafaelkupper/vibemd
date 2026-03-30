import Foundation
import UniformTypeIdentifiers

struct LocalAssetResponse {
    let response: URLResponse
    let data: Data
}

enum LocalAssetLoader {
    static func load(from requestURL: URL) throws -> LocalAssetResponse {
        let fileURL = try fileURL(for: requestURL)
        let data = try Data(contentsOf: fileURL)
        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        return LocalAssetResponse(response: response, data: data)
    }

    static func fileURL(for requestURL: URL) throws -> URL {
        guard
            let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
            components.host == "asset",
            let filePath = components.queryItems?.first(where: { $0.name == "path" })?.value
        else {
            throw NSError(
                domain: "LocalAssetLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid local asset URL."]
            )
        }

        return URL(fileURLWithPath: filePath).standardizedFileURL
    }

    static func mimeType(for fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension
        if
            let type = UTType(filenameExtension: fileExtension),
            let mimeType = type.preferredMIMEType
        {
            return mimeType
        }

        return "application/octet-stream"
    }
}
