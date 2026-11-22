// Clawd v2: a small Claude Code mascot on the desktop, with a laptop and a Santa hat.
//   ClawdWallpaper                       live mode
//   ClawdWallpaper --every 3             minutes between hat entrances (default 3)
//   ClawdWallpaper --frames dir [wallpaper.png]   render each hat entrance to a sheet of frames
//   ClawdWallpaper --selftest            run every entrance and check he ends up tidy
//   ClawdWallpaper --no-login            take him off the login items and quit
//
// Every part of him is its own small layer, moved every frame along smooth curves, so the
// animation is fluid without redrawing any pixels. He stops completely while he's covered.
import AppKit
import ServiceManagement

// Where he sits, as fractions of the wallpaper image (y from the top): in the dark band above the art, left of centre.
let imageSize = CGSize(width: 2880, height: 1864)
let anchorFrac = CGPoint(x: 0.40, y: 0.11)
let baseUnit: CGFloat = 6                    // points per sprite pixel on a 1710pt-wide screen
let spritePx: CGFloat = 8                    // bitmap pixels per sprite pixel
let defaultEveryMinutes = 3.0

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
let orange = rgb(0xD97757), eyeBlack = rgb(0x141210)
let red = rgb(0xCF3A30), redDark = rgb(0x9C2620), redLight = rgb(0xE8564A)
let white = rgb(0xF4EFE6), whiteShade = rgb(0xC9C2B6)
let lid = rgb(0xB9BDC6), lidEdge = rgb(0xDDE0E5), lidSide = rgb(0x878C96), screenLight = rgb(0xDCE8FF)

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// MARK: - Art

// A piece of him: pixel art in its own box. Drawing uses whole-sprite coordinates, y down,
// with (9, 3.5) the middle of his body, so every piece lines up with the others.
typealias Paint = (CGFloat, CGFloat, CGFloat, CGFloat, CGColor) -> Void
struct Part {
    let image: CGImage, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, _ draw: (Paint) -> Void) {
        let c = context(Int(w * spritePx), Int(h * spritePx))
        c.setShouldAntialias(false)
        draw { px, py, pw, ph, col in
            c.setFillColor(col)
            c.fill(CGRect(x: (px - x) * spritePx, y: (h - (py - y) - ph) * spritePx, width: pw * spritePx, height: ph * spritePx))
        }
        image = c.makeImage()!; self.x = x; self.y = y; self.w = w; self.h = h
    }
}

let bodyArt = Part(x: 3, y: 0, w: 12, h: 6) { $0(3, 0, 12, 6, orange) }
let armArt = Part(x: 0, y: 0, w: 2, h: 1) { $0(0, 0, 2, 1, orange) }
let legArt = Part(x: 0, y: 0, w: 1, h: 1.5) { $0(0, 0, 1, 1.5, orange) }
let eyeArt = Part(x: 0, y: 0, w: 1.5, h: 2) { $0(0, 0, 1.5, 2, eyeBlack) }
let handArt = Part(x: 0, y: 0, w: 1, h: 0.5) { $0(0, 0, 1, 0.5, orange) }
// The laptop, lid towards you, with a very small Claude on the back of it.
let laptopArt = Part(x: 4.5, y: 3.25, w: 9, h: 3.25) { px in
    px(5.5, 3.25, 7, 2.75, lid); px(5.5, 3.25, 7, 0.25, lidEdge); px(12.25, 3.25, 0.25, 2.75, lidSide)
    px(8.875, 3.75, 0.25, 1.5, orange); px(8.25, 4.375, 1.5, 0.25, orange); px(8.75, 4.25, 0.5, 0.5, orange)
    for (x, y) in [(8.375, 3.875), (9.375, 3.875), (8.375, 4.875), (9.375, 4.875)] as [(CGFloat, CGFloat)] { px(x, y, 0.25, 0.25, orange) }
    px(4.5, 6, 9, 0.5, lidSide); px(4.5, 6, 9, 0.25, lidEdge)
}
let screenArt = Part(x: 5.5, y: 3, w: 7, h: 0.25) { $0(5.5, 3, 7, 0.25, screenLight) }
// The hat, without its pompom, which swings on its own.
let hatArt = Part(x: 4, y: -6, w: 14, h: 6) { hat in
    hat(5, -2, 8, 1, red); hat(6, -3, 7, 1, red); hat(7, -4, 6, 1, red); hat(9, -5, 4, 1, red)
    hat(11, -2, 2, 1, redDark); hat(11.5, -3, 1.5, 1, redDark); hat(12, -4, 1, 1, redDark)
    hat(6, -2, 1, 1, redLight); hat(7, -3, 1, 1, redLight); hat(8, -4, 1, 1, redLight)
    hat(11, -6, 3, 1, red); hat(12.5, -6, 1.5, 1, redDark); hat(13.5, -5, 1.5, 1, red)
    hat(4, -1, 10, 1, white); hat(4, -0.5, 10, 0.5, whiteShade)
}
let pompomArt = Part(x: 14.5, y: -4.5, w: 3, h: 3) { p in
    p(15, -4.5, 2, 3, white); p(14.5, -4, 3, 2, white); p(15, -2, 2, 0.5, whiteShade); p(17, -3.5, 0.5, 1.5, whiteShade)
}

