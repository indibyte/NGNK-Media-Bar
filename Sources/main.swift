// NGNK Media Bar: a full-width now-playing Touch Bar (Apple Music, YouTube, …) that opens over MTMR.
// Run with --install-mtmr-button / --remove-mtmr-button to edit MTMR's config (used by the scripts).
import AppKit

switch CommandLine.arguments.dropFirst().first {
case "--install-mtmr-button":
    exit(MTMR.installButton() ? 0 : 1)
case "--remove-mtmr-button":
    exit(MTMR.removeButton() ? 0 : 1)
default:
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
