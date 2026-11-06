// Clawd on the desktop: a tiny pixel mascot in a Santa hat, floating in the Berserk night sky.
//   ClawdWallpaper                     live mode (desktop-level window, sits under icons)
//   ClawdWallpaper --bake in.jpg out.jpg   static copy of the wallpaper with Clawd drawn in
//   ClawdWallpaper --sheet out.png         contact sheet of poses, for checking the art
import AppKit

// Positions are fractions of the wallpaper image (y from the top), so the art lines up with it.
let imageSize = CGSize(width: 7680, height: 4320)
let anchorFrac = CGPoint(x: 0.19, y: 0.50)
let moonFrac = CGPoint(x: 0.3125, y: 0.11)
let gutsFrac = CGPoint(x: 0.815, y: 0.435)
let baseUnit: CGFloat = 8          // points per sprite pixel on a 1710pt-wide screen

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}
let orange = rgb(0xD97757), eyeBlack = rgb(0x141210)
let red = rgb(0xCF3A30), redDark = rgb(0x9C2620), redLight = rgb(0xE8564A)
let white = rgb(0xF4EFE6), whiteShade = rgb(0xC9C2B6)

struct Pose: Hashable {
    var lookX: CGFloat = 0     // -1...1 in half-pixel steps
    var lookY: CGFloat = 0     // -0.5...0.5, positive is down
    var blink = false
    var happy = false          // > < eyes when the cursor is on him
    var bob: CGFloat = 0
    var wave = 0               // 0 down, 1 and 2 are the two waving frames
    var legs = 0               // 0 still, 1 and 2 tippy-tap
    var tail = 0               // -1, 0, 1: pompom swing
    var status = ""
    var detail = ""
}

// y grows downward in sprite space; (9, 3.5) is the centre of his body.
func drawSprite(_ c: CGContext, center: CGPoint, u: CGFloat, pose p: Pose) {
    c.setShouldAntialias(false)
    func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        c.setFillColor(col)
        c.fill(CGRect(x: center.x + (x - 9) * u, y: center.y - (y - 3.5 + p.bob + h) * u, width: w * u, height: h * u))
    }
    // Legs
    let lift: (CGFloat, CGFloat) = p.legs == 1 ? (0.75, 0) : p.legs == 2 ? (0, 0.75) : (0, 0)
    px(4, 6, 1, 1.5 - lift.0, orange); px(6, 6, 1, 1.5 - lift.1, orange)
    px(11, 6, 1, 1.5 - lift.0, orange); px(13, 6, 1, 1.5 - lift.1, orange)
    // Body and arms
    px(3, 0, 12, 6, orange)
    px(1, 3, 2, 1, orange)
    switch p.wave {
    case 1: px(15, 2, 1, 1, orange); px(16, 1, 1, 1, orange)
    case 2: px(15, 3, 1, 1, orange); px(16, 2, 1, 1, orange)
    default: px(15, 3, 2, 1, orange)
    }
    // Eyes
    for ex in [CGFloat(5), 11.5] {
        let x = ex + p.lookX, y = 1.5 + p.lookY
        if p.happy {
            let left = ex == 5
            px(left ? 5 : 12.5, 1.5, 0.75, 0.75, eyeBlack)
            px(left ? 5.75 : 11.75, 2.25, 0.75, 0.75, eyeBlack)
            px(left ? 5 : 12.5, 3, 0.75, 0.75, eyeBlack)
        } else if p.blink {
            px(x, y + 1, 1.5, 0.25, eyeBlack)
        } else {
            px(x, y, 1.5, 2, eyeBlack)
        }
    }
    // Hat: slumped to the right, towards Guts.
    px(5, -2, 8, 1, red);  px(6, -3, 7, 1, red);  px(7, -4, 6, 1, red);  px(9, -5, 4, 1, red)
    px(11, -2, 2, 1, redDark); px(11.5, -3, 1.5, 1, redDark); px(12, -4, 1, 1, redDark)
    px(6, -2, 1, 1, redLight); px(7, -3, 1, 1, redLight); px(8, -4, 1, 1, redLight)
    let t = CGFloat(p.tail)
    px(11 + t * 0.5, -6, 3, 1, red); px(12.5 + t * 0.5, -6, 1.5, 1, redDark)
    px(13.5 + t, -5, 1.5, 1, red)
    // Fur trim
    px(4, -1, 10, 1, white); px(4, -0.5, 10, 0.5, whiteShade)
    // Pompom
    let bx = 14.5 + t * 1.5, by = -4.5 - abs(t) * 0.5
    px(bx + 0.5, by, 2, 3, white); px(bx, by + 0.5, 3, 2, white)
    px(bx + 0.5, by + 2.5, 2, 0.5, whiteShade); px(bx + 2.5, by + 1, 0.5, 1.5, whiteShade)
}

