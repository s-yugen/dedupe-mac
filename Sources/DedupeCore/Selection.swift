import Foundation

/// Quick-select helpers. Each rule picks one file to keep in a group, and the
/// app marks every other copy for deletion.
public enum KeepRule: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case shortestPath
    case longestPath

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newest: return "Keep newest"
        case .oldest: return "Keep oldest"
        case .shortestPath: return "Keep shortest path"
        case .longestPath: return "Keep longest path"
        }
    }

    public func fileToKeep(in group: DuplicateGroup) -> FileItem? {
        group.files.min(by: comesFirst)
    }

    public func filesToDelete(in group: DuplicateGroup) -> [FileItem] {
        guard let keep = fileToKeep(in: group) else { return [] }
        return group.files.filter { $0.url != keep.url }
    }

    /// True when `a` is a better file to keep than `b`.
    private func comesFirst(_ a: FileItem, _ b: FileItem) -> Bool {
        let dateA = a.modified ?? .distantPast
        let dateB = b.modified ?? .distantPast
        switch self {
        case .newest where dateA != dateB:
            return dateA > dateB
        case .oldest where dateA != dateB:
            return dateA < dateB
        case .longestPath where a.path.count != b.path.count:
            return a.path.count > b.path.count
        default:
            // Shortest path, and the tie-breaker for every other rule.
            if a.path.count != b.path.count { return a.path.count < b.path.count }
            return a.path < b.path
        }
    }
}

public struct TrashPlan: Sendable, Equatable {
    /// Files that are safe to move to the Trash.
    public var urlsToTrash: [URL]
    /// Groups where the user meant to keep some copies, but none of the
    /// kept copies is still on disk unchanged. Nothing in these groups is
    /// touched, so a file the user meant to keep is never lost.
    public var blockedGroupIDs: [String]
    /// Selected files whose size changed since the scan. They may no longer
    /// be duplicates, so they are left alone.
    public var changedFiles: [URL]

    public init(urlsToTrash: [URL], blockedGroupIDs: [String], changedFiles: [URL]) {
        self.urlsToTrash = urlsToTrash
        self.blockedGroupIDs = blockedGroupIDs
        self.changedFiles = changedFiles
    }
}

public struct TrashFailure: Sendable, Hashable {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public struct TrashOutcome: Sendable {
    public var trashed: [URL]
    public var failures: [TrashFailure]

    public init(trashed: [URL] = [], failures: [TrashFailure] = []) {
        self.trashed = trashed
        self.failures = failures
    }
}

public enum SafeTrasher {
    /// Checks the selection against what is on disk right now.
    ///
    /// - If every copy in a group is selected, the user chose to remove them
    ///   all, and all of them are trashed.
    /// - Otherwise the selected copies are trashed only if at least one
    ///   unselected copy still exists with the same size.
    ///
    /// In both cases a selected file whose size changed since the scan is
    /// left alone.
    public static func plan(
        selection: Set<URL>,
        groups: [DuplicateGroup],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        currentSize: (URL) -> Int64? = SafeTrasher.sizeOnDisk
    ) -> TrashPlan {
        var urls: [URL] = []
        var blocked: [String] = []
        var changed: [URL] = []

        for group in groups {
            let selected = group.files.filter { selection.contains($0.url) }
            guard !selected.isEmpty else { continue }

            let removesEveryCopy = selected.count == group.files.count
            if !removesEveryCopy {
                let keptOnDisk = group.files.filter {
                    !selection.contains($0.url) && fileExists($0.url) && currentSize($0.url) == group.size
                }
                guard !keptOnDisk.isEmpty else {
                    blocked.append(group.id)
                    continue
                }
            }
            for file in selected {
                if currentSize(file.url) == group.size {
                    urls.append(file.url)
                } else {
                    changed.append(file.url)
                }
            }
        }
        return TrashPlan(urlsToTrash: urls, blockedGroupIDs: blocked, changedFiles: changed)
    }

    public static func execute(
        _ plan: TrashPlan,
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> TrashOutcome {
        var outcome = TrashOutcome()
        for url in plan.urlsToTrash {
            do {
                try trash(url)
                outcome.trashed.append(url)
            } catch {
                outcome.failures.append(TrashFailure(url: url, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    /// Reads the size fresh from disk. URL resource values are cached per
    /// URL object, so they could be stale here.
    public static func sizeOnDisk(_ url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}
