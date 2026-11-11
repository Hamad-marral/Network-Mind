import Foundation

/// File locations inside the app container.
enum StoragePaths {
    /// `Application Support/Recordings`. Created on demand with
    /// `completeUntilFirstUserAuthentication` protection: files are encrypted at rest, but
    /// remain writable while the phone is locked during Event Mode (`.complete` would make
    /// writes fail as soon as the screen locks).
    static var recordingsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Recordings", isDirectory: true)
        ensureDirectory(url)
        return url
    }

    static var exportsDirectory: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        ensureDirectory(url)
        return url
    }

    private static func ensureDirectory(_ url: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try? fm.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        // Raw audio is private and short-lived: keep it out of iCloud/device backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }
}
