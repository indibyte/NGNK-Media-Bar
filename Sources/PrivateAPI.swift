// Private macOS APIs, loaded at runtime. These are undocumented and may change between macOS releases.
import AppKit

private func load<T>(_ lib: String, _ name: String) -> T {
    unsafeBitCast(dlsym(dlopen(lib, RTLD_NOW), name), to: T.self)
}

private let mrLib = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
private let dfrLib = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"

// MediaRemote: system-wide Now Playing info and transport commands. Needs no Apple Events permission.
enum MediaRemote {
    enum Command: UInt32 { case togglePlayPause = 2, nextTrack = 4, previousTrack = 5 }

    static let send: @convention(c) (UInt32, CFDictionary?) -> Bool = load(mrLib, "MRMediaRemoteSendCommand")
    static let getInfo: @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void =
        load(mrLib, "MRMediaRemoteGetNowPlayingInfo")
    static let getAppPID: @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void =
        load(mrLib, "MRMediaRemoteGetNowPlayingApplicationPID")

    static func send(_ command: Command) { _ = send(command.rawValue, nil) }
}

// DFRFoundation: hides the system close box on system-modal Touch Bars (we draw our own).
let setSystemModalShowsCloseBox: @convention(c) (Bool) -> Void = load(dfrLib, "DFRSystemModalShowsCloseBoxWhenFrontMost")

// System-modal Touch Bar: shown over every app, including MTMR's bar.
extension NSTouchBar {
    // Placement 1 = full width, covering the Control Strip.
    static func presentFullWidth(_ bar: NSTouchBar) {
        let sel = Selector(("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:"))
        typealias Fn = @convention(c) (AnyObject, Selector, NSTouchBar, Int64, NSString?) -> Void
        unsafeBitCast((NSTouchBar.self as AnyObject).method(for: sel), to: Fn.self)(NSTouchBar.self, sel, bar, 1, nil)
    }

    static func dismissSystemModal(_ bar: NSTouchBar) {
        _ = (NSTouchBar.self as AnyObject).perform(Selector(("dismissSystemModalTouchBar:")), with: bar)
    }
}
