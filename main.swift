// Clawd on the desktop: a tiny pixel mascot floating in the Berserk night sky.
//   ClawdWallpaper                         live mode (desktop-level window, sits under icons)
//   ClawdWallpaper --hat crown --wear cape,sword  choose what he wears (--list shows everything)
//   ClawdWallpaper --demo sword|eclipse|snow|sleep|dizzy|battery|click   run a scene right away
//   ClawdWallpaper --bake in.jpg out.jpg   static copy of the wallpaper with Clawd drawn in
//   ClawdWallpaper --sheet out.png         contact sheet of poses, for checking the art
//   ClawdWallpaper --selftest              run every outfit through every scene and check the results
//   ClawdWallpaper --frames dir [wallpaper.jpg]   render each scene to a sheet of frames
//
// Built to cost almost nothing: art is drawn at 4 pixels per sprite pixel and scaled by the GPU,
// nothing updates unless it changed, the tick rate drops when nothing is happening, and it all
// pauses while the desktop is covered or the display is asleep.
import AppKit
import IOKit.ps

// Positions are fractions of the wallpaper image (y from the top), so the art lines up with it.
let imageSize = CGSize(width: 7680, height: 4320)
let anchorFrac = CGPoint(x: 0.19, y: 0.50)
let moonFrac = CGPoint(x: 0.313, y: 0.104)
let moonRadiusFrac: CGFloat = 0.066          // of image height
let gutsFrac = CGPoint(x: 0.815, y: 0.435)
let baseUnit: CGFloat = 12                   // points per sprite pixel on a 1710pt-wide screen
let spritePx: CGFloat = 4                    // bitmap pixels per sprite pixel in live mode
let canvasUnits: CGFloat = 40                // live sprite canvas, in sprite pixels
let swordLength: CGFloat = 72, swordHeight: CGFloat = 14
let swordMeanSeconds = 1500.0, eclipseMeanSeconds = 14400.0   // of visible time

func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}
let orange = rgb(0xD97757), eyeBlack = rgb(0x141210)
let red = rgb(0xCF3A30), redDark = rgb(0x9C2620), redLight = rgb(0xE8564A)
let white = rgb(0xF4EFE6), whiteShade = rgb(0xC9C2B6)
let wiz = rgb(0x4A3FA8), wizDark = rgb(0x322A7A), wizLight = rgb(0x6A5ED0), gold = rgb(0xF2C14E)
let cape = rgb(0x3A3A44), capeLight = rgb(0x7E7E8C)
let iron = rgb(0x3C3D44), ironLight = rgb(0x7B7D86), ironDark = rgb(0x212227)
let bone = rgb(0xE6DCC3)
let pink = rgb(0xE85C9C), cyan = rgb(0x4FC3D9), steel = rgb(0x8E9299), steelLight = rgb(0xC4C8CE), brown = rgb(0x6B4A2E)

// To add an item: add a case here, then draw it in drawHat or drawGear.
enum Hat: String, CaseIterable { case santa, wizard, crown, party, viking, helm, none }
enum Gear: String, CaseIterable { case cape, armor, scarf, sword }

// The default look follows the calendar.
func hatForToday() -> Hat {
    switch Calendar.current.component(.month, from: Date()) {
    case 12: return .santa
    case 9...11: return .wizard
    default: return .none
    }
}
func gearForToday() -> [Gear] { hatForToday() == .none ? [.cape] : [] }

enum Eyes: Hashable { case normal, blink, happy, wide, tired, dizzy(Int) }

struct Pose: Hashable {
    var lookX: CGFloat = 0     // -1...1 in half-pixel steps
    var lookY: CGFloat = 0     // -0.5...0.5, positive is down
    var eyes = Eyes.normal
    var bob: CGFloat = 0       // only used for stills; live mode moves the layer instead
    var wave = 0               // 0 down, 1 and 2 are the two waving frames
    var legs = 0               // 0 still, 1 and 2 are the stepping frames
    var tail = 0               // -1, 0, 1: hat tip or cape swing
    var hat = Hat.santa
    var gear: [Gear] = []
    var crooked = false
    var snow = 0               // flakes settled on him, 0...6
    var z = -1                 // sleeping "z" frame, -1 for none
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
    let t = CGFloat(p.tail)
    if p.gear.contains(.sword) {   // a tiny slab strapped to his back, far too big even so
        for i in 0..<15 {
            let k = CGFloat(i)
            px(14 - k * 0.5, -6.5 + k, 3, 1, steel); px(14 - k * 0.5, -6.5 + k, 1, 1, steelLight)
        }
        px(13, -7.25, 5, 0.75, ironLight); px(14.75, -9.75, 1.25, 2.5, brown); px(14.5, -10.25, 1.75, 0.5, ironLight)
    }
    if p.gear.contains(.cape) {    // a tiny torn black cape
        let sway = t * 0.5
        px(2, 0.5, 1.5, 1, cape); px(1, 1.5, 2.5, 1, cape); px(0, 2.5, 3.5, 1, cape)
        px(-1 + sway * 0.5, 3.5, 4.5, 1, cape); px(-2.5 + sway, 4.5, 6, 1, cape); px(-3.5 + sway, 5.5, 7, 1, cape)
        px(-4 + sway * 2, 6.5, 6.5, 1, cape)
        px(-4 + sway * 2, 7.5, 1.5, 1, cape); px(-1.5 + sway * 2, 7.5, 1.5, 0.75, cape); px(1 + sway, 7.5, 1.25, 1, cape)
        px(-4 + sway * 2, 8.5, 0.75, 0.75, cape)
        px(2, 0.5, 1, 0.5, capeLight); px(1, 1.5, 1, 0.5, capeLight); px(0, 2.5, 1, 0.5, capeLight)
        px(-1 + sway * 0.5, 3.5, 1, 0.5, capeLight); px(-2.5 + sway, 4.5, 1.25, 0.5, capeLight)
        px(-3.5 + sway, 5.5, 1, 0.5, capeLight); px(-4 + sway * 2, 6.5, 0.75, 0.5, capeLight)
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
        let left = ex == 5
        let x = ex + p.lookX, y = 1.5 + p.lookY
        switch p.eyes {
        case .happy:
            px(left ? 5 : 12.5, 1.5, 0.75, 0.75, eyeBlack)
            px(left ? 5.75 : 11.75, 2.25, 0.75, 0.75, eyeBlack)
            px(left ? 5 : 12.5, 3, 0.75, 0.75, eyeBlack)
        case .blink: px(x, y + 1, 1.5, 0.25, eyeBlack)
        case .tired: px(x, y + 1, 1.5, 1, eyeBlack)
        case .wide:
            px(x - 0.25, y - 0.5, 2, 3, eyeBlack)
            px(x + 0.25, y, 0.5, 0.5, white)
        case .dizzy(let f):
            // A hollow ring with a gap chasing round it, and a dot in the middle.
            let cell: CGFloat = 0.5
            var ring: [(CGFloat, CGFloat)] = []
            for i in 0..<4 { ring.append((CGFloat(i), 0)) }
            for i in 0..<4 { ring.append((4, CGFloat(i))) }
            for i in 0..<4 { ring.append((4 - CGFloat(i), 4)) }
            for i in 0..<4 { ring.append((0, 4 - CGFloat(i))) }
            let gap = (left ? f * 2 : 16 - f * 2) % 16
            let bx = ex - 0.5, by: CGFloat = 1.25
            for (i, r) in ring.enumerated() where (i - gap + 16) % 16 >= 4 {
                px(bx + r.0 * cell, by + r.1 * cell, cell, cell, eyeBlack)
            }
            px(bx + cell * 2, by + cell * 2, cell, cell, eyeBlack)
        case .normal: px(x, y, 1.5, 2, eyeBlack)
        }
    }
    // Headwear. When crooked it slides down over his left eye.
    let dx: CGFloat = p.crooked ? -2.5 : 0, dy: CGFloat = p.crooked ? 1 : 0
    func hat(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) { px(x + dx, y + dy, w, h, col) }
    if p.gear.contains(.armor) {   // Black plate over the belly and shoulders, a joke of a Berserker suit.
        px(3, 4.25, 12, 1.75, iron); px(3, 4.25, 12, 0.5, ironLight)
        for x in [4.5, 7.5, 10.5, 13] as [CGFloat] { px(x, 5, 0.75, 1, ironDark) }
        let up: CGFloat = p.wave == 1 ? 1.5 : p.wave == 2 ? 0.75 : 0   // the right shoulder rides up with a wave
        px(0.5, 2.25, 3, 2, iron); px(14.5, 2.25 - up, 3, 2, iron)
        px(0.5, 2.25, 3, 0.5, ironLight); px(14.5, 2.25 - up, 3, 0.5, ironLight)
        px(0, 1.25, 1, 1, ironDark); px(2, 1.25, 1, 1, ironDark); px(15, 1.25 - up, 1, 1, ironDark); px(17, 1.25 - up, 1, 1, ironDark)
    }
    if p.gear.contains(.scarf) {
        px(3, 3.75, 12, 1.25, red); px(3, 4.5, 12, 0.5, redDark)
        px(12.5 + t * 0.5, 5, 1.5, 2.25, red); px(12.5 + t * 0.5, 6.75, 1.5, 0.5, white)
    }
    drawHat(p.hat, t: t, crooked: p.crooked, hat)
    // Snow that has settled on him.
    let spots = snowSpots(p.hat)
    for i in 0..<min(p.snow, spots.count) { hat(spots[i].0, spots[i].1, 1, 0.75, white) }
    // Sleeping z
    if p.z >= 0 {
        let f = CGFloat(p.z), s: CGFloat = 0.5 + f * 0.25, zx = 17 + f * 2, zy = -7 - f * 3
        let col = rgb(0xD9D3C8)
        px(zx, zy, s * 3, s, col); px(zx + s * 2, zy + s, s, s, col); px(zx + s, zy + s * 2, s, s, col); px(zx, zy + s * 3, s * 3, s, col)
    }
}

