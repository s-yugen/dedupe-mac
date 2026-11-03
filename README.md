# Dedupe for Mac

Dedupe finds duplicate files on your Mac and lets you choose which copies to move to the Trash. It is built for the Mac App Store and runs in the App Sandbox.

- Pick the file types to look for. Tick predefined types (Word, Excel, PowerPoint, PDF, images, audio, video, archives and more) or type your own extensions, such as `psd, epub, tar.gz`.
- Add the folders or drives to search with the Open dialog or by dragging them onto the window. To search the whole Mac, choose the startup disk (Macintosh HD) in the dialog. Dedupe remembers the folders between launches.
- Dedupe compares file contents, not names. `Report.docx` and `Report copy.docx` count as duplicates if their bytes are identical, and two different files that share a name do not.
- Results come in sets. Each set lists every copy with its folder and modification date. Tick the copies to delete, including every copy if you want the file gone, or use a quick-select rule: keep newest, keep oldest, keep shortest path, or keep longest path.
- Ticked files go to the Trash, so you can restore them from Finder. When the move finishes, a message at the bottom of the window says how many files moved and how much space they take, then fades out after 3 seconds. If some files were skipped or could not be moved, the message is orange, stays for 8 seconds, and has a Details button that lists them.
- Click a file name in the results to open the file in its default app, so you can check it before choosing. The magnifying glass button shows the file in Finder.
- Switch between light and dark with the sun/moon button in the toolbar. Its arrow, and View, Appearance, also offer Use System Setting. The app remembers the choice.
- Change the size of the results text with View, Larger Text (Command-plus), Smaller Text (Command-minus) and Actual Size (Command-0). The app remembers the size.

Requires macOS 14 Sonoma or later. Building requires Xcode 16 or later.

## Set up signing in Xcode

1. Open `Dedupe.xcodeproj` in Xcode.
2. If you have not signed in yet, open Xcode, Settings, Accounts, click **+**, and sign in with the Apple ID of your Apple Developer Program membership.
3. In the Project navigator on the left, click the blue **Dedupe** project, then the **Dedupe** target under Targets.
4. Open the **Signing & Capabilities** tab.
5. Leave **Automatically manage signing** ticked and choose your team in **Team**.
6. Change **Bundle Identifier** to one you own, such as `com.yourcompany.dedupe`. The placeholder `io.github.s-yugen.dedupe-mac` will not register under your team.
7. Under **App Sandbox**, check that **User Selected File** is set to Read/Write. The project's entitlements file already sets this.
8. Press Run (Command-R).

The team and bundle identifier you pick are saved in `Dedupe.xcodeproj/project.pbxproj`. Commit that change if you want it in the repository.

## Submit to the Mac App Store

1. In [App Store Connect](https://appstoreconnect.apple.com), go to Apps, click **+**, choose New App, pick macOS, and select the bundle identifier you set in Xcode.
2. In Xcode, set the run destination to **Any Mac**, then choose Product, Archive.
3. When the Organizer window opens, select the archive, click **Distribute App**, choose **App Store Connect**, and follow the steps to upload.
4. Back in App Store Connect, fill in the description, keywords, screenshots, support URL and privacy policy URL, then pick the uploaded build and submit it for review.

Things already set up for review:

| Item | Where |
| --- | --- |
| App Sandbox with read/write access to user-selected files, plus app-scoped bookmarks | `App/Dedupe.entitlements` |
| App icon at every macOS size | `App/Resources/Assets.xcassets/AppIcon.appiconset` |
| Privacy manifest that declares file timestamp and UserDefaults use | `App/Resources/PrivacyInfo.xcprivacy` |
| Export compliance: `ITSAppUsesNonExemptEncryption` is false, because SHA-256 hashing of local files is exempt | `App/Info.plist` |
| App category: Utilities | target build settings |

For the App Privacy questions in App Store Connect, answer that the app collects no data. Dedupe makes no network connections.

Increase **Version** and **Build** on the target's General tab before each new upload.

## Safety rules

- You can tick every copy in a set to remove the file completely, one by one or with Select, Delete all copies. The set header then shows "Every copy will be deleted" in red, and the confirmation dialog says how many sets will have no copy left.
- Right before moving files, the app checks the disk again. In a set where you keep some copies, it skips the whole set if none of the kept copies is still there with the same size, so a file you meant to keep is never lost. It also skips any ticked file whose size changed since the scan.
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

Sets start out sorted by space to free, largest first. Use Sort in the toolbar to sort by:

- Space to free: size times the number of extra copies.
- File size: the size of one copy.
- File name: the first copy's name, in Finder order (case is ignored and "file 2" comes before "file 10").
- Folder: the first copy's folder.

The same menu switches the direction. Picking a new sort key resets the direction to largest first for sizes and A to Z for names and folders. Inside each set, copies are ordered by file name when sorting by name and by folder otherwise. The app remembers the choice.

## Project layout

| Path | Contents |
| --- | --- |
| `Dedupe.xcodeproj` | Xcode project for the app. Open this one. |
| `Sources/DedupeCore` | Scanner, hashing, file type lists, keep rules, and the safe-trash planner. It has no UI code. |
| `Sources/DedupeMac` | SwiftUI app: sidebar with folders and file types, the results list, the Trash flow, and folder bookmarks. |
| `App` | Entitlements, Info.plist additions, app icon and privacy manifest. |
| `Tests/DedupeCoreTests` | XCTest unit tests for `DedupeCore`. |
| `Package.swift` | Swift package used to run the unit tests from Terminal. |
| `.github/workflows/build.yml` | CI: runs the tests and builds the Xcode project without signing. |

The Xcode project compiles `Sources/DedupeCore` and `Sources/DedupeMac` into one app target. Xcode adds any new `.swift` file in those folders to the target, so you do not need to edit the project file when you add code.

Run the unit tests from Terminal with:

```bash
swift test
```

To add a predefined file type, add a case to `FileTypeCategory` in `Sources/DedupeCore/FileTypes.swift` and list its extensions. The sidebar lists every case, so no UI change is needed.
