import AppKit

if CommandLine.arguments.contains("--dump") {
    Diagnostics.dump()
    exit(0)
}

// `ManyDisplays --save` / `--restore` talk to the running instance (handy for Shortcuts/Raycast).
for (flag, name) in [("--save", RemoteCommand.save), ("--restore", RemoteCommand.restore),
                     ("--preview-overlay", RemoteCommand.previewOverlay)]
where CommandLine.arguments.contains(flag) {
    DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// Only one instance.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, never in the Dock
app.run()
