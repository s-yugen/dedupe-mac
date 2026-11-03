import AppKit
import DedupeCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView(
                "No scan yet",
                systemImage: "doc.on.doc",
                description: Text("Pick folders and file types on the left, then click Scan for Duplicates.")
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
                    Text("\(model.unreadablePaths.count) items could not be read. Give Dedupe Full Disk Access to include them.")
                    Button("Open Settings") { model.openFullDiskAccessSettings() }
                        .buttonStyle(.link)
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
                    Text("Tick the copies to delete. Use Auto-Select in the toolbar or the Select menu on each set to tick all but one copy. Each set always keeps at least one file.")
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
                Menu {
                    ForEach(KeepRule.allCases) { rule in
                        Button(rule.title) { model.apply(rule, to: groups) }
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
            Button("Move to Trash", role: .destructive) { model.trashMarked() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This frees \(model.markedBytes.formattedBytes) once you empty the Trash. You can restore the files from the Trash in Finder until then.")
        }
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

struct GroupHeader: View {
    @Environment(AppModel.self) private var model
    let group: DuplicateGroup

    var body: some View {
        HStack(spacing: 8) {
            Text(group.files.first?.name ?? "")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(group.files.count) copies, \(group.size.formattedBytes) each")
                .foregroundStyle(.secondary)
            Spacer()
            Menu("Select") {
                ForEach(KeepRule.allCases) { rule in
                    Button(rule.title) { model.apply(rule, to: [group]) }
                }
                Divider()
                Button("Keep all") { model.unmark(group) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.top, 6)
    }
}

struct FileRow: View {
    @Environment(AppModel.self) private var model
    let file: FileItem
    let group: DuplicateGroup

    var body: some View {
        let isMarked = model.isMarked(file)
        let canToggle = model.canMark(file, in: group)
        HStack(spacing: 10) {
            Toggle(
                "Delete",
                isOn: Binding(
                    get: { model.isMarked(file) },
                    set: { model.setMarked($0, file: file, in: group) }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!canToggle)
            .help(canToggle ? "Tick to move this copy to the Trash" : "At least one copy must be kept")

            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .strikethrough(isMarked)
                    .foregroundStyle(isMarked ? Color.secondary : Color.primary)
                Text((file.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.path)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Modified " + (file.modified?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"))
                    .font(.caption)
                    .monospacedDigit()
                if isMarked {
                    Text("Will move to Trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Keep")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Button {
                model.reveal(file)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Finder") { model.reveal(file) }
            Button("Open") { model.open(file) }
            Button("Copy Path") { model.copyPath(file) }
        }
    }
}