func glowImage() -> CGImage {
    let c = context(160, 160)
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [rgb(0xE8743F, 0.30), rgb(0xD9633A, 0.11), rgb(0xB84A2E, 0.03), rgb(0xB84A2E, 0)] as CFArray,
                       locations: [0, 0.32, 0.68, 1])!
    c.drawRadialGradient(g, startCenter: CGPoint(x: 80, y: 80), startRadius: 0, endCenter: CGPoint(x: 80, y: 80), endRadius: 80, options: [])
    return c.makeImage()!
}

// MARK: - Motion

func clamp(_ v: CGFloat, _ lo: CGFloat = 0, _ hi: CGFloat = 1) -> CGFloat { min(hi, max(lo, v)) }
func smooth(_ k: CGFloat) -> CGFloat { let k = clamp(k); return k * k * (3 - 2 * k) }
func easeOut(_ k: CGFloat) -> CGFloat { let k = clamp(k); return 1 - (1 - k) * (1 - k) * (1 - k) }
func easeOutBack(_ k: CGFloat) -> CGFloat { let k = clamp(k), c: CGFloat = 1.9; return 1 + (c + 1) * pow(k - 1, 3) + c * pow(k - 1, 2) }
// A spring settling: 1 at τ = 0, wobbling down to nothing.
func wobble(_ tau: CGFloat, freq: CGFloat, decay: CGFloat) -> CGFloat { tau < 0 ? 0 : exp(-decay * tau) * cos(2 * .pi * freq * tau) }

// Where the hat is, relative to sitting on his head.
struct HatState { var dx: CGFloat = 0, dy: CGFloat = 0, rot: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, alpha: CGFloat = 1, pompom: CGFloat = 0, onHead = true }
// What his body is doing about it.
struct BodyState { var lift: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1, look: CGPoint? = nil, squint = false }

// The hat leaves one of two ways and comes back one of four, a different pairing each time.
struct Entrance {
    let start: Double, enter: Int, exit: Int
    static let exitTime = 0.9, gap = 0.35, settle = 1.2
    static let enterTimes = [0.65, 1.5, 1.5, 0.5]       // until it's on his head
    var landsAt: Double { start + Entrance.exitTime + Entrance.gap + Entrance.enterTimes[enter] }
    var end: Double { landsAt + Entrance.settle }