typealias Paint = (CGFloat, CGFloat, CGFloat, CGFloat, CGColor) -> Void

func drawHat(_ kind: Hat, t: CGFloat, crooked: Bool, _ hat: Paint) {
    switch kind {
    case .santa:
        hat(5, -2, 8, 1, red);  hat(6, -3, 7, 1, red);  hat(7, -4, 6, 1, red);  hat(9, -5, 4, 1, red)
        hat(11, -2, 2, 1, redDark); hat(11.5, -3, 1.5, 1, redDark); hat(12, -4, 1, 1, redDark)
        hat(6, -2, 1, 1, redLight); hat(7, -3, 1, 1, redLight); hat(8, -4, 1, 1, redLight)
        hat(11 + t * 0.5, -6, 3, 1, red); hat(12.5 + t * 0.5, -6, 1.5, 1, redDark)
        hat(13.5 + t, -5, 1.5, 1, red)
        hat(4, -1, 10, 1, white); hat(4, -0.5, 10, 0.5, whiteShade)
        if crooked { hat(4, 0, 4, 1, white); hat(4, 0.5, 4, 0.5, whiteShade) }
        let bx = 14.5 + t * 1.5, by = -4.5 - abs(t) * 0.5
        hat(bx + 0.5, by, 2, 3, white); hat(bx, by + 0.5, 3, 2, white)
        hat(bx + 0.5, by + 2.5, 2, 0.5, whiteShade); hat(bx + 2.5, by + 1, 0.5, 1.5, whiteShade)
    case .wizard:
        hat(5, -2, 8, 1, wiz);  hat(5.5, -3, 7, 1, wiz);  hat(6.5, -4, 5.5, 1, wiz)
        hat(7, -5, 4.5, 1, wiz); hat(8, -6, 3, 1, wiz); hat(9, -7, 2, 1, wiz)
        hat(10.5 + t * 0.5, -8, 2, 1, wiz); hat(12 + t, -7.5, 1.5, 1, wizDark)
        hat(11, -2, 2, 1, wizDark); hat(10.5, -3, 2, 1, wizDark); hat(10.5, -4, 1.5, 1, wizDark)
        hat(6, -2, 1, 1, wizLight); hat(6.5, -3, 1, 1, wizLight); hat(7.5, -4, 1, 1, wizLight)
        hat(8.5, -4.5, 1, 1, gold); hat(8.25, -6, 0.75, 0.75, gold)
        hat(5, -2.5, 8, 0.5, gold)
        hat(2.5, -1, 13, 1, wizDark); hat(2.5, -1, 13, 0.5, wizLight)
    case .crown:
        hat(5, -2, 8, 2, gold); hat(5, -3, 1, 1, gold); hat(8.5, -3.5, 1, 1.5, gold); hat(12, -3, 1, 1, gold)
        hat(5, -0.5, 8, 0.5, rgb(0xB88A24))
        hat(6.5, -1.5, 1, 1, red); hat(8.5, -1.5, 1, 1, cyan); hat(10.5, -1.5, 1, 1, red)
    case .party:
        hat(6, -1, 6, 1, pink); hat(6.5, -2, 5, 1, cyan); hat(7, -3, 4, 1, pink)
        hat(7.5, -4, 3, 1, cyan); hat(8, -5, 2, 1, pink)
        hat(8.25 + t * 0.5, -6.5, 1.5, 1.5, gold)
    case .viking:
        hat(4, -2, 10, 2, steel); hat(5, -3, 8, 1, steel); hat(6.5, -3.75, 5, 0.75, steelLight)
        hat(4, -1, 10, 1, brown); hat(8.5, -3, 1, 3, rgb(0x5C5F66))
        hat(2, -2.5, 2, 1, bone); hat(1.5, -3.5, 1.5, 1, bone); hat(1.5, -4.5, 1, 1, bone)
        hat(14, -2.5, 2, 1, bone); hat(15, -3.5, 1.5, 1, bone); hat(15.5, -4.5, 1, 1, bone)
    case .helm:   // a very small wolf, a very big attitude
        hat(3, -2, 12, 3, iron); hat(4, -3, 10, 1, iron); hat(3, -2, 12, 0.5, ironLight)
        hat(4, -4.5, 1.5, 1.5, iron); hat(12.5, -4.5, 1.5, 1.5, iron); hat(4, -5, 1, 0.5, ironDark); hat(13, -5, 1, 0.5, ironDark)
        for x in [5, 7, 9, 11] as [CGFloat] { hat(x, 0.5, 1, 0.75, bone) }
    case .none:
        break
    }
}

func snowSpots(_ kind: Hat) -> [(CGFloat, CGFloat)] {
    switch kind {
    case .santa: return [(8, -5.75), (10, -6.5), (6.5, -3.75), (11.5, -6.75), (5.5, -2.75), (9, -6.25)]
    case .wizard: return [(9, -7.75), (7.5, -5.75), (6.5, -4.75), (2.75, -1.5), (14, -1.5), (5.5, -3.75)]
    case .crown: return [(5.5, -2.75), (8.5, -4.25), (11.5, -2.75), (7, -2.5), (10, -2.5), (9.5, -2.5)]
    case .party: return [(8.25, -7.25), (7.5, -5.5), (9.5, -5.5), (6.75, -3.5), (10.25, -3.5), (8.5, -5.75)]
    case .viking: return [(7, -4.5), (9, -4.5), (11, -4.5), (5.5, -3.5), (12, -3.5), (8, -4.5)]
    case .helm: return [(6, -3.5), (8, -3.5), (10, -3.5), (12, -3.5), (4, -5.5), (13, -5.5)]
    case .none: return [(5, -0.5), (8, -0.5), (11, -0.5), (6.5, -0.75), (9.5, -0.75), (13, -0.5)]
    }
}

func drawGlow(_ c: CGContext, center: CGPoint, radius: CGFloat) {
    let colors = [rgb(0xE8743F, 0.34), rgb(0xD9633A, 0.13), rgb(0xB84A2E, 0.035), rgb(0xB84A2E, 0)] as CFArray
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.32, 0.68, 1])!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func statusString(_ status: String, _ detail: String, size: CGFloat) -> NSAttributedString {
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    let text = NSMutableAttributedString(string: status, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: rgb(0xE8895F))!])
    if !detail.isEmpty {
        text.append(NSAttributedString(string: "  " + detail, attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: rgb(0x8A8580))!]))
    }
    return text
}

func drawText(_ c: CGContext, _ text: NSAttributedString, at p: CGPoint) {
    c.setShouldAntialias(true)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    text.draw(at: p)
    NSGraphicsContext.restoreGraphicsState()
}

