import Foundation

/// Resolves the standard fixture sets that `scripts/make-fixture-sets` builds in
/// the shared cache outside the repository.
///
/// Tests that need a set gate themselves with
/// `@Test(.enabled(if: Fixtures.set("card-basic") != nil))`, so a machine that
/// has not run `mise run fixtures-sets` skips instead of failing.
public enum Fixtures {
    /// Environment variable that overrides the cache location.
    public static let directoryEnvironmentVariable = "CLOVE_FIXTURES_DIR"

    /// Default cache, next to the project on the T7 SSD.
    public static let defaultDirectory = URL(
        fileURLWithPath: "/Volumes/T7/Projects/.clove-fixtures",
        isDirectory: true
    )

    /// The cache directory for `environment`; `$CLOVE_FIXTURES_DIR` wins when set.
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[directoryEnvironmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return defaultDirectory
    }

    /// `sets/<name>` under `directory`, or `nil` when the set is missing.
    public static func set(_ name: String, directory: URL = Fixtures.directory()) -> URL? {
        let url =
            directory
            .appendingPathComponent("sets", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue ? url : nil
    }

    /// `sets/<name>` in the cache that `environment` selects, or `nil` when the
    /// set is missing.
    public static func set(_ name: String, environment: [String: String]) -> URL? {
        set(name, directory: directory(environment: environment))
    }
}