    func at(_ t: Double) -> (HatState, BodyState) {
        var h = HatState(), b = BodyState()
        let a = CGFloat(t - start)
        let exitT = CGFloat(Entrance.exitTime), enterAt = CGFloat(Entrance.exitTime + Entrance.gap)
        if a < exitT {                                    // off it goes
            let k = a / exitT
            h.onHead = false
            if exit == 0 {                                // popped straight up with a hop
                h.dy = -34 * easeOut(k); h.rot = k * 3.6; h.alpha = 1 - k * k * k
                b.lift = a < 0.3 ? 1.6 * sin(.pi * a / 0.3) : 0
                h.pompom = 0.5 * sin(k * 12)
            } else {                                      // a gust takes it off to the left
                h.dx = -36 * pow(k, 1.6); h.dy = -8 * sin(k * 2.5) - 4 * k; h.rot = -k * 2.8 + 0.2 * sin(k * 14); h.alpha = 1 - pow(k, 4)
                h.pompom = 0.7 * sin(k * 16); b.squint = k < 0.45
            }
            b.look = CGPoint(x: h.dx + 9, y: h.dy - 3)
            return (h, b)
        }
        let s = a - enterAt
        if s < 0 { h.alpha = 0; h.onHead = false; b.look = exit == 0 ? CGPoint(x: 9, y: -40) : CGPoint(x: -30, y: -10); return (h, b) }
        let fly = CGFloat(Entrance.enterTimes[enter]), tau = s - fly
        switch enter {
        case 0:                                           // dropped from the sky, and it lands hard
            if s < fly {
                let k = s / fly
                h.onHead = false; h.dy = -44 * (1 - k * k); h.alpha = clamp(k * 4); h.rot = (1 - k) * 0.5 * sin(k * 9)
                h.pompom = 0.3 * sin(k * 10)
            } else {
                let w = wobble(tau, freq: 2.2, decay: 5)
                b.sy = 1 - 0.2 * w; b.sx = 1 + 0.14 * w
                h.sy = 1 - 0.12 * w; h.pompom = 0.7 * wobble(tau, freq: 1.5, decay: 3)
                b.squint = tau < 0.35
            }
        case 1:                                           // flung back like a boomerang, spinning
            if s < fly {
                let k = easeOut(s / fly), j = 1 - k
                let p0 = CGPoint(x: 42, y: -26), p1 = CGPoint(x: 10, y: -38)
                h.onHead = false
                h.dx = j * j * p0.x + 2 * j * k * p1.x; h.dy = j * j * p0.y + 2 * j * k * p1.y
                h.rot = -j * 4 * .pi; h.alpha = clamp(s * 5); h.pompom = 0.4 * sin(s * 20) * j
            } else {
                h.rot = 0.22 * wobble(tau, freq: 1.8, decay: 4); h.pompom = 0.6 * wobble(tau, freq: 1.4, decay: 3)
                let w = wobble(tau, freq: 2.4, decay: 6); b.sy = 1 - 0.08 * w; b.sx = 1 + 0.06 * w
            }
        case 2:                                           // it waits up there, so he jumps into it
            let hover: CGFloat = -10
            if s < 0.4 { let k = easeOutBack(s / 0.4); h.sx = k; h.sy = k }
            if s < 1.1 {
                h.onHead = false; h.dy = hover + 0.4 * sin(s * 6); h.pompom = 0.25 * sin(s * 5)
                if s > 0.4 && s < 0.7 { let q = smooth((s - 0.4) / 0.3); b.sy = 1 - 0.18 * q; b.sx = 1 + 0.1 * q }
                if s >= 0.7 { let q = (s - 0.7) / 0.4; b.lift = -hover * (1 - (1 - q) * (1 - q)); b.sy = 1.12 - 0.12 * q; b.sx = 0.94 + 0.06 * q }
            } else if s < fly {
                let q = (s - 1.1) / 0.4; b.lift = -hover * (1 - q * q); b.sy = 1 + 0.06 * q; b.sx = 1 - 0.04 * q
                h.pompom = 0.5 * sin(q * .pi)
            } else {
                let w = wobble(tau, freq: 2.2, decay: 5); b.sy = 1 - 0.16 * w; b.sx = 1 + 0.11 * w
                h.pompom = 0.6 * wobble(tau, freq: 1.5, decay: 3); b.squint = tau < 0.3
            }
        default:                                          // it just appears, with a flourish
            if s < fly { h.alpha = 0; h.onHead = false }
            else {
                let sc = 1 - exp(-6 * tau) * cos(13 * tau)
                h.sx = sc; h.sy = sc; h.rot = -2 * .pi * exp(-7 * tau); h.pompom = 0.5 * wobble(tau, freq: 1.5, decay: 3)
                b.squint = tau < 0.4
            }
        }
        if !h.onHead || s < fly + 0.15 { b.look = CGPoint(x: h.dx + 9, y: h.dy - 3) }
        return (h, b)
    }
}

struct Sparkle { let layer: CALayer, born: Double, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: Double, gravity: CGFloat }

// MARK: - Live mode

final class Clawd: NSObject {
    let screen: NSScreen, window: NSWindow, root: CALayer
    let u: CGFloat, size: CGSize, center: CGPoint   // center is in screen coordinates
    let glow = CALayer(), rig = CALayer(), bodyGroup = CALayer()
    let body = CALayer(), armL = CALayer(), armR = CALayer(), eyeL = CALayer(), eyeR = CALayer()
    let legs = (0..<4).map { _ in CALayer() }
    let laptop = CALayer(), screenGlow = CALayer(), handL = CALayer(), handR = CALayer()
    let hat = CALayer(), pompom = CALayer()
    var every: Double
    var link: CADisplayLink?, timer: Timer?
    var active = true, visible = true

    // Tests drive these instead of the clock and the cursor.
    var fakeT: Double? = nil, fakeMouse: CGPoint? = nil
    let start = Date.timeIntervalSinceReferenceDate
    var now: Double { fakeT ?? Date.timeIntervalSinceReferenceDate - start }
    var mouseNow: CGPoint { fakeMouse ?? NSEvent.mouseLocation }

    var lastT = 0.0, lastMouse = CGPoint.zero, lastMoveT = 0.0
    var look = CGPoint.zero, idleLook: CGPoint? = nil, nextIdleLook = 0.0
    var nextBlink = 2.0, blinkStart = -10.0, doubleBlink = false
    var nextTyping = 8.0, typingStart = -100.0, typingEnd = -100.0
    var nextTap = 20.0, tapStart = -10.0
    var entrance: Entrance?, entranceCount = 0, nextEntrance = 4.0, burstDone = false, twinkled = false
    var sparkles: [Sparkle] = []
    var hatInFront = false

