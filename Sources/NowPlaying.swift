import AppKit
import AudioToolbox
import CoreAudio

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

// System output volume (0–100) of the default output device, via CoreAudio.
enum Volume {
    static func get() -> Double { read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, as: Float32.self).map { Double($0) * 100 } ?? 50 }

    static var muted: Bool { read(kAudioDevicePropertyMute, as: UInt32.self) == 1 }

    /// Sets the level and unmutes, so moving the slider is always audible (like the volume keys).
    static func set(_ value: Double) {
        write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(value / 100))
        write(kAudioDevicePropertyMute, UInt32(0))
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var device: AudioDeviceID? {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr ? id : nil
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector, as _: T.Type) -> T? {
        guard let dev = device else { return nil }
        var a = address(selector), size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, value) == noErr ? value.pointee : nil
    }

    private static func write<T>(_ selector: AudioObjectPropertySelector, _ value: T) {
        guard let dev = device else { return }
        var a = address(selector), v = value
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }
}
