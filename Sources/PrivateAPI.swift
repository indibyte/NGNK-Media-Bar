// Private macOS APIs, loaded at runtime. These are undocumented and may change between macOS releases.
import AppKit

private func load<T>(_ lib: String, _ name: String) -> T {
    unsafeBitCast(dlsym(dlopen(lib, RTLD_NOW), name), to: T.self)
}

private let dfrLib = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"

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
