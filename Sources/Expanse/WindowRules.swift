import Foundation

/// A rule deciding that an app's new windows float over the layout instead of joining it (see
/// CanvasController.arrive): transient utilities — a Settings pane, the WeChat image viewer —
/// you glance at and close, never file into a row.
struct FloatRule: Codable, Equatable {
    /// The app's bundle identifier.
    var bundleID: String
    /// Its name, for a list of rules.
    var appName: String
    /// A regular expression the window's title must match; nil matches every title.
    var titlePattern: String? = nil
    /// Match only when the app already has a window (the new one isn't its main window, then):
    /// WeChat's viewers and panels, never the WeChat window itself.
    var nonMainOnly = false
    var enabled = true
}

enum WindowRules {
    /// The built-in table, after Tangrid's predefined set of floating rules: utilities and
    /// previews you open briefly and drop. Edited rules are stored under `rulesKey`.
    static let builtIn: [FloatRule] = [
        FloatRule(bundleID: "com.apple.systempreferences", appName: "System Settings"),
        FloatRule(bundleID: "com.apple.finder", appName: "Finder"),
        FloatRule(bundleID: "com.apple.Preview", appName: "Preview"),
        FloatRule(bundleID: "com.apple.calculator", appName: "Calculator"),
        FloatRule(bundleID: "com.apple.archiveutility", appName: "Archive Utility"),
        FloatRule(bundleID: "com.apple.AppStore", appName: "App Store"),
        FloatRule(bundleID: "com.apple.installer", appName: "Installer"),
        FloatRule(bundleID: "com.apple.ActivityMonitor", appName: "Activity Monitor"),
        FloatRule(bundleID: "com.apple.PhotoBooth", appName: "Photo Booth"),
        FloatRule(bundleID: "com.apple.DiskUtility", appName: "Disk Utility"),
        FloatRule(bundleID: "com.tencent.xinWeChat", appName: "WeChat", nonMainOnly: true),
    ]

    /// The rules as a JSON array in defaults; absent or unreadable, the built-in table.
    static let rulesKey = "floatingRules"

    static var rules: [FloatRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: rulesKey),
                  let rules = try? JSONDecoder().decode([FloatRule].self, from: data)
            else { return builtIn }
            return rules
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: rulesKey)
        }
    }

    /// Whether a new window floats: its app matches an enabled rule, a title pattern (if any)
    /// matches its title, and a non-main rule matches only when the app has another window
    /// already (`hasSibling`), so the app's first window is taken for its main one.
    static func floats(bundleID: String, title: String, hasSibling: Bool,
                       rules: [FloatRule]? = nil) -> Bool {
        (rules ?? self.rules).contains { r in
            r.enabled && r.bundleID == bundleID
                && (!r.nonMainOnly || hasSibling)
                && (r.titlePattern.map { title.range(of: $0, options: .regularExpression) != nil } ?? true)
        }
    }
}
