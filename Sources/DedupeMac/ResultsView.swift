import AppKit
#if canImport(DedupeCore)
import DedupeCore
#endif
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "No scan yet",
                systemImage: "doc.on.doc",
                description: Text("Add the folders to search and pick file types on the left, then click Scan for Duplicates.")
            )
        case .scanning:
            ScanProgressView()
        case .finished:
            if model.groups.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No duplicates found",
                        systemImage: "checkmark.circle",
                        description: Text("Checked \(model.filesScanned) matching files.")
                    )
                    ScanNotes()
                        .padding()
                }
            } else {
                DuplicateListView()
            }
        }
    }
}

struct ScanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let progress = model.progress
        VStack(spacing: 14) {
            switch progress.phase {
            case .listing:
                ProgressView()
                    .controlSize(.large)
                Text("Looking for files: \(progress.filesFound) found")
            case .comparing:
                ProgressView()
                    .controlSize(.large)
                Text("Comparing \(progress.filesFound) files by size")
            case .hashing:
                ProgressView(
                    value: Double(progress.filesHashed),
                    total: Double(max(progress.filesToHash, 1))
                )
                .frame(width: 360)
                Text("Checking contents: \(progress.filesHashed) of \(progress.filesToHash) files")
            case .done:
                ProgressView()
                    .controlSize(.large)
                Text("Finishing")
            }
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520)
            Button("Cancel") { model.cancelScan() }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Warnings about files the scan could not look at.
struct ScanNotes: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.unreadablePaths.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Skipped \(model.unreadablePaths.count) items that macOS did not allow Dedupe to read. Hover for the list.")
                }
                .help(model.unreadablePaths.prefix(20).joined(separator: "\n"))
            }
            if model.skippedCloudOnly > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "icloud")
                        .foregroundStyle(.secondary)
                    Text("Skipped \(model.skippedCloudOnly) iCloud files that are not downloaded to this Mac.")
                }
            }
        }
        .font(.callout)
    }
}

