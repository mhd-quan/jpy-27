import Foundation

/// The file an album page's picture is kept in (the app's `PhotoCache.ambient`, in `Caches/Ambient`): named after
/// the picture's key (the photograph and the box it fills) and the app's build. Caches outlive an update, and a new
/// build may compose differently or ship a photograph re-cut under the same name, so a new build never reads a
/// picture an older one composed: it composes its own, under a new name.
public enum AmbientFile {
    /// "a1-<base 36>.heic": HEIC, or JPEG under the same name where HEIC cannot be written (ImageIO reads an image by
    /// its content). "a1" is the way pictures are composed: bumped, it names every picture anew within one build.
    public static func name(key: String, build: String) -> String {
        var f = SnapshotKey.Fingerprint()
        f.add(key)
        f.add(build)
        return "a1-" + String(f.value, radix: 36) + ".heic"
    }
}
