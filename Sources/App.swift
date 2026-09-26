import AppKit

extension NSTouchBarItem.Identifier {
    static let close = Self("ngnk.mediabar.close"), art = Self("ngnk.mediabar.art"),
               marquee = Self("ngnk.mediabar.marquee"), eq = Self("ngnk.mediabar.eq"),
               prev = Self("ngnk.mediabar.prev"), play = Self("ngnk.mediabar.play"),
               next = Self("ngnk.mediabar.next"), volume = Self("ngnk.mediabar.volume")
}

final class App: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    private let bar = NSTouchBar()
    private let art = ArtView(width: 120)
    private let marquee = MarqueeView(width: 320)
    private let eq = EQView(width: 150, count: 18)
    private let levels = SimulatedLevels(count: 18)
    private lazy var playButton = button("play.fill", #selector(togglePlayPause))
    private let volume = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var state = NowPlaying()
    private var isOpen = false
    private var eqTimer: Timer?

    // MTMR button sync: an MTMR reload would cover this bar, so updates wait until it's closed.
    private var mtmrSummary: String?
    private var mtmrPending = false
    private var mtmrChangedAt = Date()

    func applicationDidFinishLaunching(_: Notification) {
        setSystemModalShowsCloseBox(false)
        bar.delegate = self
        bar.defaultItemIdentifiers = [.close, .art, .marquee, .eq, .prev, .play, .next, .flexibleSpace, .volume]
        volume.widthAnchor.constraint(equalToConstant: 130).isActive = true
        volume.target = self
        volume.action = #selector(volumeChanged)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    // mediabar://show opens the bar; mediabar://close closes it.
    func application(_: NSApplication, open urls: [URL]) {
        urls.last?.host == "close" ? close() : show()
    }

    private func show() {
        isOpen = true
        volume.doubleValue = Volume.get()
        NSTouchBar.presentFullWidth(bar)
        eqTimer?.invalidate()
        eqTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.eq.update(self.levels.next(playing: self.state.playing))
        }
        refresh()
    }

    @objc private func close() {
        isOpen = false
        eqTimer?.invalidate()
        NSTouchBar.dismissSystemModal(bar)
        refresh()   // flush any MTMR update held while open
    }

    private func refresh() {
        NowPlaying.fetch { [weak self] np in
            guard let self = self else { return }
            self.syncMTMR(np)
            guard np != self.state else { return }
            if np.art != self.state.art || np.title != self.state.title { self.art.set(np.art) }
            self.state = np
            self.marquee.set(title: np.title, artist: np.artist)
            self.art.setPlaying(np.playing)
            self.playButton.image = NSImage(systemSymbolName: np.playing ? "pause.fill" : "play.fill",
                                            accessibilityDescription: nil)
        }
    }

    private func syncMTMR(_ np: NowPlaying) {
        if np.summary != mtmrSummary {
            mtmrSummary = np.summary
            mtmrPending = true
            mtmrChangedAt = Date()
        }
        // Art often lags the title; wait up to 3s for it so each track costs one MTMR reload.
        guard mtmrPending, !isOpen,
              np.art != nil || np.summary.isEmpty || Date().timeIntervalSince(mtmrChangedAt) > 3 else { return }
        mtmrPending = false
        MTMR.update(np)
    }

    @objc private func togglePlayPause() {
        MediaRemote.send(.togglePlayPause)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    @objc private func nextTrack() { MediaRemote.send(.nextTrack) }
    @objc private func previousTrack() { MediaRemote.send(.previousTrack) }
    @objc private func volumeChanged() { Volume.set(volume.doubleValue) }

    private func button(_ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!, target: self, action: action)
        b.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return b
    }

    private func volumeView() -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .white
        return NSStackView(views: [icon, volume])
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
