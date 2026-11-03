import AppKit
#if canImport(DedupeCore)
import DedupeCore
#endif
import Observation
import SwiftUI

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case finished
    }

    // MARK: Setup

    /// Folders to search. The sandbox only lets the app read folders the
    /// user picked, so this starts empty and is restored from bookmarks.
    private(set) var folders: [URL] = []
    var selectedCategories: Set<FileTypeCategory> = [.word, .excel, .powerpoint, .pdf]
    var customExtensionsText = ""
    var includeHiddenFiles = false
    var includeLibraryFolders = false

    // MARK: Scan state

    var phase: Phase = .idle
    var progress = ScanProgress()
    var groups: [DuplicateGroup] = []
    var marked: Set<URL> = []
    var filesScanned = 0
    var unreadablePaths: [String] = []
    var skippedCloudOnly = 0
    var isTrashing = false
    var alert: AlertInfo?

    private var worker: Task<ScanResult, Error>?
    private let folderAccess = FolderAccess()

    // MARK: Sorting

    private static let sortOrderKey = "SortOrder"
    private static let sortAscendingKey = "SortAscending"

    /// `groups` is always kept in this order, so the list does not re-sort
    /// on every checkbox click.
    private(set) var sortOrder: DuplicateSortOrder = .spaceToFree
    private(set) var sortAscending = false

    init() {
        folders = folderAccess.restore()
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.sortOrderKey),
           let order = DuplicateSortOrder(rawValue: raw) {
            sortOrder = order
            sortAscending = defaults.object(forKey: Self.sortAscendingKey) as? Bool ?? order.defaultAscending
        }
    }

    /// Picking a new sort key also resets the direction to the natural one
    /// for that key: largest first for sizes, A to Z for names and folders.
    func setSortOrder(_ order: DuplicateSortOrder) {
        guard order != sortOrder else { return }
        sortOrder = order
        sortAscending = order.defaultAscending
        applySort()
    }

    func setSortAscending(_ ascending: Bool) {
        guard ascending != sortAscending else { return }
        sortAscending = ascending
        applySort()
    }

    private func applySort() {
        UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        UserDefaults.standard.set(sortAscending, forKey: Self.sortAscendingKey)
        groups = DuplicateSorter.sort(groups, by: sortOrder, ascending: sortAscending)
    }

    // MARK: Derived values

    var customExtensions: Set<String> {
        ExtensionParser.parse(customExtensionsText)
    }

    var allExtensions: Set<String> {
        selectedCategories.reduce(into: customExtensions) { result, category in
            result.formUnion(category.extensions)
        }
    }

    var canScan: Bool {
        !folders.isEmpty && !allExtensions.isEmpty && phase != .scanning && !isTrashing
    }

    var totalWastedBytes: Int64 {
        groups.reduce(0) { $0 + $1.wastedBytes }
    }

    var markedBytes: Int64 {
        groups.reduce(0) { total, group in
            total + Int64(group.files.filter { marked.contains($0.url) }.count) * group.size
        }
    }

    // MARK: Folders

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = UserHome.directory
        panel.prompt = "Add"
        panel.message = "Choose folders or drives to search for duplicates. Dedupe can only read the folders you choose here."
        if panel.runModal() == .OK {
            addFolders(panel.urls)
        }
    }

    func addFolders(_ urls: [URL]) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let standardized = url.standardizedFileURL
            guard !folders.contains(standardized) else { continue }
            folderAccess.add(standardized)
            folders.append(standardized)
        }
        folderAccess.save(folders)
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        folderAccess.remove(url)
        folderAccess.save(folders)
    }

    // MARK: File types

    func binding(for category: FileTypeCategory) -> Binding<Bool> {
        Binding(
            get: { self.selectedCategories.contains(category) },
            set: { isOn in
                if isOn {
                    self.selectedCategories.insert(category)
                } else {
                    self.selectedCategories.remove(category)
                }
            }
        )
    }

    func setAll(in group: FileTypeGroup, selected: Bool) {
        for category in group.categories {
            if selected {
                selectedCategories.insert(category)
            } else {
                selectedCategories.remove(category)
            }
        }
    }

    // MARK: Scanning

    func startScan() {
        guard canScan else { return }
        let options = ScanOptions(
            roots: folders,
            extensions: allExtensions,
            includeHiddenFiles: includeHiddenFiles,
            includeLibraryFolders: includeLibraryFolders
        )
        phase = .scanning
        progress = ScanProgress()
        groups = []
        marked = []
        unreadablePaths = []
        skippedCloudOnly = 0
        filesScanned = 0

        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] update in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .scanning else { return }
                self.progress = update
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            try DuplicateScanner().scan(options: options, progress: onProgress)
        }
        self.worker = worker

        Task {
            let result = await worker.result
            finishScan(result)
        }
    }

    func cancelScan() {
        worker?.cancel()
    }

    private func finishScan(_ result: Result<ScanResult, Error>) {
        worker = nil
        switch result {
        case .success(let scan):
            groups = DuplicateSorter.sort(scan.groups, by: sortOrder, ascending: sortAscending)
            filesScanned = scan.filesScanned
            unreadablePaths = scan.unreadablePaths
            skippedCloudOnly = scan.skippedCloudOnly
            phase = .finished
        case .failure(let error):
            phase = .idle
            if !(error is CancellationError) {
                alert = AlertInfo(title: "Scan failed", message: error.localizedDescription)
            }
        }
    }

    // MARK: Marking files for deletion

    func isMarked(_ file: FileItem) -> Bool {
        marked.contains(file.url)
    }

    func setMarked(_ value: Bool, file: FileItem) {
        if value {
            marked.insert(file.url)
        } else {
            marked.remove(file.url)
        }
    }

    /// True when every copy in the group is ticked, so nothing of it would
    /// be left after the Trash is emptied.
    func isFullyMarked(_ group: DuplicateGroup) -> Bool {
        !group.files.isEmpty && group.files.allSatisfy { marked.contains($0.url) }
    }

    var fullyMarkedGroupCount: Int {
        groups.filter(isFullyMarked).count
    }

    func markAll(in targetGroups: [DuplicateGroup]) {
        for group in targetGroups {
            for file in group.files {
                marked.insert(file.url)
            }
        }
    }

    func apply(_ rule: KeepRule, to targetGroups: [DuplicateGroup]) {
        for group in targetGroups {
            for file in group.files {
                marked.remove(file.url)
            }
            for file in rule.filesToDelete(in: group) {
                marked.insert(file.url)
            }
        }
    }

    func unmark(_ group: DuplicateGroup) {
        for file in group.files {
            marked.remove(file.url)
        }
    }

    func clearMarks() {
        marked.removeAll()
    }

    // MARK: Trash

    func trashMarked() {
        guard !marked.isEmpty, !isTrashing else { return }
        let plan = SafeTrasher.plan(selection: marked, groups: groups)
        let sizes = Dictionary(
            groups.flatMap { group in group.files.map { ($0.url, group.size) } },
            uniquingKeysWith: { first, _ in first }
        )
        isTrashing = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                SafeTrasher.execute(plan)
            }.value
            finishTrash(plan: plan, outcome: outcome, sizes: sizes)
        }
    }

    private func finishTrash(plan: TrashPlan, outcome: TrashOutcome, sizes: [URL: Int64]) {
        isTrashing = false
        let trashed = Set(outcome.trashed)
        marked.subtract(trashed)
        groups = groups.compactMap { group in
            var updated = group
            updated.files.removeAll { trashed.contains($0.url) }
            return updated.files.count > 1 ? updated : nil
        }
        let remaining = Set(groups.flatMap { $0.files.map(\.url) })
        marked.formIntersection(remaining)

        let freed = outcome.trashed.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        var lines = ["Moved \(outcome.trashed.count) file(s), \(freed.formattedBytes), to the Trash."]
        if !plan.blockedGroupIDs.isEmpty {
            lines.append("Skipped \(plan.blockedGroupIDs.count) set(s) because the copies you chose to keep are no longer on disk.")
        }
        if !plan.changedFiles.isEmpty {
            lines.append("Skipped \(plan.changedFiles.count) file(s) that changed since the scan.")
        }
        if !outcome.failures.isEmpty {
            let examples = outcome.failures.prefix(5).map { "\($0.url.path): \($0.reason)" }
            lines.append("Could not move \(outcome.failures.count) file(s):\n" + examples.joined(separator: "\n"))
        }
        alert = AlertInfo(title: "Done", message: lines.joined(separator: "\n\n"))
    }

    // MARK: Finder

    func reveal(_ file: FileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func open(_ file: FileItem) {
        guard FileManager.default.fileExists(atPath: file.path) else {
            alert = AlertInfo(title: "File not found", message: "\(file.path) was moved or deleted after the scan.")
            return
        }
        if !NSWorkspace.shared.open(file.url) {
            alert = AlertInfo(title: "Could not open file", message: "No app on this Mac can open \(file.name).")
        }
    }

    func copyPath(_ file: FileItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.path, forType: .string)
    }
}