func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// The big slab. x runs hilt to tip, in sprite pixels.
func makeSwordImage() -> CGImage {
    let p = spritePx, c = context(Int(swordLength * p), Int(swordHeight * p))
    c.setShouldAntialias(false)
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        c.setFillColor(col); c.fill(CGRect(x: x * p, y: (y + swordHeight / 2) * p, width: w * p, height: h * p))
    }
    func cut(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        c.clear(CGRect(x: x * p, y: (y + swordHeight / 2) * p, width: w * p, height: h * p))
    }
    let blade = rgb(0x6A6E75), top = rgb(0xDADDE0), upper = rgb(0x8B8F96), low = rgb(0x3F4147), ink = rgb(0x26272B)
    let wrap = rgb(0x33261D), wrapLight = rgb(0x5E4736)
    // Pommel and a long, wrapped grip
    r(0, -1.75, 1.75, 3.5, low); r(0, 1.25, 1.75, 0.5, upper)
    r(1.75, -1.25, 8, 2.5, wrap)
    for i in 0..<4 { r(2.25 + CGFloat(i) * 2, -1.25, 0.75, 2.5, wrapLight) }
    // A plain, stubby guard
    r(9.75, -6.5, 2, 13, low); r(9.75, 6, 2, 0.5, upper); r(9.75, -6.5, 0.5, 13, ink)
    // The slab itself, with a blunt angled tip
    r(11.75, -5.5, 54.25, 11, blade); r(66, -5, 2, 10, blade); r(68, -3.75, 2, 8, blade); r(70, -1.5, 2, 4.5, blade)
    r(11.75, 1.5, 54.25, 3, upper); r(66, 1.5, 2, 2.5, upper)
    r(11.75, 4.5, 54.25, 1, top); r(66, 4, 2, 1, top); r(68, 3.25, 2, 1, top); r(70, 2, 2, 1, top)
    r(11.75, -5.5, 54.25, 1.25, low); r(66, -5, 2, 1, low); r(68, -3.75, 2, 1, low)
    // Inked hatching along the shadow side, so it sits with the manga art
    var x: CGFloat = 12.5, i = 0
    while x < 66 {
        let len: CGFloat = [2.25, 3.25, 1.5, 2.75, 3.75][i % 5]
        r(x, -5.25, 0.5, len, ink)
        r(x + 0.5, -5.25 + len, 0.5, 0.75, low)
        x += [1.25, 1.75, 1, 2.25][i % 4]; i += 1
    }
    // Scars from years of hard use, and chips in both edges
    for (x, y, w) in [(15, 2.25, 6), (24, 0.5, 4), (30, 3, 3.5), (38, 1, 7), (47, 2.75, 3), (53, 0.25, 5), (61, 2.25, 3.5)] as [(CGFloat, CGFloat, CGFloat)] {
        r(x, y, w, 0.5, low); r(x + 0.5, y + 0.5, w - 1, 0.25, top)
    }
    for (x, w) in [(18, 1.25), (33, 0.75), (44, 1.5), (58, 1), (64, 0.75)] as [(CGFloat, CGFloat)] { cut(x, 5, w, 0.5) }
    for (x, w) in [(23, 1), (37, 1.5), (51, 0.75), (62, 1.25)] as [(CGFloat, CGFloat)] { cut(x, -5.5, w, 0.5) }
    return c.makeImage()!
}

func batteryPercent() -> Int? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for src in list {
        guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
              let pct = d[kIOPSCurrentCapacityKey] as? Int else { continue }
        return pct
    }
    return nil
}

// MARK: - Live mode

let spinner = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
let verbs = [
    "Struggling…", "Contemplating the moon…", "Sharpening Dragonslayer…", "Awaiting Guts's approval…",
    "Compacting 200 years of trauma…", "Resisting the Beast of Darkness…", "Delegating to Puck…",
    "Asking permission to swing…", "Hanging tinsel on a giant slab of iron…", "Reading CLAUDE.md…",
    "Checking the naughty list (long)…", "Rewriting fate in Rust…",
]

func noAnim(_ l: CALayer) { l.actions = ["position": NSNull(), "contents": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull()] }

struct Flake { let layer: CALayer; var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat; let lands: Bool; let born: Double }
enum Scene { case sword, eclipse }

final class Clawd {
    let screen: NSScreen
    let window: NSWindow
    let root: CALayer
    let glow = CALayer(), sprite = CALayer(), textLayer = CALayer(), spinLayer = CALayer()
    let home: CGPoint              // in window coordinates
    let center: CGPoint, moon: CGPoint, guts: CGPoint   // in screen coordinates
    let moonRadius: CGFloat
    let u: CGFloat, scale: CGFloat, homeToEdge: CGFloat
    let spriteCtx = context(Int(canvasUnits * spritePx), Int(canvasUnits * spritePx))
    let spinImages: [CGImage]
    let spinWidth: CGFloat

    var pose = Pose(), drawn: Pose? = nil
    var hatChoice: Hat?, gearChoice: [Gear]?
    var currentHat = Hat.santa, currentGear: [Gear] = []
    var drawnText = ""
    var pos = CGPoint.zero         // sprite pixels from home, y up
    var lastSpin = -1

    // Tests drive these instead of the real clock and cursor.
    var fakeT: Double? = nil, fakeMouse: CGPoint? = nil, randomEvents = true
    var now: Double { fakeT ?? (Date.timeIntervalSinceReferenceDate - start) }
    var mouseNow: CGPoint { fakeMouse ?? NSEvent.mouseLocation }

    // Time and input
    let start = Date.timeIntervalSinceReferenceDate
    var lastT = 0.0, lastMoveT = 0.0
    var lastMouse = NSEvent.mouseLocation
    var nextBlink = 2.0, blinkUntil = 0.0, nextIdle = 0.0, idleTarget: CGPoint? = nil
    var waveUntil = 0.0, tapUntil = 0.0, nextTap = 25.0
    var verbIndex = Int.random(in: 0..<verbs.count), verbStart = 0.0
    var nextSlow = 0.0, battery: Int? = nil, lateNight = false, simBattery: Int? = nil

    // Moods
    var sleeping = false, sleepForced = false
    var wideUntil = 0.0, hopStart = -10.0, hopHeight: CGFloat = 3, happyUntil = 0.0, flinchUntil = 0.0, flinchX: CGFloat = 0
    var crookedUntil = 0.0
    var shakeUntil = 0.0
    var dizzyUntil = 0.0, spin: CGFloat = 0, lastAngle: CGFloat? = nil, pulling = false, pullStart = 0.0

    // Snow
    var flakes: [Flake] = [], nextFlake = 12.0

    // Scenes
    var scene: Scene? = nil, sceneStart = 0.0
    var swordLayer: CALayer?
    var swordTimes = (leave: 2.2, push: 0.0, pant: 1.6, lift: 2.6, fall: 1.8, up: 0.5, stare: 2.6, pull: 0.0, back: 2.6)
    var moonWindow: NSWindow?, moonDisc: CALayer?, moonRing: CALayer?

