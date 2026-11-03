import Foundation

public enum UserHome {
    /// The user's real home folder, such as /Users/alice.
    ///
    /// In a sandboxed app, `FileManager.homeDirectoryForCurrentUser` returns
    /// the app's container (~/Library/Containers/<bundle id>/Data), so read
    /// the password database instead.
    public static var directory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
