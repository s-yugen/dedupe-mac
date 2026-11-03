import XCTest
@testable import DedupeCore

final class SelectionTests: XCTestCase {
    private func file(_ path: String, daysAgo: Double?) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: path),
            size: 10,
            modified: daysAgo.map { Date(timeIntervalSince1970: 1_700_000_000 - $0 * 86_400) }
        )
    }

    private lazy var group = DuplicateGroup(id: "g", size: 10, files: [
        file("/Users/a/Documents/Reports/2024/report.docx", daysAgo: 30),
        file("/Users/a/Desktop/report.docx", daysAgo: 1),
        file("/Users/a/Downloads/report (1).docx", daysAgo: 400),
    ])

    func testKeepNewest() {
        XCTAssertEqual(KeepRule.newest.fileToKeep(in: group)?.path, "/Users/a/Desktop/report.docx")
        XCTAssertEqual(KeepRule.newest.filesToDelete(in: group).count, 2)
    }

    func testKeepOldest() {
        XCTAssertEqual(KeepRule.oldest.fileToKeep(in: group)?.path, "/Users/a/Downloads/report (1).docx")
    }

    func testKeepShortestAndLongestPath() {
        XCTAssertEqual(KeepRule.shortestPath.fileToKeep(in: group)?.path, "/Users/a/Desktop/report.docx")
        XCTAssertEqual(KeepRule.longestPath.fileToKeep(in: group)?.path, "/Users/a/Documents/Reports/2024/report.docx")
    }

    func testRulesNeverDeleteEveryCopy() {
        for rule in KeepRule.allCases {
            XCTAssertEqual(rule.filesToDelete(in: group).count, group.files.count - 1, rule.title)
        }
    }

    func testTieBreakIsStable() {
        let tie = DuplicateGroup(id: "t", size: 1, files: [
            file("/b/x.pdf", daysAgo: nil),
            file("/a/x.pdf", daysAgo: nil),
        ])
        XCTAssertEqual(KeepRule.newest.fileToKeep(in: tie)?.path, "/a/x.pdf")
    }

    // MARK: SafeTrasher

    func testPlanTrashesEveryCopyWhenEverythingIsSelected() {
        let all = Set(group.files.map(\.url))
        let plan = SafeTrasher.plan(selection: all, groups: [group], fileExists: { _ in true }, currentSize: { _ in 10 })
        XCTAssertEqual(Set(plan.urlsToTrash), all)
        XCTAssertEqual(plan.blockedGroupIDs, [])
    }

    func testPlanSkipsChangedFileEvenWhenEverythingIsSelected() {
        let all = Set(group.files.map(\.url))
        let changed = group.files[0].url
        let plan = SafeTrasher.plan(
            selection: all,
            groups: [group],
            fileExists: { _ in true },
            currentSize: { $0 == changed ? 99 : 10 }
        )
        XCTAssertEqual(Set(plan.urlsToTrash), all.subtracting([changed]))
        XCTAssertEqual(plan.changedFiles, [changed])
    }

    func testPlanBlocksGroupWhenKeptCopyIsGone() {
        let keep = group.files[0].url
        let selection = Set(group.files.dropFirst().map(\.url))
        let plan = SafeTrasher.plan(
            selection: selection,
            groups: [group],
            fileExists: { $0 != keep },
            currentSize: { _ in 10 }
        )
        XCTAssertEqual(plan.urlsToTrash, [])
        XCTAssertEqual(plan.blockedGroupIDs, ["g"])
    }

    func testPlanSkipsFilesThatChanged() {
        let changed = group.files[2].url
        let selection: Set<URL> = [group.files[1].url, changed]
        let plan = SafeTrasher.plan(
            selection: selection,
            groups: [group],
            fileExists: { _ in true },
            currentSize: { $0 == changed ? 99 : 10 }
        )
        XCTAssertEqual(plan.urlsToTrash, [group.files[1].url])
        XCTAssertEqual(plan.changedFiles, [changed])
    }

    func testExecuteReportsFailures() {
        let plan = TrashPlan(
            urlsToTrash: [URL(fileURLWithPath: "/ok"), URL(fileURLWithPath: "/locked")],
            blockedGroupIDs: [],
            changedFiles: []
        )
        struct Locked: Error {}
        let outcome = SafeTrasher.execute(plan) { url in
            if url.path == "/locked" { throw Locked() }
        }
        XCTAssertEqual(outcome.trashed.map(\.path), ["/ok"])
        XCTAssertEqual(outcome.failures.map(\.url.path), ["/locked"])
    }

    func testTrashesRealFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = dir.appendingPathComponent("keep.txt")
        let remove = dir.appendingPathComponent("remove.txt")
        try Data("same".utf8).write(to: keep)
        try Data("same".utf8).write(to: remove)
        let realGroup = DuplicateGroup(id: "r", size: 4, files: [
            FileItem(url: keep, size: 4),
            FileItem(url: remove, size: 4),
        ])

        let plan = SafeTrasher.plan(selection: [remove], groups: [realGroup])
        XCTAssertEqual(plan.urlsToTrash, [remove])

        // Delete directly instead of using the Trash so the test leaves
        // nothing behind on the build machine.
        let outcome = SafeTrasher.execute(plan) { try FileManager.default.removeItem(at: $0) }
        XCTAssertEqual(outcome.trashed, [remove])
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: remove.path))
    }
}