func drawGlow(_ c: CGContext, center: CGPoint, u: CGFloat) {
    let colors = [rgb(0xE8743F, 0.34), rgb(0xD9633A, 0.13), rgb(0xB84A2E, 0.035), rgb(0xB84A2E, 0)] as CFArray
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.32, 0.68, 1])!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 30 * u,
                         options: [])
}

func drawStatus(_ c: CGContext, center: CGPoint, u: CGFloat, pose p: Pose) {
    guard !p.status.isEmpty else { return }
    c.setShouldAntialias(true)
    let size = 13 * u / baseUnit
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    let text = NSMutableAttributedString(string: p.status, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: rgb(0xE8895F))!])
    text.append(NSAttributedString(string: "  " + p.detail, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: rgb(0x8A8580))!]))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    text.draw(at: CGPoint(x: center.x - 8 * u, y: center.y - 7.75 * u))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Behaviour

let spinner = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
let verbs = [
    "Struggling…", "Contemplating the moon…", "Sharpening Dragonslayer…", "Awaiting Guts's approval…",
    "Compacting 200 years of trauma…", "Resisting the Beast of Darkness…", "Delegating to Puck…",
    "Asking permission to swing…", "Hanging tinsel on a giant slab of iron…", "Reading CLAUDE.md…",
    "Checking the naughty list (long)…", "Rewriting fate in Rust…", "Too big, too thick, too heavy…",
]

final class Brain {
    var pose = Pose()
    var lastMouse = NSEvent.mouseLocation
    var lastMouseMove = Date.timeIntervalSinceReferenceDate
    let start = Date.timeIntervalSinceReferenceDate
    var nextBlink = 0.0, blinkUntil = 0.0
    var nextIdle = 0.0, idleTarget: CGPoint? = nil
    var waveUntil = 0.0, tapUntil = 0.0, nextTap = 20.0
    var verbIndex = Int.random(in: 0..<verbs.count), verbStart = 0.0
    var flickUntil = 0.0

    func tick(center: CGPoint, u: CGFloat, moon: CGPoint, guts: CGPoint) {
        let now = Date.timeIntervalSinceReferenceDate, t = now - start
        let mouse = NSEvent.mouseLocation
        if hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 1 {
            lastMouse = mouse; lastMouseMove = now; idleTarget = nil
        }
        // What he's looking at: the cursor, or when you stop moving, the moon or Guts.
        var target = mouse
        if now - lastMouseMove > 10 {
            if t > nextIdle {
                nextIdle = t + Double.random(in: 5...13)
                switch Int.random(in: 0..<10) {
                case 0...3: idleTarget = moon
                case 4...7:
                    idleTarget = guts
                    if Bool.random() { waveUntil = t + 3.0 }  // Guts never waves back
                default: idleTarget = center
                }
            }
            target = idleTarget ?? center
        }
        let dx = target.x - center.x, dy = target.y - center.y, d = max(hypot(dx, dy), 0.001)
        let mag = min(1, d / (24 * u))
        pose.lookX = ((dx / d * mag) * 2).rounded() / 2
        pose.lookY = ((-dy / d * mag * 0.5) * 4).rounded() / 4

        // Cursor right on top of him: happy eyes, excited wiggle.
        let onHim = now - lastMouseMove < 10 && hypot(mouse.x - center.x, mouse.y - center.y) < 9 * u
        pose.happy = onHim
        if t > nextBlink {
            blinkUntil = t + 0.13
            nextBlink = t + (Int.random(in: 0..<5) == 0 ? 0.28 : Double.random(in: 2.5...6.5))
        }
        pose.blink = t < blinkUntil

        let period = onHim ? 0.5 : 3.4
        pose.bob = (sin(t * 2 * .pi / period)).rounded() * 0.25
        pose.tail = Int((sin(t * 2 * .pi / period + 0.9) * 1.3).rounded())

        pose.wave = t < waveUntil ? (Int(t * 5) % 2 == 0 ? 1 : 2) : 0
        if t > nextTap { tapUntil = t + 1.4; nextTap = t + Double.random(in: 25...70) }
        pose.legs = (t < tapUntil || onHim) ? (Int(t * 7) % 2 == 0 ? 1 : 2) : 0

        // Status line, Claude Code style.
        if t - verbStart > 16 { verbIndex = (verbIndex + 1) % verbs.count; verbStart = t }
        pose.status = spinner[Int(t * 5) % spinner.count] + " " + verbs[verbIndex]
        pose.detail = "(\(Int(t - verbStart))s · esc to interrupt)"
    }
}

// MARK: - Live mode

final class GlowView: NSView {
    var u: CGFloat = baseUnit
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        drawGlow(c, center: CGPoint(x: bounds.midX, y: bounds.midY), u: u)
    }
}

final class SpriteView: NSView {
    var u: CGFloat = baseUnit
    var pose = Pose()
    override func draw(_ r: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        drawSprite(c, center: center, u: u, pose: pose)
        drawStatus(c, center: center, u: u, pose: pose)
    }
}

final class Overlay {
    let window: NSWindow, sprite = SpriteView(), brain = Brain()
    let center: CGPoint, u: CGFloat, moon: CGPoint, guts: CGPoint

