import AppKit

struct NowPlaying: Equatable {
    var title = "", artist = "", playing = false, art: Data? = nil

    /// "Artist – Title", or "" when nothing is playing.
    var summary: String { artist.isEmpty ? title : "\(artist) – \(title)" }

    /// Fetches the system Now Playing state from whichever app owns it (Apple Music, a browser playing
    /// YouTube, etc.). Without artwork: YouTube's thumbnail for Firefox tabs, otherwise the app's icon.
    static func fetch(_ done: @escaping (NowPlaying) -> Void) {
        MediaRemote.getAppPID(.main) { pid in
            MediaRemote.getIsPlaying(.main) { playing in
                MediaRemote.getInfo(.main) { cf in
                    let info = (cf as? [String: Any]) ?? [:], k = "kMRMediaRemoteNowPlayingInfo"
                    guard let title = info[k + "Title"] as? String, !title.isEmpty else { return done(NowPlaying()) }
                    var art = info[k + "ArtworkData"] as? Data
                    if art == nil, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == FirefoxYouTube.bundleID {
                        let thumb = FirefoxYouTube.thumbnail(for: title)
                        art = thumb.data
                        if art == nil, !thumb.pending { art = appIcon(pid) }   // blank tile while still looking
                    } else if art == nil {
                        art = appIcon(pid)
                    }
                    done(NowPlaying(title: title, artist: info[k + "Artist"] as? String ?? "", playing: playing, art: art))
                }
            }
        }
    }

    private static var iconCache: [String: Data] = [:]

    private static func appIcon(_ pid: Int32) -> Data? {
        guard let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
              let icon = app.icon else { return nil }
        if let cached = iconCache[id] { return cached }
        icon.size = NSSize(width: 256, height: 256)
        let data = icon.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:])
        iconCache[id] = data
        return data
    }
}

// System output volume via an in-process scripting addition (no Apple Events permission needed).
enum Volume {
    static func get() -> Double {
        NSAppleScript(source: "output volume of (get volume settings)")?.executeAndReturnError(nil).doubleValue ?? 50
    }

    static var muted: Bool {
        NSAppleScript(source: "output muted of (get volume settings)")?.executeAndReturnError(nil).booleanValue ?? false
    }

    /// Sets the level and unmutes, so moving the slider is always audible (like the volume keys).
    static func set(_ value: Double) {
        NSAppleScript(source: "set volume output volume \(Int(value)) without output muted")?.executeAndReturnError(nil)
    }
}