    init(screen s: NSScreen, every minutes: Double = defaultEveryMinutes, show: Bool = true) {
        screen = s; every = minutes * 60
        let f = s.frame
        let fill = max(f.width / imageSize.width, f.height / imageSize.height)   // like the "Fill Screen" placement
        let shown = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        center = CGPoint(x: f.midX + (anchorFrac.x - 0.5) * shown.width, y: f.midY - (anchorFrac.y - 0.5) * shown.height)
        let scale = s.backingScaleFactor
        u = ((baseUnit * f.width / 1710) * scale).rounded() / scale
        size = CGSize(width: (120 * u).rounded(), height: (110 * u).rounded())   // room for the hat to fly about
        let frame = NSRect(x: (center.x - size.width / 2).rounded(), y: (center.y - size.height / 2).rounded(), width: size.width, height: size.height)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size)); view.wantsLayer = true
        window.contentView = view
        root = view.layer!
        super.init()

        let bounds = CGRect(origin: .zero, size: size)
        glow.contents = glowImage(); glow.bounds = CGRect(x: 0, y: 0, width: 56 * u, height: 56 * u)
        rig.bounds = bounds; rig.position = mid
        bodyGroup.bounds = bounds
        bodyGroup.anchorPoint = CGPoint(x: 0.5, y: pt(9, 7.5).y / size.height)   // squashes from his feet
        bodyGroup.position = pt(9, 7.5)
        for l in [glow, rig, bodyGroup, body, armL, armR, eyeL, eyeR, laptop, screenGlow, handL, handR, hat, pompom] + legs { quiet(l) }
        root.addSublayer(glow); root.addSublayer(rig); rig.addSublayer(bodyGroup)
        func add(_ l: CALayer, _ p: Part) { l.contents = p.image; l.bounds = CGRect(x: 0, y: 0, width: p.w * u, height: p.h * u); bodyGroup.addSublayer(l) }
        for l in legs { add(l, legArt) }
        add(armL, armArt); add(armR, armArt); add(body, bodyArt); add(eyeL, eyeArt); add(eyeR, eyeArt)
        add(laptop, laptopArt); add(screenGlow, screenArt); add(handL, handArt); add(handR, handArt)
        laptop.position = pt(laptopArt.x + laptopArt.w / 2, laptopArt.y + laptopArt.h / 2)
        screenGlow.position = pt(screenArt.x + screenArt.w / 2, screenArt.y + screenArt.h / 2)
        body.position = pt(9, 3)
        for l in [eyeL, eyeR] { l.anchorPoint = CGPoint(x: 0.5, y: 0.5) }
        hat.contents = hatArt.image
        hat.bounds = CGRect(x: 0, y: 0, width: hatArt.w * u, height: hatArt.h * u)
        hat.anchorPoint = CGPoint(x: (9 - hatArt.x) / hatArt.w, y: 0)    // the middle of the brim
        pompom.contents = pompomArt.image
        pompom.bounds = CGRect(x: 0, y: 0, width: pompomArt.w * u, height: pompomArt.h * u)
        pompom.anchorPoint = CGPoint(x: 0, y: 1)                        // hangs off the tip
        pompom.position = CGPoint(x: (pompomArt.x - hatArt.x) * u, y: (0 - pompomArt.y) * u)
        hat.addSublayer(pompom)
        rig.addSublayer(hat)
        if show { window.orderFront(nil) }
        update()
    }

    var mid: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    // Sprite coordinates (y down, his middle at 9, 3.5) to points in his window.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mid.x + (x - 9) * u, y: mid.y - (y - 3.5) * u) }
    func quiet(_ l: CALayer) {
        l.actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(), "contents": NSNull(), "hidden": NSNull(), "anchorPoint": NSNull()]
        l.magnificationFilter = .nearest
    }
    func place(_ l: CALayer, _ x: CGFloat, _ y: CGFloat) {         // top-left corner, in sprite coordinates
        let p = pt(x, y), b = l.bounds.size
        l.position = CGPoint(x: p.x + b.width * l.anchorPoint.x, y: p.y - b.height * (1 - l.anchorPoint.y))
    }

    // MARK: Running

    // The loops that never stop (floating, breathing, the glow, the pompom swinging) are handed to
    // Core Animation, which plays them smoothly without waking this app at all. Everything that
    // reacts or happens now and then runs on the display link, and only while it's happening.
    func run() {
        let period = 3.6
        func loop(_ key: String, _ amount: CGFloat, cycles: Double = 1, phase: CGFloat = 0, additive: Bool = true, base: CGFloat = 0) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: key), n = 48
            var values: [CGFloat] = []
            for i in 0...n {
                let angle: CGFloat = CGFloat(i) / CGFloat(n) * 2 * .pi * CGFloat(cycles) + phase
                values.append(base + amount * sin(angle))
            }
            a.values = values
            a.duration = period * 2; a.repeatCount = .infinity; a.isAdditive = additive; a.calculationMode = .linear
            a.isRemovedOnCompletion = false
            return a
        }
        rig.add(loop("position.y", 0.45 * u, cycles: 2), forKey: "float")
        bodyGroup.add(loop("transform.scale.y", 0.012, cycles: 4, phase: 0.6), forKey: "breathe-y")
        bodyGroup.add(loop("transform.scale.x", -0.012, cycles: 4, phase: 0.6), forKey: "breathe-x")
        glow.add(loop("opacity", 0.15, cycles: 2, additive: false, base: 0.85), forKey: "pulse")
        pompom.add(loop("transform.rotation.z", -0.12, cycles: 3), forKey: "swing")   // whole cycles, so the loop is seamless
        hat.add(loop("transform.rotation.z", -0.035, cycles: 1, phase: 1), forKey: "lean")
        for (l, ph) in [(armL, CGFloat(1)), (armR, 2)] { l.add(loop("position.y", -0.1 * u, cycles: 2, phase: ph), forKey: "sway") }

        let l = window.contentView!.displayLink(target: self, selector: #selector(frame))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
        // A slow heartbeat for noticing the cursor and keeping time while nothing's happening.
        let tm = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.heartbeat() }
        tm.tolerance = 0.1
        RunLoop.main.add(tm, forMode: .common)
        timer = tm
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            self?.occlusionChanged()
        }
        occlusionChanged()
    }

    func close() { link?.invalidate(); link = nil; timer?.invalidate(); timer = nil; window.orderOut(nil) }

    func occlusionChanged() {
        visible = window.occlusionState.contains(.visible)
        syncLink()
    }

    func syncLink() {
        let paused = !(visible && active)
        if link?.isPaused != paused { link?.isPaused = paused }
        let fps: Float = entrance != nil || !sparkles.isEmpty ? 60 : 30     // the hat flying gets every frame
        if link?.preferredFrameRateRange.preferred != fps { link?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: fps, preferred: fps) }
    }

    func heartbeat() {
        guard visible, link?.isPaused ?? true else { return }
        update(); syncLink()
    }

    @objc func frame() { update(); syncLink() }

    var typing: Bool { now >= typingStart && now < typingEnd }

    // MARK: Every frame

    func update() {
        let t = now, dt = min(0.1, max(0, t - lastT)); lastT = t
        let mouse = mouseNow
        if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 1 { lastMouse = mouse; lastMoveT = t; idleLook = nil }
        let idle = t - lastMoveT

        // What's coming up
        if entrance == nil, t >= nextEntrance {
            entrance = Entrance(start: t, enter: entranceCount % 4, exit: (entranceCount / 4 + entranceCount) % 2)
            entranceCount += 1; burstDone = false; twinkled = false
            typingEnd = min(typingEnd, t)
        }
        if let e = entrance, t >= e.end { entrance = nil; nextEntrance = t + every }
        if entrance == nil, !typing, t >= nextTyping {
            typingStart = t; typingEnd = t + Double.random(in: 3...7); nextTyping = typingEnd + Double.random(in: 12...35)
        }
        if t >= nextBlink {
            blinkStart = t; doubleBlink = Int.random(in: 0..<5) == 0
            nextBlink = t + Double.random(in: 2.5...6)
        }
        if t >= nextTap { tapStart = t; nextTap = t + Double.random(in: 20...50) }

        // The hat, and what it's making him do
        var h = HatState(), b = BodyState()
        if let e = entrance { (h, b) = e.at(t); sparkleEvents(e, t) }
        let float = b.lift
        let sx = b.sx, sy = b.sy

        // Where he looks: the hat while it's flying, the laptop while typing, otherwise you
        var target: CGPoint
        let me = CGPoint(x: center.x, y: center.y + float * u)
        let hover = hypot(mouse.x - me.x, mouse.y - me.y) < 9 * u && idle < 5
        if let l = b.look { target = CGPoint(x: (l.x - 9) * 3, y: (l.y - 3.5) * 3) }
        else if typing { target = CGPoint(x: sin(CGFloat(t) * 1.7) * 4, y: 20) }
        else {
            if idle > 10, t >= nextIdleLook || idleLook == nil {
                nextIdleLook = t + Double.random(in: 4...9)
                idleLook = CGPoint(x: .random(in: -30...30), y: .random(in: -20...8))
            }
            if idle > 10, let l = idleLook { target = l }
            else { target = CGPoint(x: (mouse.x - me.x) / u, y: -(mouse.y - me.y) / u) }
        }
        let d = max(hypot(target.x, target.y), 0.001), mag = min(1, d / 24)
        let goal = CGPoint(x: target.x / d * mag, y: target.y / d * mag * 0.5)
        let k = 1 - exp(-dt * 12)
        look.x += (goal.x - look.x) * k; look.y += (goal.y - look.y) * k

        // Body
        rig.position = CGPoint(x: mid.x, y: mid.y + float * u)
        bodyGroup.setAffineTransform(CGAffineTransform(scaleX: sx, y: sy))
        glow.position = CGPoint(x: mid.x, y: mid.y + float * 0.5 * u)
        place(body, 3, 0)

        // Legs: dangling, a little tippy-tap now and then
        let tapping = t - tapStart < 1.3 || hover
        for (i, x) in [CGFloat(4), 6, 11, 13].enumerated() {
            let lift = tapping ? max(0, sin(CGFloat(t) * 2 * .pi * 3 + (i % 2 == 0 ? 0 : .pi))) * 0.5 : 0
            legs[i].setAffineTransform(CGAffineTransform(scaleX: 1, y: 1 - lift / 1.5))
            legs[i].anchorPoint = CGPoint(x: 0.5, y: 1)
            place(legs[i], x, 6)
        }

        // Typing: arms in, hands on the keys, the screen flickering away
        let tIn = smooth(CGFloat((t - typingStart) / 0.25)) * (1 - smooth(CGFloat((t - typingEnd) / 0.25 + 1)))
        let into = tIn
        place(armL, 1 + into * 2.5, 3 + into * 1.5)
        place(armR, 15 - into * 2.5, 3 + into * 1.5)
        let tapL = max(0, sin(CGFloat(t) * 2 * .pi * 5)), tapR = max(0, sin(CGFloat(t) * 2 * .pi * 5 + .pi * 0.9))
        place(handL, 5, 5.75 - tapL * 0.35 * into); place(handR, 12, 5.75 - tapR * 0.35 * into)
        handL.opacity = Float(into); handR.opacity = Float(into)
        let flicker = into > 0 ? 0.2 * (sin(CGFloat(t) * 23) * sin(CGFloat(t) * 7.3)) : 0
        screenGlow.opacity = Float(0.45 + 0.35 * into + flicker)

        // Eyes: follow, blink, squint when happy
        var blink: CGFloat = 1
        let bs = t - blinkStart
        if bs < 0.16 { blink = 1 - 0.9 * sin(.pi * CGFloat(bs / 0.16)) }
        else if doubleBlink, bs > 0.24, bs < 0.4 { blink = 1 - 0.9 * sin(.pi * CGFloat((bs - 0.24) / 0.16)) }
        if b.squint || hover { blink = min(blink, 0.3) }
        for (l, ex) in [(eyeL, CGFloat(5)), (eyeR, 11.5)] {
            l.setAffineTransform(CGAffineTransform(scaleX: 1, y: blink))
            place(l, ex + look.x, 1.5 + look.y)
        }

        // The hat sits on his head, squashing with him, unless it's off on an adventure
        let headTop = 7.5 - 7.5 * sy                      // how far the squash pulls the brim down
        hat.position = pt(9 + h.dx, (h.onHead ? headTop : 0) + h.dy)
        if !h.onHead { hat.position.y -= b.lift * u }   // in flight it doesn't jump when he does
        hat.setAffineTransform(CGAffineTransform(rotationAngle: -h.rot).scaledBy(x: h.sx * (h.onHead ? sx : 1), y: h.sy))
        hat.opacity = Float(h.alpha)
        pompom.setAffineTransform(CGAffineTransform(rotationAngle: -h.pompom))

        updateSparkles(t)

        // Is anything moving that needs every frame?
        let settling = abs(goal.x - look.x) > 0.01 || abs(goal.y - look.y) > 0.01
        active = entrance != nil || !sparkles.isEmpty || (t >= typingStart - 0.05 && t < typingEnd + 0.3)
            || t - blinkStart < 0.45 || tapping || idle < 0.4 || settling
    }

    // MARK: Sparkles

    func sparkleEvents(_ e: Entrance, _ t: Double) {
        let lands = e.landsAt
        if e.enter == 3, !twinkled, t >= lands - 0.45, t < lands {
            twinkled = true
            for i in 0..<8 {
                let a = CGFloat(i) / 8 * 2 * .pi
                spark(t, x: 9 + cos(a) * 7, y: -2 + sin(a) * 4, vx: -cos(a) * 14, vy: -sin(a) * 8, life: 0.45, gravity: 0, color: rgb(0xFFF3C4))
            }
        }
        if !burstDone, t >= lands {
            burstDone = true
            guard t - lands < 0.3 else { return }        // came back long after: no fireworks for nobody
            for i in 0..<12 {
                let a = CGFloat(i) / 12 * 2 * .pi + .random(in: -0.2...0.2), v = CGFloat.random(in: 8...16)
                spark(t, x: 9 + cos(a) * 3, y: -2 + sin(a) * 1.5, vx: cos(a) * v, vy: sin(a) * v * 0.6 - 6,
                      life: .random(in: 0.5...0.9), gravity: 26, color: i % 3 == 0 ? rgb(0xFFF3C4) : white)
            }
        }
    }

    func spark(_ t: Double, x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, life: Double, gravity: CGFloat, color: CGColor) {
        let l = CALayer(); quiet(l)
        l.backgroundColor = color
        l.bounds = CGRect(x: 0, y: 0, width: 0.6 * u, height: 0.6 * u)
        rig.addSublayer(l)
        sparkles.append(Sparkle(layer: l, born: t, x: x, y: y, vx: vx, vy: vy, life: life, gravity: gravity))
    }

    func updateSparkles(_ t: Double) {
        guard !sparkles.isEmpty else { return }
        sparkles = sparkles.filter { s in
            let a = t - s.born
            if a >= s.life || a < 0 { s.layer.removeFromSuperlayer(); return false }
            let k = CGFloat(a)
            s.layer.position = pt(s.x + s.vx * k, s.y + s.vy * k + 0.5 * s.gravity * k * k)
            s.layer.opacity = Float(1 - pow(a / s.life, 2))
            let sc = 1 - 0.5 * CGFloat(a / s.life)
            s.layer.setAffineTransform(CGAffineTransform(rotationAngle: k * 6).scaledBy(x: sc, y: sc))
            return true
        }
    }
}