    init(screen: NSScreen) {
        // Same maths as the "Crop" wallpaper placement: aspect fill, centred.
        let f = screen.frame
        let scale = max(f.width / imageSize.width, f.height / imageSize.height)
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: f.midX + (p.x - 0.5) * shown.width, y: f.midY - (p.y - 0.5) * shown.height)
        }
        center = map(anchorFrac); moon = map(moonFrac); guts = map(gutsFrac)
        let scaleF = screen.backingScaleFactor
        u = ((baseUnit * f.width / 1710) * scaleF).rounded() / scaleF
        let w = 110 * u, h = 62 * u  // wide enough for the longest status line
        let frame = NSRect(x: (center.x - w / 2).rounded(), y: (center.y - h / 2).rounded(), width: w, height: h)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        let glow = GlowView(frame: root.bounds); glow.u = u; glow.wantsLayer = true
        sprite.frame = root.bounds; sprite.u = u; sprite.wantsLayer = true
        root.addSubview(glow); root.addSubview(sprite)
        window.contentView = root
        window.orderFront(nil)
        window.setFrame(frame, display: true)
    }

    func tick() {
        brain.tick(center: center, u: u, moon: moon, guts: guts)
        if brain.pose != sprite.pose { sprite.pose = brain.pose; sprite.needsDisplay = true }
    }
}

final class Controller: NSObject {
    var overlays: [Overlay] = []
    var timer: Timer?
    func rebuild() {
        overlays.forEach { $0.window.orderOut(nil) }
        overlays = NSScreen.screens.map { Overlay(screen: $0) }
    }
    func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in self?.overlays.forEach { $0.tick() } }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stopTimer() { timer?.invalidate(); timer = nil }
    func run() {
        rebuild(); startTimer()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.stopTimer() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.startTimer() }
    }
}

// MARK: - Static output

func writeImage(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let isPNG = path.lowercased().hasSuffix(".png")
    let type = (isPNG ? "public.png" : "public.jpeg") as CFString
    guard let dest = CGImageDestinationCreateWithURL(url, type, 1, nil) else { fatalError("cannot write \(path)") }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(path)") }
}

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func bake(input: String, output: String) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(input)") }
    let c = context(img.width, img.height)
    c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    // On a 1710pt display this image is shown at 1107/4320, so match the live sprite's size.
    let u = (baseUnit / (1107 / CGFloat(img.height))).rounded()
    let center = CGPoint(x: (CGFloat(img.width) * anchorFrac.x).rounded(), y: (CGFloat(img.height) * (1 - anchorFrac.y)).rounded())
    drawGlow(c, center: center, u: u)
    let pose = Pose(lookX: 1, lookY: -0.25, status: "✻ Struggling…", detail: "(esc to interrupt)")
    drawSprite(c, center: center, u: u, pose: pose)
    drawStatus(c, center: center, u: u, pose: pose)
    writeImage(c.makeImage()!, to: output)
}

func sheet(output: String) {
    let poses: [Pose] = [
        Pose(status: "✻ Struggling…", detail: ""),
        Pose(lookX: 1, lookY: -0.25, tail: 1),
        Pose(lookX: -1, lookY: 0.5, tail: -1),
        Pose(lookX: 0.5, lookY: -0.5, blink: true),
        Pose(lookX: 1, wave: 1, legs: 1),
        Pose(lookX: 1, wave: 2, legs: 2),
        Pose(happy: true, bob: 0.25, legs: 1),
        Pose(lookX: 1, lookY: -0.5, status: "✶ Delegating to Puck…", detail: ""),
    ]
    let cell = 620, cols = 4, rows = 2
    let c = context(cell * cols, cell * rows)
    c.setFillColor(rgb(0x000000)); c.fill(CGRect(x: 0, y: 0, width: cell * cols, height: cell * rows))
    for (i, p) in poses.enumerated() {
        let center = CGPoint(x: cell * (i % cols) + cell / 2, y: cell * (rows - 1 - i / cols) + cell / 2 + 20)
        c.saveGState(); c.clip(to: CGRect(x: cell * (i % cols), y: cell * (rows - 1 - i / cols), width: cell, height: cell))
        drawGlow(c, center: center, u: 16)
        drawSprite(c, center: center, u: 16, pose: p)
        drawStatus(c, center: center, u: 16, pose: p)
        c.restoreGState()
    }
    writeImage(c.makeImage()!, to: output)
}

// MARK: - Entry

let args = CommandLine.arguments
if args.count == 4, args[1] == "--bake" { bake(input: args[2], output: args[3]); exit(0) }
if args.count == 3, args[1] == "--sheet" { sheet(output: args[2]); exit(0) }

// Only ever one copy running.
let lock = open(NSTemporaryDirectory() + "clawd-wallpaper.lock", O_CREAT | O_RDWR, 0o600)
if flock(lock, LOCK_EX | LOCK_NB) != 0 { print("already running"); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.run()
app.run()
