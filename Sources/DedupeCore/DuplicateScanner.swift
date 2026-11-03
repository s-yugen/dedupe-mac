import Foundation

/// Finds files with identical contents.
///
/// The scan runs in three passes so that most files are never read:
/// 1. List files that match the chosen extensions and group them by size.
/// 2. For each size with two or more files, hash the first 16 KB.
/// 3. For files that still match and are larger than 16 KB, hash the whole file.
///
/// `scan` is synchronous and checks `Task.isCancelled` as it goes, so run it
/// inside a detached task and cancel that task to stop it.
public struct DuplicateScanner: Sendable {
    public static let partialHashBytes = 16 * 1024

    /// Top-level system folders that never hold user documents.
    static let systemDirectories: Set<String> = [
        "/System", "/private", "/usr", "/bin", "/sbin", "/cores", "/dev", "/opt",
    ]

    public init() {}

    public func scan(
        options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) throws -> ScanResult {
        try Task.checkCancellation()
        let reporter = ProgressReporter(handler: progress)
        let log = ScanLog()
        let matcher = ExtensionMatcher(extensions: options.extensions)
        guard !matcher.isEmpty else {
            return ScanResult(groups: [], filesScanned: 0, unreadablePaths: [], skippedCloudOnly: 0)
        }

        let files = try listFiles(options: options, matcher: matcher, reporter: reporter, log: log)

        reporter.update(force: true) { $0.phase = .comparing }
        var bySize: [Int64: [FileItem]] = [:]
        for file in files {
            bySize[file.size, default: []].append(file)
        }
        let sizeGroups = bySize.values
            .filter { $0.count > 1 }
            .map(Self.removingHardLinks)
            .filter { $0.count > 1 }

        let toHash = sizeGroups.reduce(0) { $0 + $1.count }
        reporter.update(force: true) {
            $0.phase = .hashing
            $0.filesToHash = toHash
            $0.filesHashed = 0
        }

        var groups: [DuplicateGroup] = []
        for sameSize in sizeGroups {
            try Task.checkCancellation()
            let size = sameSize[0].size

            var byPartial: [String: [FileItem]] = [:]
            for file in sameSize {
                reporter.update { $0.currentPath = file.path }
                if let hash = try hash(file, maxBytes: Self.partialHashBytes, log: log) {
                    byPartial[hash, default: []].append(file)
                }
                reporter.update { $0.filesHashed += 1 }
            }

            for (partialHash, candidates) in byPartial where candidates.count > 1 {
                if size <= Int64(Self.partialHashBytes) {
                    // The partial hash already covered the whole file.
                    groups.append(Self.makeGroup(size: size, hash: partialHash, files: candidates))
                    continue
                }
                var byFull: [String: [FileItem]] = [:]
                for file in candidates {
                    reporter.update { $0.currentPath = file.path }
                    if let hash = try hash(file, maxBytes: nil, log: log) {
                        byFull[hash, default: []].append(file)
                    }
                }
                for (fullHash, matches) in byFull where matches.count > 1 {
                    groups.append(Self.makeGroup(size: size, hash: fullHash, files: matches))
                }
            }
        }

        groups.sort {
            if $0.wastedBytes != $1.wastedBytes { return $0.wastedBytes > $1.wastedBytes }
            return $0.id < $1.id
        }
        reporter.update(force: true) {
            $0.phase = .done
            $0.currentPath = ""
        }
        return ScanResult(
            groups: groups,
            filesScanned: files.count,
            unreadablePaths: log.unreadable,
            skippedCloudOnly: log.skippedCloudOnly
        )
    }

    // MARK: - Listing

    private func listFiles(
        options: ScanOptions,
        matcher: ExtensionMatcher,
        reporter: ProgressReporter,
        log: ScanLog
    ) throws -> [FileItem] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        let keySet = Set(keys)
        // Packages such as .app bundles and Photos libraries are skipped as a
        // whole. Deleting files inside them would break them.
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !options.includeHiddenFiles {
            enumerationOptions.insert(.skipsHiddenFiles)
        }
        let homePath = UserHome.directory.standardizedFileURL.path

        var seenPaths = Set<String>()
        var items: [FileItem] = []