// MARK: - Screens

// The MacBook's own screen, which is the one with this wallpaper; any screen if there isn't one.
func homeScreen() -> NSScreen? {
    NSScreen.screens.first { s in
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
    } ?? NSScreen.screens.first
}

final class Controller {
    var clawd: Clawd?
    var every = defaultEveryMinutes
    func rebuild() {
        clawd?.close()
        guard let s = homeScreen() else { return }
        let c = Clawd(screen: s, every: every)
        c.run()
        clawd = c
    }
    func start() {
        rebuild()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }
}

// MARK: - Frames and tests

func writePNG(_ image: CGImage, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
}

func makeSim(_ screen: NSScreen) -> Clawd {
    let c = Clawd(screen: screen, show: false)
    c.fakeT = 0.01; c.fakeMouse = CGPoint(x: c.center.x + 300, y: c.center.y - 200)
    c.nextEntrance = 1e9; c.nextTyping = 1e9; c.nextTap = 1e9; c.nextBlink = 1e9
    c.lastMouse = c.fakeMouse!; c.update()
    return c
}
func step(_ c: Clawd, to t: Double, each: (() -> Void)? = nil) {
    while (c.fakeT ?? 0) < t { c.fakeT = min(t, (c.fakeT ?? 0) + 1.0 / 60); c.lastMoveT = c.fakeT!; c.update(); each?() }
}

