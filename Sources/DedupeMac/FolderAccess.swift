import Foundation

/// Keeps access to the folders the user picked, across launches.
///
/// In the App Sandbox, a folder picked in the Open dialog or dragged onto the
/// window is readable only until the app quits. A security-scoped bookmark
/// saved in UserDefaults lets the app open it again on the next launch.
final class FolderAccess {
    private let defaultsKey = "FolderBookmarks"
    private var bookmarks: [URL: Data] = [:]
    /// URLs on which `startAccessingSecurityScopedResource()` succeeded,
    /// keyed by the standardized URL the app uses.
    private var scoped: [URL: URL] = [:]

    deinit {
        for url in scoped.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Resolves the saved bookmarks and starts access to each folder.
    /// Folders that no longer exist are dropped.
    func restore() -> [URL] {
        guard let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else { return [] }
        var folders: [URL] = []
        for data in stored {
            guard let resolved = Self.resolve(data) else { continue }
            let (url, isStale) = resolved
            let standardized = url.standardizedFileURL
            guard !folders.contains(standardized) else { continue }
            if url.startAccessingSecurityScopedResource() {
                scoped[standardized] = url
            }
            bookmarks[standardized] = isStale ? (Self.makeBookmark(for: url) ?? data) : data
            folders.append(standardized)
        }
        save(folders)
        return folders
    }

    /// Call while the app still has access to `url`, for example right after
    /// the Open dialog returns it.
    func add(_ url: URL) {
        if let data = Self.makeBookmark(for: url) {
            bookmarks[url] = data
        }
    }

    func remove(_ url: URL) {
        bookmarks[url] = nil
        scoped.removeValue(forKey: url)?.stopAccessingSecurityScopedResource()
    }

    func save(_ folders: [URL]) {
        let list = folders.compactMap { bookmarks[$0] }
        UserDefaults.standard.set(list, forKey: defaultsKey)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        // Builds without the sandbox (for example `swift run`) fall back to
        // a plain bookmark.
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private static func resolve(_ data: Data) -> (URL, Bool)? {
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return (url, isStale)
        }
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return (url, isStale)
        }
        return nil
    }
}
