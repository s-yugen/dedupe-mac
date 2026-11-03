import DedupeCore
import SwiftUI

/// Sidebar: folders to search, file types, options and the Scan button.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                if model.folders.isEmpty {
                    Text("No folders yet. Add one below or drop a folder here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.folders, id: \.self) { url in
                    HStack {
                        Image(systemName: url.path == "/" ? "internaldrive" : "folder")
                            .foregroundStyle(.secondary)
                        Text(displayPath(url))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(url.path)
                        Spacer()
                        Button {
                            model.removeFolder(url)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this folder")
                    }
                }
                Menu("Add Folder") {
                    Button("Choose Folder or Drive...") { model.chooseFolders() }
                    Button("Home Folder") { model.addHomeFolder() }
                    Button("Entire Startup Disk") { model.addWholeDisk() }
                }
                .fixedSize()
            } header: {
                Text("Search in")
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.addFolders(urls)
                return true
            }

            ForEach(FileTypeGroup.allCases) { group in
                Section {
                    ForEach(group.categories) { category in
                        Toggle(isOn: model.binding(for: category)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(category.extensionsLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Button("All") { model.setAll(in: group, selected: true) }
                        Button("None") { model.setAll(in: group, selected: false) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Section {
                TextField("Extensions", text: $model.customExtensionsText, prompt: Text("psd, epub, .sketch"))
                if model.customExtensions.isEmpty {
                    Text("Separate extensions with commas or spaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Will also match: " + model.customExtensions.sorted().joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Other file types")
            }

            Section {
                Toggle("Include hidden files", isOn: $model.includeHiddenFiles)
                Toggle("Include Library folders", isOn: $model.includeLibraryFolders)
                    .help("Library folders hold app data. Deleting files there can break apps.")
            } header: {
                Text("Options")
            }
        }
        .formStyle(.grouped)
        .disabled(model.phase == .scanning || model.isTrashing)
        .safeAreaInset(edge: .bottom) {
            scanBar
        }
    }

    private var scanBar: some View {
        VStack(spacing: 6) {
            if model.phase == .scanning {
                Button(role: .cancel) {
                    model.cancelScan()
                } label: {
                    Text("Cancel Scan").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            } else {
                Button {
                    model.startScan()
                } label: {
                    Text("Scan for Duplicates").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canScan)

                if model.folders.isEmpty {
                    hint("Add at least one folder.")
                } else if model.allExtensions.isEmpty {
                    hint("Choose at least one file type.")
                } else {
                    hint("\(model.allExtensions.count) extensions selected")
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func displayPath(_ url: URL) -> String {
        if url.path == "/" { return "Startup Disk (/)" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}