    init(screen s: NSScreen, hat: Hat?, gear: [Gear]?, show: Bool = true) {
        screen = s
        hatChoice = hat; gearChoice = gear
        // Same maths as the "Crop" wallpaper placement: aspect fill, centred.
        let f = s.frame
        let fill = max(f.width / imageSize.width, f.height / imageSize.height)
        let shown = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: f.midX + (p.x - 0.5) * shown.width, y: f.midY - (p.y - 0.5) * shown.height)
        }
        center = map(anchorFrac); moon = map(moonFrac); guts = map(gutsFrac)
        moonRadius = moonRadiusFrac * shown.height
        scale = s.backingScaleFactor
        u = ((baseUnit * f.width / 1710) * scale).rounded() / scale
        homeToEdge = (center.x - f.minX) / u
        // Reaches from the screen edge to past the sword's tip; only as tall as he needs.
        let frame = NSRect(x: f.minX, y: (center.y - 30 * u).rounded(), width: (center.x - f.minX + 84 * u).rounded(), height: (60 * u).rounded())
        home = CGPoint(x: center.x - frame.minX, y: center.y - frame.minY)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        root = view.layer!
        window.contentView = view

        // Glow: drawn once, small, and scaled up. It's a soft gradient so that doesn't show.
        let gc = context(180, 180)
        drawGlow(gc, center: CGPoint(x: 90, y: 90), radius: 90)
        glow.contents = gc.makeImage()
        glow.bounds = CGRect(x: 0, y: 0, width: 60 * u, height: 60 * u)
        glow.position = home
        sprite.bounds = CGRect(x: 0, y: 0, width: canvasUnits * u, height: canvasUnits * u)
        sprite.magnificationFilter = .nearest
        spinLayer.anchorPoint = .zero; textLayer.anchorPoint = .zero

        // Spinner glyphs are rendered once and swapped.
        let size: CGFloat = 13
        var imgs: [CGImage] = []
        let probe = statusString("✻", "", size: size).size()
        spinWidth = (NSFont.monospacedSystemFont(ofSize: size, weight: .medium).maximumAdvancement.width * 2).rounded()
        let gw = Int(ceil(probe.width + 4) * scale), gh = Int(ceil(probe.height + 2) * scale)
        for g in spinner {
            let c = context(gw, gh); c.scaleBy(x: scale, y: scale)
            drawText(c, statusString(g, "", size: size), at: CGPoint(x: 1, y: 1))
            imgs.append(c.makeImage()!)
        }
        spinImages = imgs
        spinLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(gw) / scale, height: CGFloat(gh) / scale)
        let tx = home.x - 8 * u, ty = home.y - 7.75 * u
        spinLayer.position = CGPoint(x: tx, y: ty)
        textLayer.position = CGPoint(x: tx + spinWidth, y: ty)

        for l in [glow, sprite, textLayer, spinLayer] { noAnim(l); root.addSublayer(l) }
        if show { window.orderFront(nil) }
    }

    func close() {
        endEclipse(); window.orderOut(nil)
    }

    var visible: Bool { window.occlusionState.contains(.visible) || (moonWindow?.occlusionState.contains(.visible) ?? false) }

    var desiredInterval: TimeInterval {
        let t = lastT
        if sleeping { return 0.5 }
        if scene != nil || pulling || t < dizzyUntil || t - hopStart < 0.6 || t < shakeUntil || t < waveUntil || t < tapUntil || t - lastMoveT < 1.5 { return 1.0 / 12 }
        if tired || ProcessInfo.processInfo.isLowPowerModeEnabled { return 1.0 / 3 }
        return 1.0 / 6
    }

    var tired: Bool { (simBattery ?? battery ?? 100) < 10 }

    // MARK: Input

    func handleClick(at p: CGPoint) {
        guard !sleeping, scene == nil else { return }
        let d = hypot(p.x - (center.x + pos.x * u), p.y - (center.y + pos.y * u))
        if d < 9 * u {
            hopStart = lastT; hopHeight = 4; happyUntil = lastT + 0.9
        } else if d < 40 * u {
            flinchUntil = lastT + 0.35; wideUntil = lastT + 0.45
            flinchX = p.x > center.x ? -1 : 1
        }
    }

    func demo(_ name: String) {
        let t = now
        switch name {
        case "sword": startSword(t)
        case "eclipse": startEclipse(t)
        case "snow": pose.snow = 5; nextFlake = t + 0.5
        case "sleep": sleeping = true; sleepForced = true
        case "dizzy": dizzyUntil = t + 3.5
        case "battery": simBattery = 7
        case "click": handleClick(at: center)
        default: print("unknown demo \(name)")
        }
    }

    // MARK: Tick

    func tick() {
        let t = now
        let dt = min(t - lastT, 0.6); lastT = t
        let mouse = mouseNow
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 1
        if moved { lastMouse = mouse; lastMoveT = t; idleTarget = nil }
        let idle = t - lastMoveT

        if t > nextSlow {      // once a minute is plenty for these
            nextSlow = t + 60
            battery = batteryPercent()
            let hour = Calendar.current.component(.hour, from: Date())
            lateNight = hour < 6
            currentHat = hatChoice ?? hatForToday()
            currentGear = gearChoice ?? gearForToday()
        }

        // Sleep and waking
        if sleeping {
            if moved {
                sleeping = false; sleepForced = false
                hopStart = t; hopHeight = 5; wideUntil = t + 0.9
                verbStart = t
            }
        } else if scene == nil, idle > (lateNight ? 60 : 300) {
            sleeping = true
        }

        // Rare events
        if randomEvents, scene == nil, !sleeping, !tired, !pulling, t > dizzyUntil {
            if Double.random(in: 0..<1) < dt / eclipseMeanSeconds { startEclipse(t) }
            else if Double.random(in: 0..<1) < dt / swordMeanSeconds { startSword(t) }
        }

        // Defaults for this frame
        var p = Pose(hat: currentHat, gear: currentGear, snow: pose.snow)
        var status: String? = nil, detail: String? = nil
        var target = mouse
        var bobPeriod = tired ? 6.0 : 3.4
        var offset = CGPoint.zero
        var shake: CGFloat = 0
        var fallen = false

        // Idle looking: the cursor, or when you stop moving it, the moon or Guts.
        if idle > 10 {
            if t > nextIdle {
                nextIdle = t + Double.random(in: 5...13)
                switch Int.random(in: 0..<10) {
                case 0...3: idleTarget = moon
                case 4...7:
                    idleTarget = guts
                    if Bool.random() && !tired { waveUntil = t + 3.0 }  // Guts never waves back
                default: idleTarget = center
                }
            }
            target = idleTarget ?? center
        }

        // Chasing: the cursor circling him winds him up.
        let cdx = mouse.x - (center.x + pos.x * u), cdy = mouse.y - (center.y + pos.y * u)
        let cd = hypot(cdx, cdy)
        if scene == nil, !sleeping, t > dizzyUntil {
            spin *= CGFloat(exp(-dt / 1.5))
            if cd < 45 * u, cd > 6 * u, moved {
                let a = atan2(cdy, cdx)
                if let la = lastAngle {
                    var da = a - la
                    if da > .pi { da -= 2 * .pi } else if da < -.pi { da += 2 * .pi }
                    spin += da
                }
                lastAngle = a
            } else if cd >= 45 * u { lastAngle = nil }
            let wasPulling = pulling
            pulling = abs(spin) > 2 * .pi * 1.25
            if pulling && !wasPulling { pullStart = t }
            if (pulling && t - pullStart > 2.5) || (wasPulling && !pulling) {
                dizzyUntil = t + 3.5; spin = 0; pulling = false; lastAngle = nil
            }
            if pulling {
                let k = min(1, 14 * u / max(cd, 1))
                offset = CGPoint(x: cdx * k / u, y: cdy * k / u)
                status = "Being pulled into a causality stream…"; detail = ""
            }
        }

        // Scenes take over the body.
        var movedByScene = false
        if scene == .sword { movedByScene = updateSword(t, &p, &offset, &status, &detail, &target, &shake, &fallen) }
        if scene == .eclipse { updateEclipse(t, &p, &status, &detail, &target, &shake) }
        if scene == nil, !pulling { offset = .zero }

        // Eyes
        let dx = target.x - (center.x + pos.x * u), dy = target.y - (center.y + pos.y * u), d = max(hypot(dx, dy), 0.001)
        let mag = min(1, d / (24 * u))
        if scene == nil || p.lookX == 0 {
            p.lookX = ((dx / d * mag) * 2).rounded() / 2
            p.lookY = ((-dy / d * mag * 0.5) * 4).rounded() / 4
        }
        if t > nextBlink {
            blinkUntil = t + 0.2
            nextBlink = t + (Int.random(in: 0..<5) == 0 ? 0.35 : Double.random(in: 2.5...6.5))
        }
        let onHim = idle < 10 && cd < 9 * u && scene == nil && !sleeping
        if p.eyes == .normal {
            if t < dizzyUntil { p.eyes = .dizzy(Int(t * 8) % 8) }
            else if sleeping { p.eyes = .blink }
            else if t < wideUntil { p.eyes = .wide }
            else if onHim || t < happyUntil { p.eyes = .happy }
            else if t < blinkUntil { p.eyes = .blink }
            else if tired { p.eyes = .tired }
        }

        // Body language
        if onHim { bobPeriod = 0.5 }
        if t < dizzyUntil { bobPeriod = 0.8; shake += sin(CGFloat(t) * 9) * 0.5; status = status ?? "Seeing three moons…"; detail = detail ?? "" }
        if t < flinchUntil { offset.x += flinchX * 1.5 }
        if sleeping {
            bobPeriod = 5
            p.z = Int(t / 1.2) % 3
            status = "Sleeping…"; detail = "(esc to wake)"
        } else if t < wideUntil && t - hopStart < 1 && hopHeight == 5 {
            status = "I wasn't sleeping…"; detail = ""
        }
        p.tail = Int((sin(t * 2 * .pi / bobPeriod + 0.9) * 1.3).rounded())
        let bob = (sin(t * 2 * .pi / bobPeriod)).rounded() * 0.25
        p.wave = t < waveUntil && scene == nil && !sleeping ? (Int(t * 5) % 2 == 0 ? 1 : 2) : p.wave
        if t > nextTap { if scene == nil && !sleeping && !tired { tapUntil = t + 1.4 }; nextTap = t + Double.random(in: 25...70) }
        if p.legs == 0, (t < tapUntil || onHim), !sleeping { p.legs = Int(t * 6) % 2 == 0 ? 1 : 2 }
        if t < crookedUntil { p.crooked = true }

        // Snow
        updateSnow(t, dt, &p, &status, &detail, &shake)

        // Move toward wherever he should be. Home, usually.
        if !movedByScene {
            let k = CGFloat(min(1, dt * 7))
            pos.x += (offset.x - pos.x) * k; pos.y += (offset.y - pos.y) * k
            if abs(pos.x - offset.x) < 0.1 { pos.x = offset.x }
            if abs(pos.y - offset.y) < 0.1 { pos.y = offset.y }
        } else { pos = offset }

        // Hop
        var hop: CGFloat = 0
        let hs = (t - hopStart) / 0.45
        if hs >= 0, hs < 1 { hop = 4 * hopHeight * CGFloat(hs * (1 - hs)) }

        // Status text, Claude Code style.
        if t - verbStart > 16 { verbIndex = (verbIndex + 1) % verbs.count; verbStart = t }
        let line = status ?? verbs[verbIndex]
        let info = detail ?? (tired ? "" : "(\(Int(t - verbStart))s · esc to interrupt)")
        if tired && status == nil {
            setText("Running on fumes…", "(\(simBattery ?? battery ?? 0)% · esc to interrupt)")
        } else {
            setText(line, info)
        }
        let spinIndex = sleeping ? 0 : Int(t * 3) % spinner.count
        if spinIndex != lastSpin { lastSpin = spinIndex; spinLayer.contents = spinImages[spinIndex] }

        // Draw only if something changed.
        p.bob = 0
        pose = p
        if drawn != p {
            drawn = p
            spriteCtx.clear(CGRect(x: 0, y: 0, width: spriteCtx.width, height: spriteCtx.height))
            drawSprite(spriteCtx, center: CGPoint(x: spriteCtx.width / 2, y: spriteCtx.height / 2), u: spritePx, pose: p)
            sprite.contents = spriteCtx.makeImage()
        }
        let sx = home.x + (pos.x + shake) * u
        let sy = home.y + (pos.y + (fallen ? -2 : bob) + hop) * u
        let newPos = CGPoint(x: (sx * 2).rounded() / 2, y: (sy * 2).rounded() / 2)
        if sprite.position != newPos { sprite.position = newPos }
        let glowPos = CGPoint(x: ((home.x + pos.x * u) * 2).rounded() / 2, y: ((home.y + pos.y * u) * 2).rounded() / 2)
        if glow.position != glowPos { glow.position = glowPos }
        let tf = fallen ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        if sprite.affineTransform() != tf {
            sprite.setAffineTransform(tf)
            let ty = home.y + (fallen ? -15 : -7.75) * u   // he'd land on it otherwise
            spinLayer.position.y = ty; textLayer.position.y = ty
        }
    }

    func setText(_ status: String, _ detail: String) {
        let key = status + "|" + detail
        guard key != drawnText else { return }
        drawnText = key
        let s = statusString(status, detail, size: 13), size = s.size()
        let w = Int(ceil(size.width + 2) * scale), h = Int(ceil(size.height + 2) * scale)
        let c = context(w, h); c.scaleBy(x: scale, y: scale)
        drawText(c, s, at: CGPoint(x: 1, y: 1))
        textLayer.bounds = CGRect(x: 0, y: 0, width: CGFloat(w) / scale, height: CGFloat(h) / scale)
        textLayer.contents = c.makeImage()
    }

    // MARK: Snow

    func addFlake(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, lands: Bool, t: Double) {
        let l = CALayer(); noAnim(l)
        l.backgroundColor = white
        l.bounds = CGRect(x: 0, y: 0, width: 0.75 * u, height: 0.75 * u)
        l.position = CGPoint(x: home.x + x * u, y: home.y + y * u)
        root.addSublayer(l)
        flakes.append(Flake(layer: l, x: x, y: y, vx: vx, vy: vy, lands: lands, born: t))
    }

    func updateSnow(_ t: Double, _ dt: Double, _ p: inout Pose, _ status: inout String?, _ detail: inout String?, _ shake: inout CGFloat) {
        if !sleeping, !tired, scene == nil, t > nextFlake {
            nextFlake = t + Double.random(in: 10...25)
            let aimed = Bool.random() && p.snow < 6
            addFlake(x: aimed ? CGFloat.random(in: -3...5) : CGFloat.random(in: -24...24), y: 29,
                     vx: aimed ? 0 : CGFloat.random(in: -0.4...0.4), vy: -3, lands: aimed, t: t)
        }
        let landY: CGFloat = currentHat == .none ? 4 : 10
        var keep: [Flake] = []
        for var f in flakes {
            f.x += f.vx * CGFloat(dt); f.y += f.vy * CGFloat(dt)
            if f.lands && f.y <= landY {
                p.snow = min(6, p.snow + 1); f.layer.removeFromSuperlayer(); continue
            }
            if f.y < -29 || f.y > 31 || abs(f.x) > 30 || t - f.born > 30 { f.layer.removeFromSuperlayer(); continue }
            f.layer.position = CGPoint(x: home.x + (f.x * 2).rounded() / 2 * u, y: home.y + (f.y * 2).rounded() / 2 * u)
            keep.append(f)
        }
        flakes = keep
        if p.snow >= 6, t > shakeUntil, scene == nil, !sleeping {
            shakeUntil = t + 1.2
            p.snow = 0
            for i in 0..<5 {
                let a = CGFloat(i) / 4 * .pi
                addFlake(x: cos(a) * 6, y: 8 + sin(a) * 2, vx: cos(a) * 14, vy: -3 - sin(a) * 2, lands: false, t: t)
            }
        }
        if t < shakeUntil {
            shake += (Int(t * 12) % 2 == 0 ? 0.5 : -0.5)
            status = status ?? "Shaking it off…"; detail = detail ?? ""
        }
    }

    // MARK: The sword

    func startSword(_ t: Double) {
        scene = .sword; sceneStart = t
        let d = homeToEdge + swordLength + 9
        swordTimes.push = (d / 4).rounded(.up) * 0.8
        swordTimes.pull = (d / 2.5).rounded(.up) * 0.45
        let l = CALayer(); noAnim(l)
        l.contents = makeSwordImage()
        l.magnificationFilter = .nearest
        l.anchorPoint = CGPoint(x: 0, y: 0.5)
        l.bounds = CGRect(x: 0, y: 0, width: swordLength * u, height: swordHeight * u)
        l.position = CGPoint(x: -swordLength * u - 10, y: home.y)
        root.insertSublayer(l, below: sprite)
        swordLayer = l
    }

    // Returns true while the scene is steering his position directly.
    func updateSword(_ t: Double, _ p: inout Pose, _ off: inout CGPoint, _ status: inout String?, _ detail: inout String?,
                     _ target: inout CGPoint, _ shake: inout CGFloat, _ fallen: inout Bool) -> Bool {
        var s = t - sceneStart
        let T = swordTimes
        let farLeft = -(homeToEdge + 22)
        let startX = -(homeToEdge + swordLength + 2), endX: CGFloat = 9
        let dist = endX - startX
        var swordX = startX, swordLift: CGFloat = 0
        func walk() { p.legs = Int(t * 6) % 2 == 0 ? 1 : 2 }
        status = "Fetching something…"; detail = ""
        defer {
            swordLayer?.position = CGPoint(x: (home.x + swordX * u).rounded(), y: home.y + (swordLift - 0.5) * u)
        }
        if s < T.leave {                        // wander off the left edge
            off = CGPoint(x: farLeft * CGFloat(s / T.leave), y: 0); walk()
            p.lookX = -1
            return true
        }
        s -= T.leave
        if s < T.push {                         // the tip arrives first, and it keeps on arriving
            let n = floor(s / 0.8), frac = (s / 0.8) - n
            swordX = min(endX, startX + 4 * (CGFloat(n) + CGFloat(min(1, frac / 0.55))))
            off = CGPoint(x: swordX - 9, y: 0)
            if frac < 0.55 { walk() }
            p.lookX = 1; p.eyes = frac < 0.55 ? .happy : .normal
            status = "Too big, too thick, too heavy…"
            return true
        }
        s -= T.push; swordX = endX; off = CGPoint(x: endX - 9, y: 0)
        if s < T.pant {                         // catch breath
            p.lookX = 0.5; p.eyes = .tired
            status = "Catching breath…"
            return true
        }
        s -= T.pant
        if s < T.lift {                         // one mighty effort
            p.eyes = .happy; p.wave = Int(t * 8) % 2 == 0 ? 1 : 2
            shake = Int(t * 12) % 2 == 0 ? 0.25 : -0.25
            if s > 1.7 { swordLift = 0.25 }     // one pixel, on your screen, more or less
            status = s > 1.7 ? "Lifted it 1px…" : "Lifting…"
            return true
        }
        s -= T.lift
        if s < T.fall {                         // and over he goes
            fallen = true; p.eyes = .dizzy(Int(t * 8) % 8); p.crooked = true
            status = "Struggling…"
            return true
        }
        s -= T.fall
        p.crooked = true
        if s < T.up { hopStart = hopStart < t - 1 ? t : hopStart; hopHeight = 2; p.lookX = 1; status = "Struggling…"; return true }
        s -= T.up
        if s < T.stare {                        // Guts stares at the moon, unmoved
            target = guts; p.lookX = 0; p.lookY = 0
            let dx = guts.x - center.x, dy = guts.y - center.y, d = hypot(dx, dy)
            p.lookX = ((dx / d) * 2).rounded() / 2; p.lookY = ((-dy / d * 0.5) * 4).rounded() / 4
            if p.lookX == 0 { p.lookX = 1 }
            status = "Awaiting Guts's approval…"
            return true
        }
        s -= T.stare
        if s < T.pull {                         // haul it back the way it came
            let n = floor(s / 0.45), frac = (s / 0.45) - n
            swordX = max(startX, endX - 2.5 * (CGFloat(n) + CGFloat(min(1, frac / 0.6))))
            off = CGPoint(x: swordX - 9, y: 0)
            p.lookX = -1; if frac < 0.6 { walk() }
            status = "Rewriting fate in Rust…"
            return true
        }
        s -= T.pull; swordX = startX
        if s < T.back {                         // stroll back in like nothing happened
            off = CGPoint(x: farLeft * CGFloat(1 - s / T.back), y: 0); walk()
            p.lookX = 1
            status = "All tests passing…"
            return true
        }
        swordLayer?.removeFromSuperlayer(); swordLayer = nil
        scene = nil; crookedUntil = t + 45; verbStart = t
        off = .zero
        return true
    }

    // MARK: The Eclipse

    func startEclipse(_ t: Double) {
        scene = .eclipse; sceneStart = t
        let r = moonRadius, side = r * 8
        let frame = NSRect(x: moon.x - side / 2, y: moon.y - side / 2, width: side, height: side)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
        w.level = window.level; w.collectionBehavior = window.collectionBehavior
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(origin: .zero, size: frame.size)); v.wantsLayer = true
        w.contentView = v
        let disc = CALayer(); noAnim(disc)
        disc.backgroundColor = rgb(0x030202)
        disc.bounds = CGRect(x: 0, y: 0, width: r * 2.4, height: r * 2.4)
        disc.cornerRadius = r * 1.2
        let ring = CALayer(); noAnim(ring)
        let px = 256, c = context(px, px), m = CGFloat(px) / 2
        let inner: CGFloat = 1.2 / 2.2
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0xFF2A1A, 0), rgb(0xFF3A22, 1), rgb(0xD9281A, 0.55), rgb(0x8A1410, 0.15), rgb(0x8A1410, 0)] as CFArray,
                           locations: [inner - 0.012, inner + 0.008, inner + 0.05, inner + 0.2, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m), startRadius: 0, endCenter: CGPoint(x: m, y: m), endRadius: m, options: [])
        ring.contents = c.makeImage()
        ring.bounds = CGRect(x: 0, y: 0, width: r * 4.4, height: r * 4.4)
        ring.position = CGPoint(x: side / 2, y: side / 2)
        ring.opacity = 0
        v.layer!.addSublayer(ring); v.layer!.addSublayer(disc)
        if randomEvents { w.orderFront(nil) }
        moonWindow = w; moonDisc = disc; moonRing = ring
    }

    func endEclipse() {
        moonWindow?.orderOut(nil); moonWindow = nil; moonDisc = nil; moonRing = nil
    }

    func updateEclipse(_ t: Double, _ p: inout Pose, _ status: inout String?, _ detail: inout String?,
                       _ target: inout CGPoint, _ shake: inout CGFloat) {
        let s = t - sceneStart, r = moonRadius, side = r * 8
        let arrive = 16.0, hold = 8.0, leave = 14.0
        // Slides from the upper right, sits dead centre, carries on to the lower left.
        let travel = r * 3.4
        var along: CGFloat
        if s < arrive { let k = CGFloat(s / arrive); along = travel * (1 - k * k * (3 - 2 * k)) }
        else if s < arrive + hold { along = 0 }
        else { let k = CGFloat((s - arrive - hold) / leave); along = -travel * k * k * (3 - 2 * k) }
        moonDisc?.position = CGPoint(x: side / 2 + along * 0.9, y: side / 2 + along * 0.45)
        var ringOn: Float = 0
        if s > arrive - 3, s < arrive + hold + 3 {
            ringOn = Float(min(1, min((s - (arrive - 3)) / 3, (arrive + hold + 3 - s) / 3)))
        }
        moonRing?.opacity = ringOn

        if s > 7 && s < arrive + hold + 4 {
            target = moon; p.eyes = .wide
            if s > arrive - 2 {
                shake = Int(t * 12) % 2 == 0 ? 0.5 : -0.5
                status = "Asking permission to not be here…"; detail = ""
            } else {
                status = "Contemplating the moon…"; detail = ""
            }
        } else if s >= arrive + hold + 4 {
            target = guts
            status = "Nothing happened…"; detail = ""
        }
        if s > arrive + hold + leave {
            endEclipse(); scene = nil; verbStart = t
        }
    }
}

