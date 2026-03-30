import Foundation

public enum LinkTarget: Equatable {
    case external(URL)
    case markdownFile(URL)
    case otherFile(URL)
    case unresolved(String)
}

public final class AssetResolver {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    public init() {}

    public func resolve(destination: String, relativeTo baseURL: URL?) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let absoluteURL = URL(string: trimmed), absoluteURL.scheme != nil {
            return absoluteURL
        }

        if trimmed.hasPrefix("#"), let baseURL {
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            components?.fragment = String(trimmed.dropFirst())
            return components?.url
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard let baseURL else {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard baseURL.isFileURL else {
            return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
        }

        let directoryURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        let pieces = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(pieces.first ?? "")
        let fragment = pieces.count > 1 ? String(pieces[1]) : nil

        var resolvedURL = URL(fileURLWithPath: pathPart, relativeTo: directoryURL).standardizedFileURL
        if let fragment {
            var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)
            components?.fragment = fragment
            resolvedURL = components?.url ?? resolvedURL
        }

        return resolvedURL
    }

    public func imageURL(for source: String, relativeTo baseURL: URL?) -> URL? {
        guard let resolved = resolve(destination: source, relativeTo: baseURL) else {
            return nil
        }

        guard resolved.isFileURL else {
            return nil
        }

        return resolved
    }

    public func linkTarget(for destination: String, relativeTo baseURL: URL?) -> LinkTarget {
        guard let resolved = resolve(destination: destination, relativeTo: baseURL) else {
            return .unresolved(destination)
        }

        return classify(resolved)
    }

    public func classify(_ url: URL) -> LinkTarget {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            return .external(url)
        }

        if url.isFileURL, Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
            return .markdownFile(standardizedFileURLPreservingFragment(url))
        }

        if url.isFileURL {
            return .otherFile(standardizedFileURLPreservingFragment(url))
        }

        return .external(url)
    }

    private func standardizedFileURLPreservingFragment(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        guard let fragment = url.fragment else {
            return standardizedURL
        }

        var components = URLComponents(url: standardizedURL, resolvingAgainstBaseURL: false)
        components?.fragment = fragment
        return components?.url ?? standardizedURL
    }
}
