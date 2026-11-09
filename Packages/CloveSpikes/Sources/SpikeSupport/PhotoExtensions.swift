/// HEIF still-image extensions, including camera files from Sony, Canon and Fujifilm.
/// Callers lowercase the extension before testing membership.
public enum PhotoExtensions {
    public static let heif: Set<String> = ["heic", "heif", "hif"]
}