final class Controller: NSObject {
    var clawds: [Clawd] = []
    var timer: Timer?, interval: TimeInterval = 0
    var hat: Hat?, gear: [Gear]?, demoName: String?, awake = true, wasVisible: Bool? = nil
    var clickMonitor: Any?

    func rebuild() {
        clawds.forEach { $0.close() }
        clawds = NSScreen.screens.map { Clawd(screen: $0, hat: hat, gear: gear) }
        // Always draw once, so he's there the moment the desktop is uncovered.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clawds.forEach { $0.tick() }
        CATransaction.commit()
    }
    func schedule(_ i: TimeInterval) {
        guard i != interval || timer == nil else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: i, repeats: true) { [weak self] _ in self?.tickAll() }
        t.tolerance = i * 0.2       // lets macOS group wake-ups together
        RunLoop.main.add(t, forMode: .common)
        timer = t; interval = i
    }
    func tickAll() {
        guard awake else { return }
        let vis = demoName != nil || clawds.contains { $0.visible }
        if vis != wasVisible {
            wasVisible = vis
            FileHandle.standardError.write("\(Date()) desktop \(vis ? "visible" : "covered")\n".data(using: .utf8)!)
        }
        if !vis { schedule(2); return }   // covered: draw nothing, just check back
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clawds.forEach { $0.tick() }
        CATransaction.commit()
        schedule(clawds.map(\.desiredInterval).min() ?? 1.0 / 6)
    }
    func run() {
        rebuild(); schedule(1.0 / 6)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in self?.tickAll() }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.awake = false; self?.timer?.invalidate(); self?.timer = nil
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.awake = true; self?.schedule(1.0 / 6)
        }
        // Only ever uses where the click landed, and only wakes up when there is one.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let p = NSEvent.mouseLocation
            self?.clawds.forEach { $0.handleClick(at: p) }
        }
        if let d = demoName {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.clawds.forEach { $0.demo(d) } }
        }
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

