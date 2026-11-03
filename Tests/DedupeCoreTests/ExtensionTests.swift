import XCTest
@testable import DedupeCore

final class ExtensionTests: XCTestCase {
    func testParserNormalizesInput() {
        let parsed = ExtensionParser.parse(" .DOCX, pdf;  *.key\ntar.gz  ")
        XCTAssertEqual(parsed, ["docx", "pdf", "key", "tar.gz"])
    }

    func testParserRejectsJunk() {
        XCTAssertEqual(ExtensionParser.parse(""), [])
        XCTAssertEqual(ExtensionParser.parse(". , ..  *"), [])
        XCTAssertEqual(ExtensionParser.parse("a/b doc"), ["doc"])
        XCTAssertEqual(ExtensionParser.parse("a..b"), [])
    }

    func testMatcherIgnoresCase() {
        let matcher = ExtensionMatcher(extensions: ["docx"])
        XCTAssertTrue(matcher.matches(fileName: "Report.DOCX"))
        XCTAssertTrue(matcher.matches(fileName: "report.docx"))
        XCTAssertFalse(matcher.matches(fileName: "report.doc"))
        XCTAssertFalse(matcher.matches(fileName: "docx"))
    }

    func testMatcherSupportsCompoundExtensions() {
        let matcher = ExtensionMatcher(extensions: ["tar.gz"])
        XCTAssertTrue(matcher.matches(fileName: "backup.tar.gz"))
        XCTAssertFalse(matcher.matches(fileName: "backup.gz"))
        XCTAssertFalse(matcher.matches(fileName: ".tar.gz"))
    }

    func testEveryCategoryHasLowercaseExtensions() {
        for category in FileTypeCategory.allCases {
            XCTAssertFalse(category.extensions.isEmpty, category.title)
            for ext in category.extensions {
                XCTAssertEqual(ext, ext.lowercased())
                XCTAssertFalse(ext.hasPrefix("."))
            }
        }
    }

    func testEveryCategoryBelongsToAGroup() {
        let grouped = FileTypeGroup.allCases.flatMap(\.categories)
        XCTAssertEqual(Set(grouped), Set(FileTypeCategory.allCases))
    }

    func testHasherMatchesKnownDigest() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString).txt")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(
            try FileHasher.sha256(of: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        // Hashing only the first byte gives the digest of "a".
        XCTAssertEqual(
            try FileHasher.sha256(of: url, maxBytes: 1),
            "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"
        )
    }
}
