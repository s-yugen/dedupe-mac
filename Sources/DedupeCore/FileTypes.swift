import Foundation

/// Sections used to group the predefined file types in the UI.
public enum FileTypeGroup: String, CaseIterable, Identifiable, Sendable {
    case documents
    case images
    case media
    case archives

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .documents: return "Documents"
        case .images: return "Images"
        case .media: return "Audio and video"
        case .archives: return "Archives and installers"
        }
    }

    public var categories: [FileTypeCategory] {
        FileTypeCategory.allCases.filter { $0.group == self }
    }
}

/// A predefined file type the user can tick instead of typing extensions.
public enum FileTypeCategory: String, CaseIterable, Identifiable, Sendable {
    case word
    case excel
    case powerpoint
    case pdf
    case iwork
    case text
    case images
    case rawPhotos
    case audio
    case video
    case archives
    case installers

    public var id: String { rawValue }

    public var group: FileTypeGroup {
        switch self {
        case .word, .excel, .powerpoint, .pdf, .iwork, .text: return .documents
        case .images, .rawPhotos: return .images
        case .audio, .video: return .media
        case .archives, .installers: return .archives
        }
    }

    public var title: String {
        switch self {
        case .word: return "Microsoft Word"
        case .excel: return "Microsoft Excel and CSV"
        case .powerpoint: return "Microsoft PowerPoint"
        case .pdf: return "PDF"
        case .iwork: return "Pages, Numbers, Keynote"
        case .text: return "Text and RTF"
        case .images: return "Photos and pictures"
        case .rawPhotos: return "Camera RAW"
        case .audio: return "Audio"
        case .video: return "Video"
        case .archives: return "Archives"
        case .installers: return "Disk images and installers"
        }
    }

    /// Extensions in display order, lowercase, without the leading dot.
    public var extensions: [String] {
        switch self {
        case .word: return ["doc", "docx", "docm", "dot", "dotx"]
        case .excel: return ["xls", "xlsx", "xlsm", "xlsb", "csv"]
        case .powerpoint: return ["ppt", "pptx", "pptm", "pps", "ppsx"]
        case .pdf: return ["pdf"]
        case .iwork: return ["pages", "numbers", "key"]
        case .text: return ["txt", "rtf", "md"]
        case .images: return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp"]
        case .rawPhotos: return ["cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2"]
        case .audio: return ["mp3", "m4a", "wav", "aac", "flac", "aif", "aiff", "ogg"]
        case .video: return ["mp4", "mov", "m4v", "avi", "mkv", "wmv", "webm"]
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
        case .installers: return ["dmg", "pkg", "iso"]
        }
    }

    public var extensionsLabel: String {
        extensions.joined(separator: ", ")
    }
}

/// Turns free text such as ".DOCX, pdf; *.key tar.gz" into a set of
/// normalized extensions: lowercase, no leading dot or wildcard.
public enum ExtensionParser {
    public static func parse(_ input: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",; \t\n\r")
        var result = Set<String>()
        for raw in input.components(separatedBy: separators) {
            var token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while token.hasPrefix("*") || token.hasPrefix(".") {
                token.removeFirst()
            }
            while token.hasSuffix(".") {
                token.removeLast()
            }
            guard !token.isEmpty, token.allSatisfy(isAllowed) else { continue }
            guard !token.contains("..") else { continue }
            result.insert(token)
        }
        return result
    }

    private static func isAllowed(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
    }
}

/// Checks file names against a set of extensions. Supports compound
/// extensions such as "tar.gz". Matching ignores case.
public struct ExtensionMatcher: Sendable {
    private let simple: Set<String>
    private let compound: [String]

    public init(extensions: Set<String>) {
        let normalized = extensions.map { $0.lowercased() }
        simple = Set(normalized.filter { !$0.contains(".") })
        compound = normalized.filter { $0.contains(".") }.map { "." + $0 }
    }

    public var isEmpty: Bool { simple.isEmpty && compound.isEmpty }

    public func matches(fileName: String) -> Bool {
        let lower = fileName.lowercased()
        if let dot = lower.lastIndex(of: "."), dot != lower.startIndex {
            let ext = String(lower[lower.index(after: dot)...])
            if simple.contains(ext) { return true }
        }
        return compound.contains { lower.count > $0.count && lower.hasSuffix($0) }
    }
}