func bake(input: String, output: String, hat: Hat, gear: [Gear]) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(input)") }
    let c = context(img.width, img.height)
    c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    // On a 1710pt display this image is shown at 1107/4320, so match the live sprite's size.
    let k = 1107 / CGFloat(img.height)
    let u = (baseUnit / k).rounded()
    let center = CGPoint(x: (CGFloat(img.width) * anchorFrac.x).rounded(), y: (CGFloat(img.height) * (1 - anchorFrac.y)).rounded())
    drawGlow(c, center: center, radius: 30 * u)
    let pose = Pose(lookX: 1, lookY: -0.25, hat: hat, gear: gear)
    drawSprite(c, center: center, u: u, pose: pose)
    drawText(c, statusString("✻ Struggling…", "(esc to interrupt)", size: 13 / k), at: CGPoint(x: center.x - 8 * u, y: center.y - 7.75 * u))
    writeImage(c.makeImage()!, to: output)
}

func sheet(output: String) {
    let poses: [Pose] = [
        Pose(lookX: 1, lookY: -0.25),
        Pose(lookX: 0.5, lookY: -0.25, hat: .wizard),
        Pose(lookX: 1, hat: .crown, gear: [.cape]),
        Pose(eyes: .happy, hat: .party, gear: [.scarf]),
        Pose(lookX: 1, lookY: -0.25, hat: .helm, gear: [.armor, .sword]),
        Pose(lookX: -1, wave: 1, hat: .viking, gear: [.armor]),
        Pose(lookX: 1, lookY: -0.25, hat: .none, gear: [.cape, .sword]),
        Pose(lookY: -0.25, hat: .none, gear: [.scarf]),
        Pose(eyes: .dizzy(2), crooked: true),
        Pose(lookX: 0.5, lookY: -0.5, eyes: .wide, snow: 4),
        Pose(eyes: .blink, hat: .wizard, snow: 3, z: 2),
        Pose(eyes: .tired, hat: .none, gear: [.cape], snow: 3),
    ]
    let cell = 620, cols = 4, rows = 3
    let c = context(cell * cols, cell * rows)
    c.setFillColor(rgb(0x000000)); c.fill(CGRect(x: 0, y: 0, width: cell * cols, height: cell * rows))
    for (i, p) in poses.enumerated() {
        let center = CGPoint(x: cell * (i % cols) + cell / 2, y: cell * (rows - 1 - i / cols) + cell / 2 + 20)
        c.saveGState(); c.clip(to: CGRect(x: cell * (i % cols), y: cell * (rows - 1 - i / cols), width: cell, height: cell))
        drawGlow(c, center: center, radius: 480)
        drawSprite(c, center: center, u: 16, pose: p)
        c.restoreGState()
    }
    writeImage(c.makeImage()!, to: output)
}

