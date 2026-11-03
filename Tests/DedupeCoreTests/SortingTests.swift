import XCTest
@testable import DedupeCore

final class SortingTests: XCTestCase {
    private func file(_ path: String, size: Int64) -> FileItem {
        FileItem(url: URL(fileURLWithPath: path), size: size)
    }

    // small.txt: 2 copies x 10 bytes, 10 bytes to free, folders /b and /z
    // Big.pdf: 2 copies x 500 bytes, 500 bytes to free, folders /m and /c
    // medium.doc: 4 copies x 200 bytes, 600 bytes to free, folder /a
    private lazy var groups = [
        DuplicateGroup(id: "small", size: 10, files: [
            file("/z/small.txt", size: 10),
            file("/b/small.txt", size: 10),
        ]),
        DuplicateGroup(id: "big", size: 500, files: [
            file("/m/Big.pdf", size: 500),
            file("/c/Another Big.pdf", size: 500),
        ]),
        DuplicateGroup(id: "medium", size: 200, files: [
            file("/a/x/medium.doc", size: 200),
            file("/a/medium.doc", size: 200),
            file("/a/y/medium.doc", size: 200),
            file("/a/copy of medium.doc", size: 200),
        ]),
    ]

    private func ids(_ order: DuplicateSortOrder, ascending: Bool) -> [String] {
        DuplicateSorter.sort(groups, by: order, ascending: ascending).map(\.id)
    }

    func testSpaceToFree() {
        XCTAssertEqual(ids(.spaceToFree, ascending: false), ["medium", "big", "small"])
        XCTAssertEqual(ids(.spaceToFree, ascending: true), ["small", "big", "medium"])
    }

    func testFileSize() {
        XCTAssertEqual(ids(.fileSize, ascending: false), ["big", "medium", "small"])
        XCTAssertEqual(ids(.fileSize, ascending: true), ["small", "medium", "big"])
    }

    func testFileNameIgnoresCase() {
        // After sorting inside each set: "Another Big.pdf", "copy of medium.doc", "small.txt".
        XCTAssertEqual(ids(.fileName, ascending: true), ["big", "medium", "small"])
        XCTAssertEqual(ids(.fileName, ascending: false), ["small", "medium", "big"])
    }

    func testFolder() {
        // First folders after sorting inside each set: /a, /b, /c.
        XCTAssertEqual(ids(.folder, ascending: true), ["medium", "small", "big"])
        XCTAssertEqual(ids(.folder, ascending: false), ["big", "small", "medium"])
    }

    func testCopiesInsideASetAreSorted() {
        let byFolder = DuplicateSorter.sort(groups, by: .folder, ascending: true)
        XCTAssertEqual(
            byFolder.first { $0.id == "medium" }?.files.map(\.path),
            ["/a/copy of medium.doc", "/a/medium.doc", "/a/x/medium.doc", "/a/y/medium.doc"]
        )
        let byName = DuplicateSorter.sort(groups, by: .fileName, ascending: true)
        XCTAssertEqual(
            byName.first { $0.id == "big" }?.files.map(\.name),
            ["Another Big.pdf", "Big.pdf"]
        )
    }

    func testDefaultDirections() {
        XCTAssertFalse(DuplicateSortOrder.spaceToFree.defaultAscending)
        XCTAssertFalse(DuplicateSortOrder.fileSize.defaultAscending)
        XCTAssertTrue(DuplicateSortOrder.fileName.defaultAscending)
        XCTAssertTrue(DuplicateSortOrder.folder.defaultAscending)
    }
}
