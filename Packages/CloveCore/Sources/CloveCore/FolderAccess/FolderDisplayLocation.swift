import Foundation

/// Display-only locations for Recents, computed from existing records (PRD P0-02; handoff Entry).
/// Paths, volume names and these strings never establish identity or permission (G1 folder access).
public enum FolderDisplayLocation {
    /// A place followed by at most two folder names; `device` is supplied by the UI (PRD P0-02).
    public static func text(
        path: String, volumeName: String?, mediaType: FolderMediaType, device: String = "iPhone"
    ) -> String {
        let parts = path.split(separator: "/").map(String.init)
        var folders = parts
        var place: String?
        if let index = parts.firstIndex(of: "com~apple~CloudDocs") {
            place = "iCloud Drive"
            folders = Array(parts.dropFirst(index + 1))
        } else if let index = parts.firstIndex(of: "File Provider Storage") {
            place = "On My \(device)"
            folders = Array(parts.dropFirst(index + 1))
        } else if let index = parts.firstIndex(of: "LiveFiles") {
            place = safeName(volumeName)
            // LiveFiles is followed by an opaque mount identifier, never a display name.
            folders = Array(parts.dropFirst(index + 2))
        } else if let index = parts.firstIndex(of: "Documents"),
            parts.contains("Containers")
        {
            place = "On My \(device)"
            folders = Array(parts.dropFirst(index + 1))
        } else if mediaType == .externalDrive || mediaType == .cloudProvider {
            place = safeName(volumeName)
            if let index = parts.firstIndex(of: "Volumes") {
                folders = Array(parts.dropFirst(index + 2))
            }
        }
        let names = folders.compactMap(safeName).suffix(2)
        return ([place].compactMap { $0 } + names).joined(separator: " › ")
    }

    /// A last folder name suitable for an Entry title (PRD P0-02).
    public static func name(path: String) -> String {
        path.split(separator: "/").reversed().compactMap { safeName(String($0)) }.first ?? "Folder"
    }

    private static func safeName(_ value: String?) -> String? {
        guard let value, !value.isEmpty, UUID(uuidString: value) == nil,
            ![
                "private", "var", "mobile", "Containers", "Shared", "AppGroup", "Data",
                "Application", "Library", "LiveFiles", "File Provider Storage", "Mobile Documents",
                "com~apple~CloudDocs",
            ].contains(value),
            !value.contains("/"), !value.hasPrefix("com~"), !value.hasPrefix("group.")
        else { return nil }
        return value
    }
}