// MARK: - Tests

// Steps a Clawd through time without a display, using the real tick and the real layers.
final class Sim {
    let c: Clawd, step = 1.0 / 12
    var t = 1.0
    var parked: CGPoint { CGPoint(x: c.center.x + 40 * c.u, y: c.center.y - 25 * c.u) }
    init(hat: Hat, gear: [Gear], screen: NSScreen) {
        c = Clawd(screen: screen, hat: hat, gear: gear, show: false)
        c.randomEvents = false; c.simBattery = 100; c.nextTap = 1e9; c.nextFlake = 1e9; c.fakeMouse = parked; c.lastMouse = parked
        c.fakeT = t; c.lastT = t; c.tick()
    }
    func run(_ seconds: Double, each: (() -> Void)? = nil) {
        let end = t + seconds
        while t < end { t += step; c.fakeT = t; c.lastMoveT = max(c.lastMoveT, t - 200); c.tick(); each?() }
    }
    var swordTotal: Double { let T = c.swordTimes; return T.leave + T.push + T.pant + T.lift + T.fall + T.up + T.stare + T.pull + T.back }
    func clean() -> Bool {
        c.scene == nil && c.swordLayer == nil && c.moonWindow == nil && c.root.sublayers?.count == 4 + c.flakes.count
            && c.sprite.affineTransform() == .identity && abs(c.pos.x) < 0.5 && abs(c.pos.y) < 0.5
    }
}

func selftest() -> Bool {
    guard let screen = NSScreen.main else { print("no screen"); return false }
    var failures: [String] = [], runs = 0
    func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
    var gearSets: [[Gear]] = [[]]
    for g in Gear.allCases { gearSets += gearSets.map { $0 + [g] } }
    for hat in Hat.allCases { for gear in gearSets {
        let name = "\(hat.rawValue)+\(gear.map(\.rawValue).joined(separator: ","))"
        let sim = Sim(hat: hat, gear: gear, screen: screen), c = sim.c
        let screenLeft = -c.homeToEdge
        // Sword
        c.startSword(sim.t)
        let total = sim.swordTotal
        var fell = false, lifted = false, offLeft = false, atHome = false, minY = CGFloat.infinity, status = Set<String>()
        var tipMax = -CGFloat.infinity
        sim.run(total + 2) {
            if c.sprite.affineTransform() != .identity { fell = true }
            if let l = c.swordLayer {
                tipMax = max(tipMax, l.position.x + swordLength * c.u)
                if l.position.y > c.home.y - 0.5 * c.u + 0.1 { lifted = true }
                minY = min(minY, l.position.y)
                if abs(l.position.x - (c.home.x + 9 * c.u)) < 1 && abs(c.pos.x) < 0.1 { atHome = true }
            }
            if c.pos.x < screenLeft - 12 { offLeft = true }
            status.insert(c.drawnText)
        }
        check(fell, "\(name): sword: never fell over")
        check(lifted, "\(name): sword: never lifted")
        check(offLeft, "\(name): sword: never left the screen")
        check(atHome, "\(name): sword: hilt never reached home")
        check(tipMax <= c.window.frame.width + 1, "\(name): sword: tip clipped by the window (\(tipMax) > \(c.window.frame.width))")
        check(sim.clean(), "\(name): sword: not clean afterwards")
        check(c.pose.crooked, "\(name): sword: hat not crooked afterwards")
        // Eclipse
        c.startEclipse(sim.t)
        var wide = false, ring: Float = 0, shook = false, askStatus = false
        sim.run(40) {
            if c.pose.eyes == .wide { wide = true }
            if let r = c.moonRing { ring = max(ring, r.opacity) }
            if c.drawnText.hasPrefix("Asking permission") { askStatus = true }
            if abs(c.sprite.position.x - c.home.x) > 0.1 * c.u && c.scene == .eclipse { shook = true }
        }
        check(wide, "\(name): eclipse: eyes never went wide")
        check(ring > 0.99, "\(name): eclipse: ring never fully on")
        check(askStatus, "\(name): eclipse: status never changed")
        check(shook, "\(name): eclipse: never shook")
        check(sim.clean(), "\(name): eclipse: not clean afterwards")
        // Snow: settles, then gets shaken off at six.
        c.nextFlake = 1e9
        for i in 0..<6 { c.addFlake(x: 0, y: 12, vx: 0, vy: -3, lands: true, t: sim.t); _ = i }
        var peak = 0
        sim.run(3) { peak = max(peak, c.pose.snow) }
        check(peak == 6 || c.pose.snow == 0, "\(name): snow: never reached the shake (peak \(peak))")
        sim.run(16)
        check(c.pose.snow == 0, "\(name): snow: did not shake off")
        check(c.flakes.isEmpty, "\(name): snow: \(c.flakes.count) flakes left behind")
        // Sleep and waking
        c.sleeping = true
        sim.run(3)
        check(c.pose.z >= 0 && c.pose.eyes == .blink, "\(name): sleep: not asleep")
        check(c.desiredInterval == 0.5, "\(name): sleep: not throttled")
        c.fakeMouse = CGPoint(x: c.center.x + 100, y: c.center.y)
        sim.run(0.2)
        check(!c.sleeping && c.pose.eyes == .wide, "\(name): sleep: did not wake startled")
        c.fakeMouse = sim.parked; sim.run(12); c.lastMoveT = sim.t
        // Clicks
        c.handleClick(at: c.center); sim.run(0.1)
        check(c.pose.eyes == .happy && sim.t - c.hopStart < 0.45, "\(name): click: no hop")
        sim.run(2); c.wideUntil = 0; c.happyUntil = 0
        c.handleClick(at: CGPoint(x: c.center.x + 20 * c.u, y: c.center.y)); sim.run(0.1)
        check(c.pose.eyes == .wide && c.pos.x < 0, "\(name): click: no flinch")
        sim.run(2)
        // Circling the cursor: pulled, then dizzy, then home.
        var pulled = false, dizzy = false
        sim.run(5) {
            let a = CGFloat(sim.t) * 2 * .pi * 1.2
            c.fakeMouse = CGPoint(x: c.center.x + cos(a) * 20 * c.u, y: c.center.y + sin(a) * 20 * c.u)
            if c.pulling { pulled = true }
            if case .dizzy = c.pose.eyes { dizzy = true }
        }
        check(pulled, "\(name): chase: never pulled")
        check(dizzy, "\(name): chase: never dizzy")
        c.fakeMouse = sim.parked; sim.run(6)
        check(sim.clean() && !c.pulling, "\(name): chase: did not settle")
        // Covered mid-scene and uncovered much later: each scene should just have finished.
        c.startSword(sim.t); sim.run(10); sim.t += 3000; sim.run(0.5)
        check(sim.clean(), "\(name): pause: sword not clean after a long pause")
        c.sleeping = false; c.lastMoveT = sim.t; c.fakeMouse = sim.parked; sim.run(0.2)
        c.startEclipse(sim.t); sim.run(10); sim.t += 3000; sim.run(0.5)
        check(sim.clean(), "\(name): pause: eclipse not clean after a long pause")
        c.sleeping = false; c.lastMoveT = sim.t; sim.run(0.2)
        // Low battery
        c.fakeMouse = CGPoint(x: c.center.x + 300, y: c.center.y)
        c.simBattery = 7; sim.run(1)
        check(c.pose.eyes == .tired || c.pose.eyes == .blink, "\(name): battery: not tired")
        check(c.drawnText.hasPrefix("Running on fumes"), "\(name): battery: wrong status")
        check(c.desiredInterval >= 1.0 / 12, "\(name): battery: bad rate")
        c.simBattery = 100
        runs += 1
    } }
    for f in failures.prefix(40) { print("FAIL", f) }
    print("\(runs) outfits, \(failures.count) failures")
    return failures.isEmpty
}

