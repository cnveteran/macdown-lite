import AppKit

// Programmatic AppKit app: no nib, no storyboard.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
