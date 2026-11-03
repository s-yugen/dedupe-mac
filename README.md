# Dedupe for Mac

Dedupe finds duplicate files on your Mac and lets you choose which copies to move to the Trash.

- Pick the file types to look for. Tick predefined types (Word, Excel, PowerPoint, PDF, images, audio, video, archives and more) or type your own extensions, such as `psd, epub, tar.gz`.
- Pick the folders or drives to search. The default is your home folder. You can add other folders, external drives, or the whole startup disk.
- Dedupe compares file contents, not names. `Report.docx` and `Report copy.docx` count as duplicates if their bytes are identical, and two different files that share a name do not.
- Results come in sets. Each set lists every copy with its folder and modification date. Tick the copies to delete, or use a quick-select rule: keep newest, keep oldest, keep shortest path, or keep longest path.
- Ticked files go to the Trash, so you can restore them from Finder.

Requires macOS 14 Sonoma or later. Runs on Apple silicon and Intel Macs.

## Safety rules

- Each set must keep at least one copy. The app disables the last unticked checkbox in a set.
- Right before moving files, the app checks the disk again. It skips a set if the kept copy is gone or has changed size, and it skips any ticked file whose size changed since the scan.
- Files go to the Trash. Nothing is deleted until you empty the Trash.
- The scan skips system folders (`/System`, `/private`, `/usr`, `/bin`, `/sbin`, `/opt`, `/dev`, `/cores`) and Trash folders.
- The scan skips `Library` folders unless you turn on "Include Library folders". Apps keep their data there, and deleting files in them can break apps.
- The scan treats packages (`.app` bundles, Photos libraries, `.pages` bundles and similar) as single items and does not look inside them.
- Symbolic links are ignored. Hard links to the same file count as one file, because deleting one frees no space.
- Empty files are ignored.
- iCloud files that are not downloaded to the Mac are skipped, because reading them would start a download.

## How the scan works

1. Walk the chosen folders and keep files whose extension matches. Extensions match without regard to case.
2. Group the files by size. A file with a unique size cannot have a duplicate, so it is never read.
3. For each size shared by two or more files, hash the first 16 KB with SHA-256.
4. For files that still match and are larger than 16 KB, hash the whole file.
5. Files with the same size and the same full SHA-256 hash form a duplicate set.

Sets are sorted by how much space they waste, largest first.

## Get the app

### Option 1: download from GitHub Actions

Every push builds the app on a macOS runner.

1. Open the repository's **Actions** tab and pick the latest green **Build** run.
2. Download the **Dedupe-app** artifact at the bottom of the run page.
3. Unzip it. GitHub wraps the file in a second zip, so you get `Dedupe.zip`; unzip that too to get `Dedupe.app`.
4. Move `Dedupe.app` to your Applications folder.

The app has an ad-hoc signature but is not notarized by Apple, so macOS blocks the first launch. To allow it:

- On macOS 15 Sequoia and later, open the app once and dismiss the warning. Then go to System Settings, Privacy & Security, scroll down, and click **Open Anyway** next to the Dedupe message.
- On macOS 14 Sonoma, Control-click the app in Finder, choose **Open**, then click **Open** in the dialog.

You can also clear the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Dedupe.app
```

### Option 2: build in Xcode

1. Install Xcode 15 or later from the App Store.
2. Clone this repository.
3. In Xcode, choose File, Open, and select `Package.swift`. You can also run `open Package.swift` in Terminal.
4. Select the `DedupeMac` scheme and **My Mac** as the destination, then press Run (Command-R).

### Option 3: build from Terminal

With Xcode or the Xcode command line tools installed:

```bash
./scripts/build-app.sh
```

This writes `build/Dedupe.app` and `build/Dedupe.zip`. It builds a universal binary by default. To build only for the current Mac, which is faster:

```bash
UNIVERSAL=0 ./scripts/build-app.sh
```

Run the tests with:

```bash
swift test
```

## Permissions

macOS asks for permission the first time Dedupe reads Desktop, Documents, Downloads, or an external drive. Click **Allow**.

Some folders stay unreadable without Full Disk Access. After a scan, the results page shows how many items could not be read and has a button that opens the right Settings page. To grant access, go to System Settings, Privacy & Security, Full Disk Access, add Dedupe, and run the scan again.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/DedupeCore` | Scanner, hashing, file type lists, keep rules, and the safe-trash planner. It has no UI code and is covered by unit tests. |
| `Sources/DedupeMac` | SwiftUI app: sidebar with folders and file types, the results list, and the Trash flow. |
| `Tests/DedupeCoreTests` | XCTest unit tests for `DedupeCore`. |
| `Resources/Info.plist` | App bundle metadata used by `scripts/build-app.sh`. |
| `scripts/build-app.sh` | Builds the release binary and wraps it in `Dedupe.app`. |
| `.github/workflows/build.yml` | CI: runs the tests, builds the app, and uploads the zip. |

To add a predefined file type, add a case to `FileTypeCategory` in `Sources/DedupeCore/FileTypes.swift` and list its extensions. The sidebar lists every case, so no UI change is needed.
