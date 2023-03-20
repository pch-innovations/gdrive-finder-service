import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// This open the service port so that the app will react to
// the service call requests configured in the .plist file
NSApp.servicesProvider = delegate
NSUpdateDynamicServices()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