        for root in Self.normalizedRoots(options.roots) {
            try Task.checkCancellation()
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: enumerationOptions,
                errorHandler: { url, _ in
                    log.unreadable.append(url.path)
                    return true
                }
            ) else {
                log.unreadable.append(root.path)
                continue
            }

            while let next = enumerator.nextObject() {
                try Task.checkCancellation()
                guard let url = next as? URL else { continue }
                guard let values = try? url.resourceValues(forKeys: keySet) else {
                    log.unreadable.append(url.path)
                    continue
                }

                if values.isDirectory == true {
                    if Self.shouldSkipDirectory(
                        path: url.standardizedFileURL.path,
                        includeLibrary: options.includeLibraryFolders,
                        homePath: homePath
                    ) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                guard matcher.matches(fileName: url.lastPathComponent) else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= options.minimumFileSize else { continue }
                if values.isUbiquitousItem == true,
                   let status = values.ubiquitousItemDownloadingStatus,
                   status != .current {
                    log.skippedCloudOnly += 1
                    continue
                }

                let standardized = url.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else { continue }
                items.append(FileItem(
                    url: standardized,
                    size: size,
                    modified: values.contentModificationDate,
                    created: values.creationDate
                ))
                let count = items.count
                reporter.update {
                    $0.filesFound = count
                    $0.currentPath = standardized.path
                }
            }
        }
        reporter.update(force: true) { $0.filesFound = items.count }
        return items
    }

    /// Standardizes the roots and drops any root inside another root, so no
    /// folder is scanned twice.
    static func normalizedRoots(_ roots: [URL]) -> [URL] {
        let sorted = roots
            .map { $0.standardizedFileURL }
            .sorted { $0.path.count < $1.path.count }
        var result: [URL] = []
        for root in sorted where !result.contains(where: { isPath(root.path, inside: $0.path) }) {
            result.append(root)
        }
        return result
    }

    static func isPath(_ path: String, inside base: String) -> Bool {
        if path == base { return true }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix)
    }

    /// Decides whether to skip a directory found during the walk. The roots
    /// themselves are never passed here, so a user who picks ~/Library
    /// directly still gets it scanned.
    static func shouldSkipDirectory(path: String, includeLibrary: Bool, homePath: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if name == ".Trash" || name == ".Trashes" { return true }
        if systemDirectories.contains(path) { return true }
        if !includeLibrary {
            if path == "/Library" { return true }
            if path == (homePath as NSString).appendingPathComponent("Library") { return true }
            let grandparent = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            if name == "Library" && grandparent == "/Users" { return true }
        }
        return false
    }

    // MARK: - Hashing

    private func hash(_ file: FileItem, maxBytes: Int?, log: ScanLog) throws -> String? {
        do {
            return try FileHasher.sha256(of: file.url, maxBytes: maxBytes)
        } catch let error as CancellationError {
            throw error
        } catch {
            log.unreadable.append(file.path)
            return nil
        }
    }

    private struct FileIdentity: Hashable {
        let device: Int64
        let inode: UInt64
    }

    /// Hard links point at the same data, so deleting one frees nothing.
    /// Keep only one path per inode.
    static func removingHardLinks(_ files: [FileItem]) -> [FileItem] {
        var seen = Set<FileIdentity>()
        return files.filter { file in
            var info = stat()
            guard lstat(file.path, &info) == 0 else { return true }
            let identity = FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
            return seen.insert(identity).inserted
        }
    }

    private static func makeGroup(size: Int64, hash: String, files: [FileItem]) -> DuplicateGroup {
        DuplicateGroup(
            id: "\(size)-\(hash)",
            size: size,
            files: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )
    }
}

/// Mutable state shared with the enumerator's error handler.
private final class ScanLog {
    var unreadable: [String] = []
    var skippedCloudOnly = 0
}

/// Sends progress at most ten times a second, plus on phase changes.
private final class ProgressReporter {
    private var state = ScanProgress()
    private var lastSent: TimeInterval = 0
    private let handler: @Sendable (ScanProgress) -> Void

    init(handler: @escaping @Sendable (ScanProgress) -> Void) {
        self.handler = handler
    }

    func update(force: Bool = false, _ change: (inout ScanProgress) -> Void) {
        change(&state)
        let now = Date().timeIntervalSinceReferenceDate
        if force || now - lastSent >= 0.1 {
            lastSent = now
            handler(state)
        }
    }
}
