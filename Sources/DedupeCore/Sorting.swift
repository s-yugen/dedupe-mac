import Foundation

/// How the results list orders the duplicate sets.
public enum DuplicateSortOrder: String, CaseIterable, Identifiable, Sendable {
    /// Bytes freed by keeping one copy (size times extra copies).
    case spaceToFree
    /// Size of one copy.
    case fileSize
    case fileName
    case folder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .spaceToFree: return "Space to Free"
        case .fileSize: return "File Size"
        case .fileName: return "File Name"
        case .folder: return "Folder"
        }
    }

    /// Sizes start with the largest, names and folders start at A.
    public var defaultAscending: Bool {
        switch self {
        case .spaceToFree, .fileSize: return false
        case .fileName, .folder: return true
        }
    }

    public var ascendingTitle: String {
        switch self {
        case .spaceToFree, .fileSize: return "Smallest First"
        case .fileName, .folder: return "A to Z"
        }
    }

    public var descendingTitle: String {
        switch self {
        case .spaceToFree, .fileSize: return "Largest First"
        case .fileName, .folder: return "Z to A"
        }
    }
}

public enum DuplicateSorter {
    /// Sorts the sets, and the copies inside each set.
    ///
    /// Inside a set, copies are ordered by file name when sorting by name,
    /// and by folder otherwise. Sets are then compared by their first copy,
    /// so sorting by folder groups sets that live in the same folder.
    public static func sort(
        _ groups: [DuplicateGroup],
        by order: DuplicateSortOrder,
        ascending: Bool
    ) -> [DuplicateGroup] {
        let prepared = groups.map { group -> DuplicateGroup in
            var group = group
            group.files.sort { compareFiles($0, $1, by: order) == .orderedAscending }
            return group
        }
        return prepared.sorted { a, b in
            let result = compareGroups(a, b, by: order)
            if result == .orderedSame {
                // Keep the order stable between runs.
                return a.id < b.id
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    static func compareGroups(_ a: DuplicateGroup, _ b: DuplicateGroup, by order: DuplicateSortOrder) -> ComparisonResult {
        switch order {
        case .spaceToFree:
            let byWaste = compare(a.wastedBytes, b.wastedBytes)
            return byWaste != .orderedSame ? byWaste : compare(a.size, b.size)
        case .fileSize:
            let bySize = compare(a.size, b.size)
            return bySize != .orderedSame ? bySize : compareText(firstName(a), firstName(b))
        case .fileName:
            let byName = compareText(firstName(a), firstName(b))
            return byName != .orderedSame ? byName : compareText(firstFolder(a), firstFolder(b))
        case .folder:
            let byFolder = compareText(firstFolder(a), firstFolder(b))
            return byFolder != .orderedSame ? byFolder : compareText(firstName(a), firstName(b))
        }
    }

    static func compareFiles(_ a: FileItem, _ b: FileItem, by order: DuplicateSortOrder) -> ComparisonResult {
        let primary: ComparisonResult
        let secondary: ComparisonResult
        if order == .fileName {
            primary = compareText(a.name, b.name)
            secondary = compareText(a.folderPath, b.folderPath)
        } else {
            primary = compareText(a.folderPath, b.folderPath)
            secondary = compareText(a.name, b.name)
        }
        if primary != .orderedSame { return primary }
        if secondary != .orderedSame { return secondary }
        return a.path < b.path ? .orderedAscending : (a.path > b.path ? .orderedDescending : .orderedSame)
    }

    private static func firstName(_ group: DuplicateGroup) -> String {
        group.files.first?.name ?? ""
    }

    private static func firstFolder(_ group: DuplicateGroup) -> String {
        group.files.first?.folderPath ?? ""
    }

    /// Finder-style comparison: ignores case and orders "file 2" before
    /// "file 10".
    private static func compareText(_ a: String, _ b: String) -> ComparisonResult {
        a.localizedStandardCompare(b)
    }

    private static func compare(_ a: Int64, _ b: Int64) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
