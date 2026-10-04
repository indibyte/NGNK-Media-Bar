// Firefox doesn't always pass YouTube's artwork to Now Playing. This finds the playing video's tab in
// Firefox's session file (saved about every 15s), takes the video ID from its URL, and downloads
// YouTube's thumbnail. Everything is read locally; only the thumbnail is fetched.
import Compression
import Foundation

enum FirefoxYouTube {
    static let bundleID = "org.mozilla.firefox"

    /// Posted when a thumbnail finishes downloading, so the bar can pick it up.
    static let didLoad = Notification.Name("ngnk.mediabar.thumbnailDidLoad")

    private static var thumbnails: [String: Data] = [:]   // video ID -> thumbnail
    private static var ids: [String: String] = [:]        // title -> video ID
    private static var loading: Set<String> = []
    private static var firstSeen: [String: Date] = [:]    // title -> when we started looking
    private static var tabs: [(title: String, url: String)] = []
    private static var sessionDate: Date?

    /// The thumbnail for the video titled `title`. `pending` is true while it may still arrive
    /// (download in flight, or the tab not saved yet); false means there's no matching YouTube tab.
    static func thumbnail(for title: String) -> (data: Data?, pending: Bool) {
        if let id = ids[title], let data = thumbnails[id] { return (data, false) }
        let seen = firstSeen[title] ?? Date()
        firstSeen[title] = seen
        reloadTabsIfChanged()   // only while unresolved: the session file is large
        guard let id = videoID(for: title) else { return (nil, Date().timeIntervalSince(seen) < 20) }
        ids[title] = id
        if let data = thumbnails[id] { return (data, false) }
        download(id)
        return (nil, true)
    }

    private static func videoID(for title: String) -> String? {
        guard let tab = tabs.first(where: { $0.title.contains(title) }),
              let url = URLComponents(string: tab.url), url.host?.hasSuffix("youtube.com") == true else { return nil }
        if url.path == "/watch" { return url.queryItems?.first(where: { $0.name == "v" })?.value }
        if url.path.hasPrefix("/shorts/") { return url.path.split(separator: "/").last.map(String.init) }
        return nil
    }

    private static func download(_ id: String) {
        guard !loading.contains(id), let url = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") else { return }
        loading.insert(id)
        URLSession.shared.dataTask(with: url) { data, response, _ in
            DispatchQueue.main.async {
                loading.remove(id)
                if let data = data, (response as? HTTPURLResponse)?.statusCode == 200 {
                    thumbnails[id] = data
                    NotificationCenter.default.post(name: didLoad, object: nil)
                }
            }
        }.resume()
    }

    // MARK: Session file (mozLz4: "mozLz40\0", little-endian UInt32 size, then a raw LZ4 block)

    private static func reloadTabsIfChanged() {
        guard let file = latestSessionFile(),
              let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              date != sessionDate else { return }
        sessionDate = date
        autoreleasepool { parseSession(file) }
    }

    private static func parseSession(_ file: URL) {
        guard let raw = try? Data(contentsOf: file), let json = decompress(raw),
              let session = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let windows = session["windows"] as? [[String: Any]] else { return }
        tabs = windows.flatMap { ($0["tabs"] as? [[String: Any]]) ?? [] }.compactMap { tab in
            guard let entries = tab["entries"] as? [[String: Any]], !entries.isEmpty else { return nil }
            let entry = entries[min(max((tab["index"] as? Int ?? entries.count) - 1, 0), entries.count - 1)]
            guard let title = entry["title"] as? String, let url = entry["url"] as? String else { return nil }
            return (title, url)
        }
    }

    private static func latestSessionFile() -> URL? {
        let profiles = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Firefox/Profiles")
        let dirs = (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? []
        return dirs.map { $0.appendingPathComponent("sessionstore-backups/recovery.jsonlz4") }
            .compactMap { url -> (URL, Date)? in
                guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
                return (url, d)
            }
            .max(by: { $0.1 < $1.1 })?.0
    }

    private static func decompress(_ data: Data) -> Data? {
        guard data.count > 12, data.prefix(8) == Data("mozLz40\0".utf8) else { return nil }
        let size = Int(data.subdata(in: 8..<12).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        let body = data.subdata(in: 12..<data.count)
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { dst in
            body.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                          src.bindMemory(to: UInt8.self).baseAddress!, body.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        return n > 0 ? out.prefix(n) : nil
    }
}