struct DuplicateListView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmTrash = false
    @State private var searchText = ""

    private var visibleGroups: [DuplicateGroup] {
        guard !searchText.isEmpty else { return model.groups }
        return model.groups.filter { group in
            group.files.contains { $0.path.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        let groups = visibleGroups
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.groups.count) sets of duplicates. \(model.totalWastedBytes.formattedBytes) can be freed by keeping one copy of each.")
                        .font(.headline)
                    Text("Tick the copies to delete. Use Auto-Select in the toolbar or the Select menu on each set to tick all but one copy. To remove a file completely, tick every copy in its set. Use Sort in the toolbar to order the sets by space to free, file size, file name or folder. Click a file name to open the file. Change the text size with View > Larger Text (Command-plus) and Smaller Text (Command-minus).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ScanNotes()
                }
                .padding(.vertical, 4)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.files) { file in
                        FileRow(file: file, group: group)
                    }
                } header: {
                    GroupHeader(group: group)
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .searchable(text: $searchText, placement: .toolbar, prompt: "Filter by name or folder")
        .toolbar {
            ToolbarItemGroup {
                SortMenu()

                Menu {
                    ForEach(KeepRule.allCases) { rule in
                        Button(rule.title) { model.apply(rule, to: groups) }
                    }
                    Divider()
                    Button(searchText.isEmpty ? "Tick every copy in every set" : "Tick every copy in the filtered sets") {
                        model.markAll(in: groups)
                    }
                } label: {
                    Label("Auto-Select", systemImage: "wand.and.stars")
                }
                .help(searchText.isEmpty ? "Tick all but one copy in every set" : "Tick all but one copy in the filtered sets")

                Button {
                    model.clearMarks()
                } label: {
                    Label("Clear Selection", systemImage: "xmark.circle")
                }
                .disabled(model.marked.isEmpty)
                .help("Untick every file")
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .confirmationDialog(
            "Move \(model.marked.count) files to the Trash?",
            isPresented: $confirmTrash,
            titleVisibility: .visible
        ) {
            Button(
                model.fullyMarkedGroupCount > 0 ? "Move to Trash, Including Every Copy" : "Move to Trash",
                role: .destructive
            ) {
                model.trashMarked()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        var text = "This frees \(model.markedBytes.formattedBytes) once you empty the Trash. Until then you can restore the files from the Trash in Finder."
        let fullSets = model.fullyMarkedGroupCount
        if fullSets == 1 {
            text = "1 set has every copy ticked. No copy of that file will be left once you empty the Trash.\n\n" + text
        } else if fullSets > 1 {
            text = "\(fullSets) sets have every copy ticked. No copy of those files will be left once you empty the Trash.\n\n" + text
        }
        return text
    }

    private var bottomBar: some View {
        HStack {
            if model.isTrashing {
                ProgressView().controlSize(.small)
                Text("Moving files to the Trash")
            } else if model.marked.isEmpty {
                Text("No files selected")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(model.marked.count) files selected, \(model.markedBytes.formattedBytes)")
            }
            Spacer()
            Button(role: .destructive) {
                confirmTrash = true
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .controlSize(.large)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.marked.isEmpty || model.isTrashing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// Toolbar menu that picks the sort key and direction for the sets.
struct SortMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let order = model.sortOrder
        Menu {
            Picker(
                "Sort By",
                selection: Binding(
                    get: { model.sortOrder },
                    set: { model.setSortOrder($0) }
                )
            ) {
                ForEach(DuplicateSortOrder.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)

            Picker(
                "Order",
                selection: Binding(
                    get: { model.sortAscending },
                    set: { model.setSortAscending($0) }
                )
            ) {
                Text(order.ascendingTitle).tag(true)
                Text(order.descendingTitle).tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort: \(order.title)", systemImage: model.sortAscending ? "arrow.up" : "arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .help("Sorted by \(order.title.lowercased()), \((model.sortAscending ? order.ascendingTitle : order.descendingTitle).lowercased())")
    }
}

struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ResultsTextSize.key) private var textSize = ResultsTextSize.standard
    let group: DuplicateGroup

    var body: some View {
        HStack(spacing: 8) {
            Text(group.files.first?.name ?? "")
                .font(.system(size: textSize + 1, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(group.files.count) copies, \(group.size.formattedBytes) each")
                .font(.system(size: textSize - 1))
                .foregroundStyle(.secondary)
            if model.isFullyMarked(group) {
                Label("Every copy will be deleted", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: textSize - 1, weight: .semibold))
                    .foregroundStyle(.red)
            }
            Spacer()
            Menu("Select") {
                ForEach(KeepRule.allCases) { rule in
                    Button(rule.title) { model.apply(rule, to: [group]) }
                }
                Divider()
                Button("Delete all copies") { model.markAll(in: [group]) }
                Button("Keep all copies") { model.unmark(group) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.top, 8)
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ResultsTextSize.key) private var textSize = ResultsTextSize.standard
    @State private var isHoveringName = false
    let file: FileItem
    let group: DuplicateGroup

    private var detailSize: Double { textSize - 2 }

    var body: some View {
        let isMarked = model.isMarked(file)
        HStack(spacing: 12) {
            Toggle(
                "Delete",
                isOn: Binding(
                    get: { model.isMarked(file) },
                    set: { model.setMarked($0, file: file) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .controlSize(textSize >= 17 ? .large : .regular)
            .help(isMarked ? "Untick to keep this copy" : "Tick to move this copy to the Trash")

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: textSize * 2, height: textSize * 2)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    model.open(file)
                } label: {
                    Text(file.name)
                        .font(.system(size: textSize))
                        .strikethrough(isMarked)
                        .underline(isHoveringName && !isMarked)
                        .foregroundStyle(isMarked ? Color.secondary : Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Open \(file.name)")
                .onHover { hovering in
                    isHoveringName = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onDisappear {
                    if isHoveringName {
                        NSCursor.pop()
                        isHoveringName = false
                    }
                }

                Text((file.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: detailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text("Modified " + (file.modified?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"))
                    .font(.system(size: detailSize))
                    .monospacedDigit()
                if isMarked {
                    Text("Will move to Trash")
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(.red)
                } else {
                    Text("Keep")
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Button {
                model.reveal(file)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: detailSize + 1))
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open") { model.open(file) }
            Button("Show in Finder") { model.reveal(file) }
            Button("Copy Path") { model.copyPath(file) }
        }
    }
}
