import CryptoKit
import Foundation

public enum FileHasher {
    static let chunkSize = 1 << 20

    /// SHA-256 of the file contents as lowercase hex. When `maxBytes` is set,
    /// only the first `maxBytes` bytes are hashed.
    public static func sha256(of url: URL, maxBytes: Int? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = maxBytes ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let readMore: Bool = try autoreleasepool {
                let count = min(chunkSize, remaining)
                guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                    return false
                }
                hasher.update(data: data)
                remaining -= data.count
                return true
            }
            if !readMore { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
