import Foundation

// MediaRemote: system-wide Now Playing info and transport commands. Needs no Apple Events permission.
// Since macOS 15.4 it only answers Apple-signed processes, so the calls run in Helper/NowPlayingHelper.m,
// loaded into /usr/bin/perl. This keeps that process running, reads its updates and sends it commands.
enum MediaRemote {
    enum Command: UInt32 { case togglePlayPause = 2, nextTrack = 4, previousTrack = 5 }

    struct Snapshot { var title = "", artist = "", playing = false, pid: Int32 = 0, art: Data? = nil }

    /// The latest state reported by the helper. Main thread only.
    private(set) static var latest = Snapshot()

    private static var input: FileHandle?
    private static var buffer = Data()
    private static let script = """
        use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::run", DynaLoader::dl_find_symbol($l, "run") || die); run();
        """

    static func start() {
        signal(SIGPIPE, SIG_IGN)   // a write to a helper that just exited should fail, not kill the app
        guard let lib = Bundle.main.path(forResource: "NowPlayingHelper", ofType: "dylib") else {
            return NSLog("NowPlayingHelper.dylib missing from the app bundle")
        }
        let p = Process(), out = Pipe(), inp = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", script, lib]
        p.standardOutput = out
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil }
            DispatchQueue.main.async { receive(data) }
        }
        p.terminationHandler = { p in
            NSLog("Now Playing helper exited (\(p.terminationStatus)); restarting")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { start() }
        }
        buffer = Data()
        do {
            try p.run()
            input = inp.fileHandleForWriting
        } catch {
            NSLog("Couldn't start Now Playing helper: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { start() }
        }
    }

    static func send(_ command: Command) { try? input?.write(contentsOf: Data("\(command.rawValue)\n".utf8)) }

    private static func receive(_ data: Data) {
        buffer.append(data)
        guard let end = buffer.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let lines = buffer[..<end].split(separator: UInt8(ascii: "\n"))
        buffer = Data(buffer[(end + 1)...])
        // Only the newest line matters.
        guard let line = lines.last,
              let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return }
        latest = Snapshot(title: j["title"] as? String ?? "", artist: j["artist"] as? String ?? "",
                          playing: (j["playing"] as? NSNumber)?.boolValue ?? false,
                          pid: (j["pid"] as? NSNumber)?.int32Value ?? 0,
                          art: (j["art"] as? String).flatMap { Data(base64Encoded: $0) })
    }
}
