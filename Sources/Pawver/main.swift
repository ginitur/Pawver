import AppKit

// Menu-bar agent (LSUIElement in Info.plist; accessory policy as a fallback
// when the bare executable is launched outside the bundle).
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
