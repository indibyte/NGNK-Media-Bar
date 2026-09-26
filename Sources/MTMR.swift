// Keeps the now-playing button on MTMR's main bar current, and installs/removes that button.
// MTMR only reads images when it loads its config, so on each track change we save the album art to
// `artPath`, set the button title in items.json, and the write makes MTMR reload.
import AppKit

enum MTMR {
    static let supportDir = NSHomeDirectory() + "/Library/Application Support/NGNK Media Bar"
    static let artPath = supportDir + "/art.png"
    static let configPath = NSHomeDirectory() + "/Library/Application Support/MTMR/items.json"
    static let showURL = "mediabar://show"

    static var button: [String: Any] {
        ["type": "staticButton", "title": "♪", "image": ["filePath": artPath], "action": "openUrl", "url": showURL]
    }

    /// Saves the art and sets the button title; MTMR reloads its bar as a result.
    static func update(_ np: NowPlaying) {
        saveArt(np.art)
        let text = np.summary
        let title = text.isEmpty ? "♪" : (text.count > 28 ? String(text.prefix(27)) + "…" : text)
        editConfig { items in
            for i in items.indices where isOurButton(items[i]) { items[i]["title"] = title }
        }
    }

    /// Adds the button after the dock (or first), replacing any existing one. Returns false if MTMR's config is missing.
    @discardableResult
    static func installButton() -> Bool {
        editConfig { items in
            let at = items.firstIndex(where: isOurButton)
                ?? items.firstIndex(where: { $0["type"] as? String == "dock" }).map { $0 + 1 } ?? 0
            items.removeAll(where: isOurButton)
            items.insert(button, at: min(at, items.count))
        }
    }

    @discardableResult
    static func removeButton() -> Bool { editConfig { $0.removeAll(where: isOurButton) } }

    private static func isOurButton(_ item: [String: Any]) -> Bool { item["url"] as? String == showURL }

    private static func saveArt(_ data: Data?) {
        try? FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        guard let data = data, let img = NSImage(data: data) else {
            try? FileManager.default.removeItem(atPath: artPath); return
        }
        let px = 64
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.current = nil
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: artPath))
    }

    // Writes in place (same file) so MTMR's file watcher sees the change.
    @discardableResult
    private static func editConfig(_ edit: (inout [[String: Any]]) -> Void) -> Bool {
        guard let data = FileManager.default.contents(atPath: configPath),
              var items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return false }
        edit(&items)
        guard let out = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .withoutEscapingSlashes]),
              let file = FileHandle(forUpdatingAtPath: configPath) else { return false }
        file.truncateFile(atOffset: 0)
        file.write(out)
        file.closeFile()
        return true
    }
}