func renderFrames(dir: String, wallpaper: String?) {
    guard let screen = homeScreen() else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var wall: CGImage? = nil
    if let p = wallpaper, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) { wall = CGImageSourceCreateImageAtIndex(src, 0, nil) }
    let f = screen.frame, scale: CGFloat = 2
    func shot(_ c: Clawd, crop: CGSize, whole: Bool = false) -> CGImage {
        let x = context(Int(crop.width * scale), Int(crop.height * scale))
        x.scaleBy(x: scale, y: scale)
        let origin = whole ? f.origin : CGPoint(x: c.center.x - crop.width / 2, y: c.center.y - crop.height / 2)
        x.translateBy(x: -origin.x, y: -origin.y)
        x.setFillColor(rgb(0x07070C)); x.fill(f)
        if let w = wall { x.interpolationQuality = .high; x.draw(w, in: f) }
        x.translateBy(x: c.window.frame.minX, y: c.window.frame.minY)
        c.root.render(in: x)
        return x.makeImage()!
    }
    func sheet(_ name: String, _ frames: [CGImage], cols: Int) {
        let w = frames[0].width, h = frames[0].height, rows = (frames.count + cols - 1) / cols
        let g = context(w * cols + 4 * (cols - 1), h * rows + 4 * (rows - 1))
        g.setFillColor(rgb(0x333333)); g.fill(CGRect(x: 0, y: 0, width: g.width, height: g.height))
        for (i, img) in frames.enumerated() { g.draw(img, in: CGRect(x: (i % cols) * (w + 4), y: (rows - 1 - i / cols) * (h + 4), width: w, height: h)) }
        writePNG(g.makeImage()!, dir + "/" + name + ".png")
    }
    // Where he is on the whole screen
    let whole = makeSim(screen)
    writePNG(shot(whole, crop: f.size, whole: true), dir + "/placement.png")
    let crop = CGSize(width: 70 * whole.u, height: 70 * whole.u)
    for (n, name) in ["drop", "boomerang", "jump", "pop"].enumerated() {
        for exit in 0..<2 {
            let c = makeSim(screen)
            c.entrance = Entrance(start: c.fakeT!, enter: n, exit: exit); c.nextEntrance = 1e9
            let e = c.entrance!, lands = e.landsAt - e.start
            var frames: [CGImage] = []
            for at in [0.15, 0.45, 0.8, 1.3, lands - 0.5, lands - 0.25, lands - 0.05, lands + 0.05, lands + 0.15, lands + 0.3, lands + 0.6, lands + 1.2] {
                step(c, to: e.start + at); frames.append(shot(c, crop: crop))
            }
            sheet("entrance-\(name)-\(exit == 0 ? "up" : "gust")", frames, cols: 6)
        }
    }
    let c = makeSim(screen)
    c.typingStart = 0.5; c.typingEnd = 3.5
    var frames: [CGImage] = []
    for at in [0.3, 0.6, 0.9, 1.0, 1.1, 1.2, 2.0, 3.6, 3.9] { step(c, to: at); frames.append(shot(c, crop: crop)) }
    sheet("typing", frames, cols: 5)
}

