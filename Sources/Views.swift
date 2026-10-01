import AppKit

func noAnimation(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

/// Layer-backed, clipped view with a fixed width, for use as a Touch Bar item.
class FixedView: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        wantsLayer = true
        layer!.masksToBounds = true
        widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Artwork at full tile width (at its own aspect ratio, so wide video thumbnails aren't cropped), scrolling
/// top-to-bottom on a seamless loop; crossfades on track change.
final class ArtView: FixedView {
    private let strip = CALayer()   // two stacked copies of the art
    private let copies = [CALayer(), CALayer()]
    private var playing = false
    private var laidOut = CGSize.zero
    private var aspect: CGFloat = 1   // art height / width

    override init(width: CGFloat) {
        super.init(width: width)
        layer!.cornerRadius = 5
        layer!.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        for c in copies {
            c.contentsGravity = .resizeAspectFill
            strip.addSublayer(c)
        }
        layer!.addSublayer(strip)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ data: Data?) {
        // Fade on the tile, not the strip, so the fade isn't tied to the scroll animation.
        let fade = CATransition()
        fade.duration = 0.6
        layer!.add(fade, forKey: "fade")
        let image = data.flatMap { NSImage(data: $0) }
        noAnimation { for c in copies { c.contents = image } }
        let newAspect = image.map { $0.size.width > 0 ? $0.size.height / $0.size.width : 1 } ?? 1
        if newAspect != aspect {
            aspect = newAspect
            laidOut = .zero
            needsLayout = true
        }
    }

    private var artHeight: CGFloat { max(bounds.height, bounds.width * aspect) }

    /// Pause holds the strip where it is; resume continues the loop from that point.
    func setPlaying(_ playing: Bool) {
        self.playing = playing
        if playing {
            startScroll()
        } else if strip.animation(forKey: "scroll") != nil {
            let y = strip.presentation()?.position.y ?? strip.position.y
            strip.removeAnimation(forKey: "scroll")
            noAnimation { strip.position.y = y }
        }
    }

    private var startY: CGFloat { bounds.height - artHeight }   // strip center with top of art visible

    private func startScroll() {
        let a = artHeight
        guard bounds.width > 0, strip.animation(forKey: "scroll") == nil else { return }
        // Moving the strip up one art-height brings the lower copy's top into view: identical to the start.
        let scroll = CABasicAnimation(keyPath: "position.y")
        scroll.fromValue = startY
        scroll.byValue = a
        scroll.duration = CFTimeInterval(a / 15)
        scroll.repeatCount = .infinity
        scroll.timeOffset = CFTimeInterval((strip.position.y - startY) / a) * scroll.duration
        strip.add(scroll, forKey: "scroll")
    }

    override func layout() {
        super.layout()
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        let w = bounds.width, h = bounds.height, a = artHeight
        noAnimation {
            strip.frame = CGRect(x: 0, y: h - 2 * a, width: w, height: 2 * a)
            copies[0].frame = CGRect(x: 0, y: a, width: w, height: a)
            copies[1].frame = CGRect(x: 0, y: 0, width: w, height: a)
        }
        strip.removeAnimation(forKey: "scroll")
        if playing { startScroll() }
    }
}

/// Title (bold) + artist, scrolling smoothly when too long to fit.
final class MarqueeView: FixedView {
    private let text = CATextLayer()
    private var current: NSAttributedString?

    override init(width: CGFloat) {
        super.init(width: width)
        text.contentsScale = 2
        layer!.addSublayer(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(title: String, artist: String) {
        let font = NSFont.systemFont(ofSize: 15)
        let s = NSMutableAttributedString(string: title.isEmpty ? "Not Playing" : title,
                                          attributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.white])
        if !artist.isEmpty {
            s.append(NSAttributedString(string: "  " + artist, attributes: [.font: font, .foregroundColor: NSColor.lightGray]))
        }
        guard s != current else { return }
        current = s

        let size = s.size()
        let fits = size.width <= bounds.width
        let shown = NSMutableAttributedString(attributedString: s)
        var period: CGFloat = 0
        if !fits {   // "text • text": scrolling exactly one period loops seamlessly
            shown.append(NSAttributedString(string: "      •      ", attributes: [.font: font, .foregroundColor: NSColor.gray]))
            period = shown.size().width
            shown.append(s)
        }
        text.removeAllAnimations()
        noAnimation {
            text.string = shown
            text.frame = CGRect(x: 0, y: (bounds.height - size.height) / 2, width: shown.size().width + 2, height: size.height)
        }
        guard !fits else { return }
        let scroll = CABasicAnimation(keyPath: "position.x")
        scroll.byValue = -period
        scroll.duration = CFTimeInterval(period / 35)
        scroll.repeatCount = .infinity
        scroll.beginTime = CACurrentMediaTime() + 1.5
        text.add(scroll, forKey: "scroll")
    }
}

/// Rainbow EQ bars.
final class EQView: FixedView {
    private var bars: [CALayer] = []

    init(width: CGFloat, count: Int) {
        super.init(width: width)
        for i in 0..<count {
            let b = CALayer()
            b.backgroundColor = NSColor(hue: CGFloat(i) / CGFloat(count) * 0.85, saturation: 0.85, brightness: 1, alpha: 1).cgColor
            b.cornerRadius = 1.5
            layer!.addSublayer(b)
            bars.append(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ levels: [Float]) {
        let bw = bounds.width / CGFloat(bars.count), maxH = bounds.height - 4
        noAnimation {
            for (i, b) in bars.enumerated() {
                let h = max(2, CGFloat(levels[i]) * maxH)
                b.frame = CGRect(x: CGFloat(i) * bw + 1, y: (bounds.height - h) / 2, width: bw - 2, height: h)
            }
        }
    }
}

/// Simulated EQ levels: animated while playing, settling to flat when paused. Not driven by real audio.
final class SimulatedLevels {
    let count: Int
    private var energy: Float = 0

    init(count: Int) { self.count = count }

    func next(playing: Bool) -> [Float] {
        energy += ((playing ? 1 : 0) - energy) * 0.1
        let t = CACurrentMediaTime()
        return (0..<count).map { i in
            let d = Double(i)
            let v = abs(sin(t * (3.1 + d * 0.7) + d * 1.3)) * 0.6 + abs(sin(t * 7.3 + d * 2.1)) * 0.4
            return Float(v) * energy
        }
    }
}
