import Foundation

/// One file found on disk.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let modified: Date?
    public let created: Date?

    public init(url: URL, size: Int64, modified: Date? = nil, created: Date? = nil) {
        self.url = url
        self.size = size
        self.modified = modified
        self.created = created
    }

    public var path: String { url.path }
    public var name: String { url.lastPathComponent }
    /// Path of the folder that holds the file.
    public var folderPath: String { url.deletingLastPathComponent().path }
}

/// Two or more files with identical contents.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    /// Size plus SHA-256 of the contents.
    public let id: String
    public let size: Int64
    public var files: [FileItem]

    public init(id: String, size: Int64, files: [FileItem]) {
        self.id = id
        self.size = size
        self.files = files
    }

    /// Bytes freed if every copy except one is removed.
    public var wastedBytes: Int64 {
        size * Int64(max(files.count - 1, 0))
    }
}

public struct ScanOptions: Sendable {
    public var roots: [URL]
    public var extensions: Set<String>
    public var includeHiddenFiles: Bool
    /// When false, the scanner skips ~/Library, /Users/*/Library and /Library.
    public var includeLibraryFolders: Bool
    /// Files smaller than this are ignored. Empty files are all "identical"
    /// and removing them frees nothing, so the default is 1 byte.
    public var minimumFileSize: Int64

    public init(
        roots: [URL],
        extensions: Set<String>,
        includeHiddenFiles: Bool = false,
        includeLibraryFolders: Bool = false,
        minimumFileSize: Int64 = 1
    ) {
        self.roots = roots
        self.extensions = extensions
        self.includeHiddenFiles = includeHiddenFiles
        self.includeLibraryFolders = includeLibraryFolders
        self.minimumFileSize = minimumFileSize
    }
}

public struct ScanProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case listing
        case comparing
        case hashing
        case done
    }

    public var phase: Phase = .listing
    /// Files that matched the selected extensions so far.
    public var filesFound = 0
    /// Files whose size matches at least one other file.
    public var filesToHash = 0
    public var filesHashed = 0
    public var currentPath = ""

    public init() {}
}

public struct ScanResult: Sendable {
    public var groups: [DuplicateGroup]
    /// Files that matched the selected extensions.
    public var filesScanned: Int
    /// Folders and files the scanner could not read, usually because of
    /// missing Full Disk Access.
    public var unreadablePaths: [String]
    /// iCloud files that are not downloaded. Reading them would start a
    /// download, so the scanner skips them.
    public var skippedCloudOnly: Int

    public init(groups: [DuplicateGroup], filesScanned: Int, unreadablePaths: [String], skippedCloudOnly: Int) {
        self.groups = groups
        self.filesScanned = filesScanned
        self.unreadablePaths = unreadablePaths
        self.skippedCloudOnly = skippedCloudOnly
    }

    public var totalWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }
}
