# NGNK Media Bar

A full-width Apple Music Touch Bar for [MTMR](https://github.com/Toxblh/MTMR).

MTMR shows a now-playing button (album art and title) on your main bar. Tap it to open the media bar:

- album art that scrolls top to bottom, pausing with playback
- title and artist, scrolling when too long
- rainbow EQ animation
- previous / play-pause / next
- volume slider
- ✕ to return to MTMR

The media bar stays open across track changes.

## Requirements

- A MacBook Pro with a Touch Bar, macOS 11 or later (tested on macOS 13)
- [MTMR](https://github.com/Toxblh/MTMR), run at least once
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```sh
git clone https://github.com/indibyte/NGNK-Media-Bar.git
cd NGNK-Media-Bar
scripts/install.sh
```

The installer:

1. builds `~/Applications/NGNK Media Bar.app`
2. backs up `~/Library/Application Support/MTMR/items.json`, then adds the now-playing button after the dock (or first)
3. adds a login item (`~/Library/LaunchAgents/com.ngnk.mediabar.plist`) so the app is always running

Re-run it after pulling changes. To remove everything: `scripts/uninstall.sh`.

## How it works

- **Now playing** comes from macOS's system-wide Now Playing info (the private MediaRemote framework). This needs no Automation permission, which MTMR often can't get.
- **The media bar** is a system-modal Touch Bar shown over MTMR's bar. MTMR's button opens it with `mediabar://show`; `mediabar://close` closes it.
- **MTMR's button** only reads its image when MTMR loads its config. So on each track change the app saves the art to `~/Library/Application Support/NGNK Media Bar/art.png` and sets the button's title in `items.json`, and MTMR reloads. While the media bar is open, those updates wait until it closes, since a reload would cover it.

The button the installer adds:

```json
{
  "type": "staticButton",
  "title": "♪",
  "image": { "filePath": "~/Library/Application Support/NGNK Media Bar/art.png" },
  "action": "openUrl",
  "url": "mediabar://show"
}
```

(The installer writes the full path; MTMR doesn't expand `~`.)

## Limitations

- **Private APIs.** MediaRemote and the system-modal Touch Bar calls are undocumented, so a macOS update could break them.
- **The EQ is simulated.** It animates while music plays and settles when paused, but doesn't react to the audio.
- **Apple Music only.** Other players are ignored.
- **MTMR's button art is small and static** (MTMR caps images at about 24pt). The large, animated art is on the media bar.
- **MTMR's bar redraws once per track change**, because that's the only way MTMR picks up a new image.
- The installer rewrites `items.json` through a JSON serializer, so key order and formatting change (content doesn't). A backup is saved first.

## Development

```sh
scripts/build.sh    # builds build/NGNK Media Bar.app
```

Sources:

| File | Purpose |
| --- | --- |
| `Sources/main.swift` | Entry point; `--install-mtmr-button` / `--remove-mtmr-button` for the scripts |
| `Sources/App.swift` | App delegate and Touch Bar layout |
| `Sources/Views.swift` | Album art, marquee and EQ views |
| `Sources/NowPlaying.swift` | Now-playing state and system volume |
| `Sources/MTMR.swift` | MTMR button sync and config edits |
| `Sources/PrivateAPI.swift` | MediaRemote and Touch Bar private APIs |

## License

MIT