func selftest() -> Bool {
    guard let screen = homeScreen() else { print("no screen"); return false }
    var failures: [String] = []
    func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
    func tidy(_ c: Clawd) -> Bool {
        c.sparkles.isEmpty && c.entrance == nil && abs(c.hat.opacity - 1) < 0.001
            && abs(c.hat.affineTransform().b) < 0.02 && abs(c.hat.position.x - c.pt(9, 0).x) < 0.5
            && abs(c.bodyGroup.affineTransform().a - 1) < 0.03 && c.rig.sublayers?.count == 2
    }
    for enter in 0..<4 { for exit in 0..<2 {
        let name = "entrance \(enter)/\(exit)"
        let c = makeSim(screen)
        c.entrance = Entrance(start: c.fakeT!, enter: enter, exit: exit)
        let e = c.entrance!
        var left = false, gone = false, landed = false, sparkled = false, escaped = false, worstJump: CGFloat = 0
        var lastHat = c.hat.position, wasShown = true
        step(c, to: e.end + 1) {
            if c.hat.position.y > c.pt(9, -3).y { left = true }
            if c.hat.opacity < 0.05 { gone = true }
            if gone, abs(c.hat.position.x - c.pt(9, 0).x) < 1, c.hat.opacity > 0.99 { landed = true }
            if !c.sparkles.isEmpty { sparkled = true }
            let hp = c.hat.position
            let shown = c.hat.opacity > 0.05 && c.hat.affineTransform().d > 0.3
            if shown {
                if hp.x < -2 * c.u || hp.x > c.size.width + 2 * c.u || hp.y < 0 || hp.y + 6 * c.u > c.size.height { escaped = true }
                if wasShown { worstJump = max(worstJump, hypot(hp.x - lastHat.x, hp.y - lastHat.y) / c.u) }
            }
            lastHat = hp; wasShown = shown
        }
        check(left && gone, "\(name): the hat never came off")
        check(landed, "\(name): the hat never came back")
        check(sparkled, "\(name): no sparkles")
        check(!escaped, "\(name): the hat left his window")
        check(worstJump < 4, "\(name): the hat jumped \(worstJump) px in one frame")
        check(tidy(c), "\(name): not tidy afterwards")
        // Covered part way and uncovered much later: straight back to normal, no fireworks.
        for at in [0.3, 1.0, 1.6, 2.2, 2.8] {
            let c2 = makeSim(screen)
            c2.entrance = Entrance(start: c2.fakeT!, enter: enter, exit: exit)
            c2.every = 1e6; step(c2, to: at); c2.fakeT! += 600; c2.update(); step(c2, to: c2.fakeT! + 1)
            check(tidy(c2), "\(name): paused at \(at)s, not tidy")
        }
    } }
    // Entrances come round on their own, every one different from the last.
    do {
        let c = makeSim(screen)
        c.nextEntrance = 2
        var seen: [Int] = []
        step(c, to: 2 + 4 * (c.every + 5)) { if let e = c.entrance, seen.last != e.enter * 2 + e.exit { seen.append(e.enter * 2 + e.exit) } }
        check(seen.count >= 4 && Set(seen.prefix(4)).count == 4, "rotation: \(seen)")
    }
    // Typing: arms in, hands out, and all back afterwards.
    do {
        let c = makeSim(screen)
        c.typingStart = 1; c.typingEnd = 3
        var handsOut = false
        step(c, to: 2) { if c.handL.opacity > 0.99 { handsOut = true } }
        check(handsOut, "typing: hands never on the keys")
        check(c.look.y > 0.2, "typing: not looking at the laptop")
        step(c, to: 4)
        check(c.handL.opacity < 0.01 && abs(c.armL.position.x - c.pt(2, 0).x) < 0.5, "typing: arms not back")
    }
    // Eyes follow the cursor.
    do {
        let c = makeSim(screen)
        c.fakeMouse = CGPoint(x: c.center.x - 500, y: c.center.y); step(c, to: 1)
        let leftX = c.eyeL.position.x
        c.fakeMouse = CGPoint(x: c.center.x + 500, y: c.center.y); step(c, to: 2)
        check(c.eyeL.position.x - leftX > 1.5 * c.u, "eyes: don't follow the cursor")
    }
    for f in failures { print("FAIL", f) }
    print(failures.isEmpty ? "all good" : "\(failures.count) failures")
    return failures.isEmpty
}

// MARK: - Entry

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let every = max(0.05, option("--every").flatMap(Double.init) ?? defaultEveryMinutes)
if args.first == "--selftest" { _ = NSApplication.shared; exit(selftest() ? 0 : 1) }
if args.first == "--frames", args.count >= 2 { _ = NSApplication.shared; renderFrames(dir: args[1], wallpaper: args.count > 2 ? args[2] : nil); exit(0) }

// Installed as ClawdWallpaper.app, he opens at login like any other app.
if Bundle.main.bundleURL.pathExtension == "app" {
    let login = SMAppService.mainApp
    if args.contains("--no-login") { try? login.unregister(); print("removed from login items"); exit(0) }
    if login.status != .enabled { do { try login.register() } catch { print("couldn't add to login items: \(error)") } }
}

// Only ever one copy running.
let lock = open(NSTemporaryDirectory() + "clawd-wallpaper.lock", O_CREAT | O_RDWR, 0o600)
if flock(lock, LOCK_EX | LOCK_NB) != 0 { print("already running"); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.every = every
controller.start()
app.run()
