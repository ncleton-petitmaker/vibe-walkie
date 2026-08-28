import AppKit

enum InstallationLocation {
    static var isSuitable: Bool {
#if DEBUG
        true
#else
        let path = Bundle.main.bundleURL.standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
#endif
    }

    static func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }
}
