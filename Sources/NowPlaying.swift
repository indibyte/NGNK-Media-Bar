import AppKit

struct NowPlaying: Equatable {
    var title = "", artist = "", playing = false, art: Data? = nil

    /// "Artist – Title", or "" when nothing is playing.
    var summary: String { artist.isEmpty ? title : "\(artist) – \(title)" }

    /// Fetches Apple Music's now-playing state; empty when another app (or nothing) is the now-playing source.
    static func fetch(_ done: @escaping (NowPlaying) -> Void) {
        MediaRemote.getAppPID(.main) { pid in
            MediaRemote.getInfo(.main) { cf in
                let info = (cf as? [String: Any]) ?? [:], k = "kMRMediaRemoteNowPlayingInfo"
                guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.Music",
                      let title = info[k + "Title"] as? String else { return done(NowPlaying()) }
                done(NowPlaying(title: title,
                                artist: info[k + "Artist"] as? String ?? "",
                                playing: (info[k + "PlaybackRate"] as? Double ?? 0) > 0,
                                art: info[k + "ArtworkData"] as? Data))
            }
        }
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
