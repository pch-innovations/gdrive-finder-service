import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

NSApp.servicesProvider = delegate
NSUpdateDynamicServices()

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
