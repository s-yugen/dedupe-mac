import XCTest
@testable import DedupeCore

final class ScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DedupeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ relativePath: String, _ data: Data) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    @discardableResult
    private func write(_ relativePath: String, _ text: String) throws -> URL {
        try write(relativePath, Data(text.utf8))
    }

    private func scan(_ extensions: Set<String>, roots: [URL]? = nil, hidden: Bool = false) throws -> ScanResult {
        try DuplicateScanner().scan(options: ScanOptions(
            roots: roots ?? [root],
            extensions: extensions,
            includeHiddenFiles: hidden
        ))
    }

    func testFindsCopiesByContentNotName() throws {
        try write("a.docx", "hello")
        try write("sub/renamed copy.docx", "hello")
        try write("c.docx", "world") // same size, different content
        try write("d.txt", "hello") // file type not selected
        try write("empty1.docx", "")
        try write("empty2.docx", "")

        let result = try scan(["docx"])

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(Set(result.groups[0].files.map(\.name)), ["a.docx", "renamed copy.docx"])
        XCTAssertEqual(result.groups[0].size, 5)
        XCTAssertEqual(result.groups[0].wastedBytes, 5)
        XCTAssertEqual(result.filesScanned, 3) // empty files are ignored
    }

    func testLargeFilesThatDifferOnlyAtTheEnd() throws {
        var data = Data((0..<200_000).map { UInt8($0 % 251) })
        try write("big1.pdf", data)
        try write("folder/big2.pdf", data)
        data[data.count - 1] ^= 0xFF
        try write("big3.pdf", data)

        let result = try scan(["pdf"])

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(Set(result.groups[0].files.map(\.name)), ["big1.pdf", "big2.pdf"])
    }

    func testMatchesExtensionsIgnoringCase() throws {
        try write("A.DOCX", "same")
        try write("b.docx", "same")

        let result = try scan(["docx"])

        XCTAssertEqual(result.groups.first?.files.count, 2)
    }

    func testSeveralFileTypesInOneScan() throws {
        try write("x.pdf", "pdf-bytes")
        try write("y.pdf", "pdf-bytes")
        try write("x.xlsx", "sheet")
        try write("y.xlsx", "sheet")

        let result = try scan(["pdf", "xlsx"])

        XCTAssertEqual(result.groups.count, 2)
    }

    func testHiddenFilesSkippedByDefault() throws {
        try write(".secret.docx", "same")
        try write("visible.docx", "same")

        XCTAssertTrue(try scan(["docx"]).groups.isEmpty)
        XCTAssertEqual(try scan(["docx"], hidden: true).groups.count, 1)
    }

    func testOverlappingRootsDoNotDoubleCount() throws {
        try write("a.docx", "hello")
        try write("sub/b.docx", "hello")

        let result = try scan(["docx"], roots: [root, root.appendingPathComponent("sub")])

        XCTAssertEqual(result.groups.count, 1)
        XCTAssertEqual(result.groups[0].files.count, 2)
    }

    func testHardLinksAreNotDuplicates() throws {
        let original = try write("a.docx", "hello")
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("link.docx"))

        XCTAssertTrue(try scan(["docx"]).groups.isEmpty)
    }

    func testSymlinksAreIgnored() throws {
        let original = try write("a.docx", "hello")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("alias.docx"),
            withDestinationURL: original
        )

        XCTAssertTrue(try scan(["docx"]).groups.isEmpty)
    }

    func testTrashFolderIsSkipped() throws {
        try write("a.docx", "hello")
        try write("stuff/.Trash/b.docx", "hello")

        XCTAssertTrue(try scan(["docx"], hidden: true).groups.isEmpty)
    }

    func testEmptyExtensionSetFindsNothing() throws {
        try write("a.docx", "hello")
        try write("b.docx", "hello")

        let result = try scan([])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.filesScanned, 0)
    }

    func testReportsProgress() throws {
        try write("a.docx", "hello")
        try write("b.docx", "hello")
        let phases = PhaseRecorder()

        _ = try DuplicateScanner().scan(options: ScanOptions(roots: [root], extensions: ["docx"])) {
            phases.record($0.phase)
        }

        XCTAssertEqual(phases.values.last, .done)
        XCTAssertTrue(phases.values.contains(.hashing))
    }

    func testDirectorySkipRules() {
        let home = "/Users/alice"
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/System", includeLibrary: false, homePath: home))
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/System", includeLibrary: true, homePath: home))
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/Users/alice/Library", includeLibrary: false, homePath: home))
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/Users/bob/Library", includeLibrary: false, homePath: home))
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/Library", includeLibrary: false, homePath: home))
        XCTAssertFalse(DuplicateScanner.shouldSkipDirectory(path: "/Users/alice/Library", includeLibrary: true, homePath: home))
        XCTAssertFalse(DuplicateScanner.shouldSkipDirectory(path: "/Users/alice/Documents/Library", includeLibrary: false, homePath: home))
        XCTAssertFalse(DuplicateScanner.shouldSkipDirectory(path: "/Volumes/Backup/private", includeLibrary: false, homePath: home))
        XCTAssertTrue(DuplicateScanner.shouldSkipDirectory(path: "/Volumes/Backup/.Trashes", includeLibrary: false, homePath: home))
    }

    func testNormalizedRoots() {
        let roots = DuplicateScanner.normalizedRoots([
            URL(fileURLWithPath: "/Users/alice/Documents"),
            URL(fileURLWithPath: "/Users/alice"),
            URL(fileURLWithPath: "/Users/alicea"),
        ])
        XCTAssertEqual(roots.map(\.path), ["/Users/alice", "/Users/alicea"])
    }
}

private final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScanProgress.Phase] = []

    func record(_ phase: ScanProgress.Phase) {
        lock.lock()
        storage.append(phase)
        lock.unlock()
    }

    var values: [ScanProgress.Phase] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
