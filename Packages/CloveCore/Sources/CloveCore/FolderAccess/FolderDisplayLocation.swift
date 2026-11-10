import Foundation

/// Display-only locations for Recents, computed from existing records (PRD P0-02; handoff Entry).
/// Paths, volume names and these strings never establish identity or permission (G1 folder access).
public enum FolderDisplayLocation {
    /// A place followed by at most two user folder names (PRD P0-02).
    /// System components are stripped before the storage anchor, never from user folder names.
    public static func text(
        path: String, volumeName: String?, mediaType: FolderMediaType, device: String = "iPhone"
    ) -> String {
        let location = location(path: path, device: device)
        let place =
            location.place
            ?? ((mediaType == .externalDrive || mediaType == .cloudProvider)
                ? displayVolume(volumeName) : nil)
        return ([place].compactMap { $0 } + location.folders.suffix(2)).joined(separator: " › ")
    }

    /// The last user folder name, including names such as Shared or Library (PRD P0-02).
    public static func name(path: String) -> String {
        let location = location(path: path, device: "iPhone")
        return location.folders.last ?? "Folder"
    }

    private static func location(path: String, device: String) -> (
        place: String?, folders: [String]
    ) {
        let parts = path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "com~apple~CloudDocs") {
            return ("iCloud Drive", Array(parts.dropFirst(index + 1)))
        }
        if let index = parts.firstIndex(of: "File Provider Storage") {
            return ("On My \(device)", Array(parts.dropFirst(index + 1)))
        }
        if let index = parts.firstIndex(of: "LiveFiles"),
            index > 0, parts[index - 1] == "Library"
        {
            // LiveFiles is followed by the system's opaque mount identifier.
            return (nil, Array(parts.dropFirst(index + 2)))
        }
        if let index = parts.firstIndex(of: "Documents"), parts.contains("Containers") {
            return ("On My \(device)", Array(parts.dropFirst(index + 1)))
        }
        if parts.first == "Volumes" {
            return (nil, Array(parts.dropFirst(parts.count > 2 ? 2 : 1)))
        }
        var folders = parts
        if folders.starts(with: ["private", "var", "mobile"]) {
            folders.removeFirst(3)
        } else if folders.starts(with: ["var", "mobile"]) {
            folders.removeFirst(2)
        }
        if folders.first == "Containers",
            let identifier = folders.firstIndex(where: { UUID(uuidString: $0) != nil })
        {
            folders = Array(folders.dropFirst(identifier + 1))
        }
        return (nil, folders.filter { UUID(uuidString: $0) == nil })
    }

    private static func displayVolume(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.contains("/"), UUID(uuidString: value) == nil,
            value != "File Provider Storage", value != "com~apple~CloudDocs"
        else { return nil }
        return value
    }
}
