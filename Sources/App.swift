import AppKit

extension NSTouchBarItem.Identifier {
    static let close = Self("ngnk.mediabar.close"), art = Self("ngnk.mediabar.art"),
               marquee = Self("ngnk.mediabar.marquee"), eq = Self("ngnk.mediabar.eq"),
               prev = Self("ngnk.mediabar.prev"), play = Self("ngnk.mediabar.play"),
               next = Self("ngnk.mediabar.next"), volume = Self("ngnk.mediabar.volume")
}

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let bar = NSTouchBar()
    private let art = ArtView(width: 240)
    private let marquee = MarqueeView(width: 200)
    private let eq = EQView(width: 150, count: 18)
    private let levels = SimulatedLevels(count: 18)
    private lazy var playButton = button("play.fill", #selector(togglePlayPause))
    private let volume = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var state = NowPlaying()
    private var isOpen = false
    private var wasPlaying = false
    private var idleSince: Date?   // while open: when we first saw nothing playing
    private let volumeIcon = NSImageView()
    private var volumeTouchedAt = Date.distantPast
    private var eqTimer: Timer?
    private var volumeTimer: Timer?

    // MTMR button sync: an MTMR reload would cover this bar, so updates wait until it's closed.
    private var mtmrSummary: String?
    private var mtmrArt: Data?
    private var mtmrPending = false
    private var mtmrChangedAt = Date()

    func applicationDidFinishLaunching(_: Notification) {
        setSystemModalShowsCloseBox(false)
        bar.delegate = self
        bar.defaultItemIdentifiers = [.close, .art, .marquee, .eq, .prev, .play, .next, .volume]
        // The slider takes whatever width is left at the end of the bar.
        volume.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        volume.setContentHuggingPriority(.defaultLow, for: .horizontal)
        volume.target = self
        volume.action = #selector(volumeChanged)
        MediaRemote.start()
        // Pick up the helper's latest state (and Firefox thumbnails) once a second.
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        NotificationCenter.default.addObserver(forName: FirefoxYouTube.didLoad, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()

        // MTMR re-presents its own bar on app switches/launches (and wake/unlock), covering ours; take the
        // Touch Bar back. MTMR can re-present a second or two later while an app is launching, so check again.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                for delay in [0.3, 1.0, 2.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard let self = self, self.isOpen else { return }
                        self.present()
                    }
                }
            }
        }
    }

    // mediabar://show | close | toggle | next | prev
    func application(_: NSApplication, open urls: [URL]) {
        switch urls.last?.host {
        case "close": close()
        case "toggle": togglePlayPause()
        case "next": nextTrack()
        case "prev": previousTrack()
        default: show()
        }
    }

    private func show() {
        isOpen = true
        idleSince = nil
        present()
        syncVolume()
        volumeTimer?.invalidate()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.syncVolume() }
        eqTimer?.invalidate()
        eqTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.eq.update(self.levels.next(playing: self.state.playing))
        }
        refresh()
    }

    // Dismiss first: presenting a bar that's already in the system-modal stack doesn't bring it to the front.
    private func present() {
        NSTouchBar.dismissSystemModal(bar)
        NSTouchBar.presentFullWidth(bar)
    }

    @objc private func close() {
        isOpen = false
        eqTimer?.invalidate()
        volumeTimer?.invalidate()
        NSTouchBar.dismissSystemModal(bar)
        refresh()   // flush any MTMR update held while open
    }

    private func refresh() {
        NowPlaying.fetch { [weak self] np in
            guard let self = self else { return }
            self.autoOpenClose(playing: np.playing)
            self.syncMTMR(np)
            guard np != self.state else { return }
            if np.art != self.state.art || np.title != self.state.title {
                self.art.set(np.art)
                // Decoding a new track's artwork briefly uses a few MB; hand those pages back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { malloc_zone_pressure_relief(nil, 0) }
            }
            self.state = np
            self.marquee.set(title: np.title, artist: np.artist)
            self.art.setPlaying(np.playing)
            self.playButton.image = NSImage(systemSymbolName: np.playing ? "pause.fill" : "play.fill",
                                            accessibilityDescription: nil)
        }
    }

    /// Opens when playback starts and closes after 5s with nothing playing. Opening only on a start means
    /// ✕ while playing keeps the bar closed until playback stops and starts again.
    private func autoOpenClose(playing: Bool) {
        defer { wasPlaying = playing }
        if playing {
            idleSince = nil
            if !wasPlaying, !isOpen { show() }
        } else if isOpen {
            let since = idleSince ?? Date()
            idleSince = since
            if Date().timeIntervalSince(since) >= 5 { close() }
        }
    }

    private func syncMTMR(_ np: NowPlaying) {
        if np.summary != mtmrSummary {
            mtmrSummary = np.summary
            mtmrPending = true
            mtmrChangedAt = Date()
        } else if np.art != mtmrArt {   // art arrived (or changed) after the title was synced
            mtmrPending = true
        }
        // Art often lags the title; wait up to 3s for it so each track costs one MTMR reload.
        guard mtmrPending, !isOpen,
              np.art != nil || np.summary.isEmpty || Date().timeIntervalSince(mtmrChangedAt) > 3 else { return }
        mtmrPending = false
        mtmrArt = np.art
        MTMR.update(np)
    }

    @objc private func togglePlayPause() {
        MediaRemote.send(.togglePlayPause)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    @objc private func nextTrack() { MediaRemote.send(.nextTrack) }
    @objc private func previousTrack() { MediaRemote.send(.previousTrack) }
    @objc private func volumeChanged() {
        volumeTouchedAt = Date()
        Volume.set(volume.doubleValue)
        volumeIcon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
    }

    // Follow volume-key and menu-bar changes, but not mid-drag.
    private func syncVolume() {
        guard isOpen, Date().timeIntervalSince(volumeTouchedAt) > 1.5 else { return }
        volume.doubleValue = Volume.get()
        let symbol = Volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        volumeIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func button(_ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: action)
        b.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return b
    }

    private func volumeView() -> NSView {
        volumeIcon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        volumeIcon.contentTintColor = .white
        volumeIcon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return NSStackView(views: [volumeIcon, volume])
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier id: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let views: [NSTouchBarItem.Identifier: () -> NSView] = [
            .close: { self.button("xmark", #selector(self.close)) },
            .art: { self.art },
            .marquee: { self.marquee },
            .eq: { self.eq },
            .prev: { self.button("backward.fill", #selector(self.previousTrack)) },
            .play: { self.playButton },
            .next: { self.button("forward.fill", #selector(self.nextTrack)) },
            .volume: { self.volumeView() },
        ]
        guard let view = views[id] else { return nil }
        let item = NSCustomTouchBarItem(identifier: id)
        item.view = view()
        return item
    }
}