func renderFrame(_ c: Clawd, wall: CGImage?, screen f: CGRect) -> CGImage {
    let x = context(Int(f.width), Int(f.height))
    x.setFillColor(rgb(0x000000)); x.fill(CGRect(origin: .zero, size: f.size))
    if let w = wall {
        let k = max(f.width / CGFloat(w.width), f.height / CGFloat(w.height))
        let dw = CGFloat(w.width) * k, dh = CGFloat(w.height) * k
        x.interpolationQuality = .medium
        x.draw(w, in: CGRect(x: (f.width - dw) / 2, y: (f.height - dh) / 2, width: dw, height: dh))
    }
    x.saveGState(); x.translateBy(x: c.window.frame.minX - f.minX, y: c.window.frame.minY - f.minY); c.root.render(in: x); x.restoreGState()
    if let m = c.moonWindow, let l = m.contentView?.layer {
        x.saveGState(); x.translateBy(x: m.frame.minX - f.minX, y: m.frame.minY - f.minY); l.render(in: x); x.restoreGState()
    }
    return x.makeImage()!
}

func gridImage(_ frames: [CGImage], cols: Int, scale: CGFloat, crop: CGRect? = nil) -> CGImage {
    let base = crop?.size ?? CGSize(width: frames[0].width, height: frames[0].height)
    let w = Int(base.width * scale), h = Int(base.height * scale), rows = (frames.count + cols - 1) / cols
    let g = context(w * cols + 4 * (cols - 1), h * rows + 4 * (rows - 1))
    g.setFillColor(rgb(0x333333)); g.fill(CGRect(x: 0, y: 0, width: g.width, height: g.height))
    g.interpolationQuality = .medium
    for (i, f) in frames.enumerated() {
        let img = crop.flatMap { f.cropping(to: $0) } ?? f
        let y = (rows - 1 - i / cols) * (h + 4)
        g.draw(img, in: CGRect(x: (i % cols) * (w + 4), y: y, width: w, height: h))
    }
    return g.makeImage()!
}

func renderFrames(dir: String, wallpaper: String?) {
    guard let screen = NSScreen.main else { return }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let f = screen.frame
    var wall: CGImage? = nil
    if let p = wallpaper, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil) {
        wall = CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    func shoot(_ name: String, hat: Hat = .santa, gear: [Gear] = [], times: [Double], cols: Int = 3, scale: CGFloat = 0.5, setup: (Sim) -> Void, each: ((Sim) -> Void)? = nil) {
        let sim = Sim(hat: hat, gear: gear, screen: screen)
        setup(sim)
        var frames: [CGImage] = [], last = 0.0
        // Times may be given as a closure's result, so read them after setup.
        for at in times {
            sim.run(at - last) { each?(sim) }
            last = at
            frames.append(renderFrame(sim.c, wall: wall, screen: f))
        }
        writeImage(gridImage(frames, cols: cols, scale: scale), to: dir + "/" + name + ".png")
    }
    let probe = Sim(hat: .santa, gear: [], screen: screen)
    probe.c.startSword(probe.t)
    let T = probe.c.swordTimes
    var m = T.leave
    let swordTimes: [Double] = {
        var r: [Double] = [1.0]
        r += [m + T.push * 0.3, m + T.push * 0.6, m + T.push * 0.9]; m += T.push
        r += [m + 0.8]; m += T.pant
        r += [m + 1.0, m + 2.2]; m += T.lift
        r += [m + 0.9]; m += T.fall
        r += [m + 0.2]; m += T.up
        r += [m + 1.5]; m += T.stare
        r += [m + T.pull * 0.4, m + T.pull * 0.9]; m += T.pull
        r += [m + 1.5, m + T.back + 0.5]
        return r
    }()
    probe.c.swordLayer?.removeFromSuperlayer()
    for (hat, gear) in [(Hat.santa, [Gear]()), (.helm, [.armor, .sword, .cape])] {
        shoot("sword-\(hat.rawValue)", hat: hat, gear: gear, times: swordTimes, setup: { $0.c.startSword($0.t) })
    }
    shoot("eclipse", times: [5, 11, 15, 17, 20, 25, 28, 31, 35, 39], setup: { $0.c.startEclipse($0.t) })
    let closeUp = CGRect(x: 0, y: 0, width: 760, height: 760)
    func close(_ name: String, hat: Hat = .santa, gear: [Gear] = [], times: [Double], setup: (Sim) -> Void, each: ((Sim) -> Void)? = nil) {
        let sim = Sim(hat: hat, gear: gear, screen: screen)
        setup(sim)
        var frames: [CGImage] = [], last = 0.0
        for at in times {
            sim.run(at - last) { each?(sim) }
            last = at
            frames.append(renderFrame(sim.c, wall: wall, screen: f))
        }
        let cy = f.height - sim.c.center.y - closeUp.height / 2
        let crop = CGRect(x: max(0, sim.c.center.x - closeUp.width / 2), y: cy, width: closeUp.width, height: closeUp.height)
        writeImage(gridImage(frames, cols: 4, scale: 0.5, crop: crop), to: dir + "/" + name + ".png")
    }
    close("chase", times: [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 8], setup: { _ in }, each: { s in
        guard s.t < 6 else { s.c.fakeMouse = s.parked; return }
        let a = CGFloat(s.t) * 2 * .pi * 1.2
        s.c.fakeMouse = CGPoint(x: s.c.center.x + cos(a) * 20 * s.c.u, y: s.c.center.y + sin(a) * 20 * s.c.u)
    })
    close("snow", hat: .wizard, times: [0.5, 2, 3.5, 5, 6, 6.8, 7.5, 9], setup: { s in
        for i in 0..<6 { s.c.addFlake(x: CGFloat(i) - 3, y: 11 + CGFloat(i) * 3, vx: 0, vy: -3, lands: true, t: s.t) }
        s.c.addFlake(x: 12, y: 25, vx: 0.2, vy: -3, lands: false, t: s.t)
    })
    close("sleep", hat: .crown, gear: [.cape], times: [0.5, 1.5, 2.8, 4, 4.3, 4.5, 4.8, 6], setup: { $0.c.sleeping = true }, each: { s in
        if s.t > 5 { s.c.fakeMouse = CGPoint(x: s.c.center.x + 200, y: s.c.center.y) }
    })
    close("battery", hat: .none, gear: [.armor], times: [0.5, 2, 4, 6], setup: { $0.c.simBattery = 7 })
}

// MARK: - Entry

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
if args.contains("--list") {
    print("--hat   auto (follows the calendar), " + Hat.allCases.map(\.rawValue).joined(separator: ", "))
    print("--wear  auto (follows the calendar), none, or a comma list of: " + Gear.allCases.map(\.rawValue).joined(separator: ", "))
    exit(0)
}
func parseHat(_ v: String) -> Hat? {
    if v == "auto" { return nil }
    guard let h = Hat(rawValue: v) else { print("unknown hat \(v), try --list"); exit(1) }
    return h
}
func parseGear(_ v: String) -> [Gear]? {
    if v == "auto" { return nil }
    if v == "none" { return [] }
    return v.split(separator: ",").map { n in
        guard let g = Gear(rawValue: String(n)) else { print("unknown gear \(n), try --list"); exit(1) }
        return g
    }
}
let chosenHat = option("--hat").flatMap(parseHat)
let chosenGear = option("--wear").flatMap(parseGear)
let demoScene = option("--demo")
if args.count == 3, args[0] == "--bake" { bake(input: args[1], output: args[2], hat: chosenHat ?? hatForToday(), gear: chosenGear ?? gearForToday()); exit(0) }
if args.count == 2, args[0] == "--sheet" { sheet(output: args[1]); exit(0) }
if args.first == "--selftest" { _ = NSApplication.shared; exit(selftest() ? 0 : 1) }
if args.first == "--frames", args.count >= 2 { _ = NSApplication.shared; renderFrames(dir: args[1], wallpaper: args.count > 2 ? args[2] : nil); exit(0) }

// Only ever one copy running.
let lock = open(NSTemporaryDirectory() + "clawd-wallpaper.lock", O_CREAT | O_RDWR, 0o600)
if flock(lock, LOCK_EX | LOCK_NB) != 0 { print("already running"); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.hat = chosenHat
controller.gear = chosenGear
controller.demoName = demoScene
controller.run()
app.run()
