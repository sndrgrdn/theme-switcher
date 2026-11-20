import AppKit

if let status = CLI.run(CommandLine.arguments) { exit(status) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
