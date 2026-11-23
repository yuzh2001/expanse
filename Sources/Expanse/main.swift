import AppKit

/// "Expanse Dev" (DEV=1 in scripts/build.sh) sits beside the release with its own bundle id, so
/// its state is its own too: Application Support, Logs and preferences all apart.
enum Variant {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.invignation.expanse"
    static let isDev = bundleID == "com.invignation.expanse.dev"
    static let folderName = isDev ? "Expanse Dev" : "Expanse"
}

// One copy at a time, counting the release and "Expanse Dev" as the same app: two would fight
// over every window (each takes the other's moves for the user's and puts windows back). A second
// launch shows the running copy's welcome window and quits before touching anything.
if ["com.invignation.expanse", "com.invignation.expanse.dev"].contains(where: { id in
    NSRunningApplication.runningApplications(withBundleIdentifier: id)
        .contains { $0.processIdentifier != getpid() && !$0.isTerminated }
}) {
    // A distributed notification is handed over before we exit (opening a URL isn't).
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.invignation.expanse.showWelcome"),
                                                                 object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
