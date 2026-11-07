// Clawd on the desktop: a tiny pixel mascot floating in the Berserk night sky.
//   ClawdWallpaper                         live mode: Santa hat, changing look every few minutes
//   ClawdWallpaper --every 5               minutes on the desktop between changes (default 3)
//   ClawdWallpaper --cycle king,wizard     which looks to rotate through
//   ClawdWallpaper --look king             wear one look, no changes
//   ClawdWallpaper --hat crown --wear cape,sword  build a look yourself, no changes (--list shows all)
//   ClawdWallpaper --demo berserker        play a look's transformation right away (--demo moon: as if you clicked the moon)
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
import ServiceManagement

// Positions are fractions of the wallpaper image (y from the top), so the art lines up with it.
let imageSize = CGSize(width: 7680, height: 4320)
let anchorFrac = CGPoint(x: 0.19, y: 0.50)
let moonFrac = CGPoint(x: 0.313, y: 0.104)
let moonRadiusFrac: CGFloat = 0.066          // of image height
let gutsFrac = CGPoint(x: 0.815, y: 0.435)
let baseUnit: CGFloat = 12                   // points per sprite pixel on a 1710pt-wide screen
let spritePx: CGFloat = 4                    // bitmap pixels per sprite pixel in live mode
let canvasUnits: CGFloat = 40                // live sprite canvas, in sprite pixels
let swordLength: CGFloat = 72, swordHeight: CGFloat = 22, swordGrip: CGFloat = 7
let eclipseMeanSeconds = 14400.0             // of visible time
let holdSeconds = 42.0                       // how long he keeps a look on
let defaultEveryMinutes = 8.0 / 60           // Santa time between looks; with the hold, a new look every 50 seconds
let coveredReset = 20.0                      // covered this long and the desktop visit starts over

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
let robe = rgb(0x9C1F2E), robeLight = rgb(0xD64050), wood = rgb(0x7A5230)
let bone = rgb(0xE6DCC3)
let pink = rgb(0xE85C9C), cyan = rgb(0x4FC3D9), steel = rgb(0x8E9299), steelLight = rgb(0xC4C8CE), brown = rgb(0x6B4A2E)
let armorRed = rgb(0xB3201C), armorRedDark = rgb(0x7E1512), armorGold = rgb(0xE0AE2E), armorGoldDark = rgb(0xA87F1C)
let manhattanBlue = rgb(0x3A8DEB), manhattanLight = rgb(0x8FD2FF), spiderRed = rgb(0xC8202C), spiderBlue = rgb(0x1E4FB0)
let plagueBlack = rgb(0x45444E), plagueDark = rgb(0x24232A), lacquer = rgb(0x7E1B1B), visor = rgb(0x1B2C45), leaf = rgb(0x5E9B3C)

// To add an item: add a case here, then draw it in drawHat, drawSprite or drawSuit.
enum Hat: String, CaseIterable { case santa, wizard, crown, party, viking, helm, ironhelm, laurel, kabuto, bubble, beak, tricorn, none }
enum Gear: String, CaseIterable { case cape, robe, armor, scarf, sword, scepter, staff, axe }

// A suit recolours the whole of him, where a hat or gear only sits on top.
enum Suit: String, CaseIterable {
    case none, ironman, manhattan, spider, toga, samurai, astronaut, plague, pirate
    var skin: CGColor {
        switch self {
        case .ironman: return armorRed
        case .manhattan: return manhattanBlue
        case .spider: return spiderRed
        case .astronaut: return white
        case .plague: return plagueBlack
        default: return orange
        }
    }
    var legs: CGColor {
        switch self {
        case .ironman: return armorGold
        case .spider: return spiderBlue
        case .astronaut: return whiteShade
        case .manhattan, .plague: return skin
        default: return orange
        }
    }
    var eyes: CGColor {
        switch self {
        case .ironman: return rgb(0xCFF6FF)
        case .manhattan: return rgb(0xEAF8FF)
        case .spider: return white
        case .astronaut: return rgb(0xE8F4FF)
        case .plague: return rgb(0xE3B341)
        default: return eyeBlack
        }
    }
    var glow: [CGColor]? {   // nil is his usual warm glow
        self == .manhattan ? [rgb(0x57B4FF, 0.46), rgb(0x3C8FEF, 0.19), rgb(0x2E6FD0, 0.05), rgb(0x2E6FD0, 0)] : nil
    }
}

// A complete outfit he can change into. To add one, add it to `looks`.
struct Look {
    let name: String, hat: Hat, gear: [Gear]
    var suit = Suit.none
    let arrival: String      // status line as it lands
    let verbs: [String]      // status lines while he's wearing it
    let spark: CGColor
}
let santaLook = Look(name: "santa", hat: .santa, gear: [], arrival: "Back to work…", verbs: [
    "Struggling…", "Contemplating the moon…", "Awaiting Guts's approval…", "Hanging tinsel on a giant slab of iron…",
    "Checking the naughty list (long)…", "Reading CLAUDE.md…", "Asking permission to swing…", "Delegating to Puck…",
], spark: white)
let looks = [
    Look(name: "berserker", hat: .helm, gear: [.armor, .cape, .sword], arrival: "Accepting the Armor's terms…", verbs: [
        "Compacting 200 years of trauma…", "Resisting the Beast of Darkness…", "Sharpening Dragonslayer…",
        "Rewriting fate in Rust…", "Too big, too thick, too heavy…", "Struggling (professionally)…",
    ], spark: rgb(0xD8261C)),
    Look(name: "king", hat: .crown, gear: [.robe, .scepter], arrival: "Seizing the throne…", verbs: [
        "Ruling over three moons…", "Taxing the stars…", "Knighting the node_modules…",
        "Issuing a royal force-push…", "Demanding Guts kneel (he won't)…",
    ], spark: gold),
    Look(name: "wizard", hat: .wizard, gear: [.staff], arrival: "Studying forbidden docs…", verbs: [
        "Casting Reticulate Splines…", "Summoning a stack trace…", "Consulting the ancient man pages…",
        "Transmuting bugs into features…", "Asking Schierke for a code review…",
    ], spark: cyan),
    Look(name: "viking", hat: .viking, gear: [.axe, .scarf], arrival: "Sailing in uninvited…", verbs: [
        "Pillaging the node_modules…", "Raiding the staging server…", "Feasting on merge conflicts…",
        "Hacking (the old way)…", "Awaiting Valhalla's approval…",
    ], spark: steelLight),
    Look(name: "party", hat: .party, gear: [.scarf], arrival: "Shipping on a Friday…", verbs: [
        "Celebrating a passing test…", "Popping confetti in prod…", "Inviting Guts (he declined)…", "Blowing out 200 candles…",
    ], spark: pink),
    Look(name: "ironman", hat: .ironhelm, gear: [], suit: .ironman, arrival: "Suiting up…", verbs: [
        "Asking J.A.R.V.I.S. to fix the build…", "Rerouting power to the test suite…", "Privatizing world peace…",
        "Patching the Mark 85 in prod…", "Offering Guts a much lighter sword…",
    ], spark: armorGold),
    Look(name: "manhattan", hat: .none, gear: [], suit: .manhattan, arrival: "Reassembling, atom by atom…", verbs: [
        "Perceiving all commits simultaneously…", "It is 12 seconds from now. You force-push…",
        "Moving the Doomsday Clock to 11:59…", "Walking on Mars, ignoring the on-call…",
        "Nothing ever ends, except this build…", "Rewriting history (not with git)…",
    ], spark: manhattanLight),
    Look(name: "spiderman", hat: .none, gear: [], suit: .spider, arrival: "Thwip…", verbs: [
        "Crawling the web…", "Tingling at a race condition…", "Being friendly, and in your neighborhood…",
        "Catching a falling server…", "With great power comes great code review…",
    ], spark: rgb(0xE8ECF4)),
    Look(name: "senator", hat: .laurel, gear: [], suit: .toga, arrival: "Taking the floor…", verbs: [
        "Filibustering your pull request…", "Crossing the Rubicon into main…", "Carthago delenda est (rm -rf)…",
        "Declaring a deploy freeze for the Ides…", "Et tu, linter?…", "Moving to censure Guts…",
    ], spark: gold),
    Look(name: "samurai", hat: .kabuto, gear: [], suit: .samurai, arrival: "Drawing the blade…", verbs: [
        "Cutting one clean commit…", "Contemplating the falling blossoms and the backlog…", "Honoring the senior devs…",
        "Resting a hand on the hilt, for 200 years…", "Finding Guts's sword a bit much…",
    ], spark: rgb(0xF2A6B8)),
    Look(name: "astronaut", hat: .bubble, gear: [], suit: .astronaut, arrival: "Sealing the helmet…", verbs: [
        "Houston, we have a merge conflict…", "Deploying to the moon…", "Measuring the latency to Earth…",
        "Planting a flag in production…", "Calculating a very long way down…",
    ], spark: cyan),
    Look(name: "plague", hat: .beak, gear: [], suit: .plague, arrival: "Making house calls…", verbs: [
        "Prescribing leeches for the memory leak…", "Quarantining the flaky test…", "Bleeding the legacy code…",
        "Diagnosing an imbalance of the humours…", "Sniffing the logs through a beak…",
    ], spark: rgb(0xB9C46A)),
    Look(name: "pirate", hat: .tricorn, gear: [], suit: .pirate, arrival: "Hoisting the colours…", verbs: [
        "Sailing the C…", "Boarding someone else's repo…", "Burying the tech debt…",
        "Making Guts walk the plank (he refused)…", "Searching for the lost API key…",
    ], spark: gold),
]

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
    var z = -1                 // sleeping "z" frame, -1 for none
    var status = ""
    var detail = ""
    var suit = Suit.none
}

// y grows downward in sprite space; (9, 3.5) is the centre of his body.
func drawSprite(_ c: CGContext, center: CGPoint, u: CGFloat, pose p: Pose) {
    c.setShouldAntialias(false)
    func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        c.setFillColor(col)
        c.fill(CGRect(x: center.x + (x - 9) * u, y: center.y - (y - 3.5 + p.bob + h) * u, width: w * u, height: h * u))
    }
    let t = CGFloat(p.tail)
    if p.suit == .astronaut { px(0.5, 0.5, 2.75, 5, whiteShade); px(0.5, 0.5, 2.75, 0.5, steel) }   // air pack
    if p.gear.contains(.sword) {   // a tiny slab strapped to his back, far too big even so
        for i in 0..<15 {
            let k = CGFloat(i)
            px(14 - k * 0.5, -6.5 + k, 3, 1, steel); px(14 - k * 0.5, -6.5 + k, 1, 1, steelLight)
        }
        px(13, -7.25, 5, 0.75, ironLight); px(14.75, -9.75, 1.25, 2.5, brown); px(14.5, -10.25, 1.75, 0.5, ironLight)
    }
    if p.gear.contains(.cape) { drawDrape(px, t: t, main: cape, light: capeLight) }    // torn black
    if p.gear.contains(.robe) { drawDrape(px, t: t, main: robe, light: robeLight, trim: white) }
    // Legs
    let lift: (CGFloat, CGFloat) = p.legs == 1 ? (0.75, 0) : p.legs == 2 ? (0, 0.75) : (0, 0)
    let skin = p.suit.skin, legCol = p.suit.legs, eyeCol = p.suit.eyes
    if p.suit == .ironman {        // always on the thrusters
        let flame = 1 + abs(t) * 0.75
        for x in [CGFloat(4), 11] { px(x, 7.5, 3, flame, rgb(0x6FD3FF, 0.85)); px(x + 0.75, 7.5, 1.5, flame * 0.6, rgb(0xE8FBFF)) }
    }
    px(4, 6, 1, 1.5 - lift.0, legCol); px(6, 6, 1, 1.5 - lift.1, legCol)
    px(11, 6, 1, 1.5 - lift.0, legCol); px(13, 6, 1, 1.5 - lift.1, legCol)
    // Body and arms
    px(3, 0, 12, 6, skin)
    px(1, 3, 2, 1, skin)
    switch p.wave {
    case 1: px(15, 2, 1, 1, skin); px(16, 1, 1, 1, skin)
    case 2: px(15, 3, 1, 1, skin); px(16, 2, 1, 1, skin)
    default: px(15, 3, 2, 1, skin)
    }
    drawSuit(p.suit, t: t, wave: p.wave, px)
    // Eyes
    for ex in [CGFloat(5), 11.5] {
        let left = ex == 5
        let x = ex + p.lookX, y = 1.5 + p.lookY
        if p.suit == .spider { px(x - 0.5, y - 0.25, 2.5, 2.75, eyeBlack) }   // the mask's black rims
        switch p.eyes {
        case .happy:
            px(left ? 5 : 12.5, 1.5, 0.75, 0.75, eyeCol)
            px(left ? 5.75 : 11.75, 2.25, 0.75, 0.75, eyeCol)
            px(left ? 5 : 12.5, 3, 0.75, 0.75, eyeCol)
        case .blink: px(x, y + 1, 1.5, 0.25, eyeCol)
        case .tired: px(x, y + 1, 1.5, 1, eyeCol)
        case .wide:
            px(x - 0.25, y - 0.5, 2, 3, eyeCol)
            if p.suit == .none || p.suit.eyes == eyeBlack { px(x + 0.25, y, 0.5, 0.5, white) }
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
                px(bx + r.0 * cell, by + r.1 * cell, cell, cell, eyeCol)
            }
            px(bx + cell * 2, by + cell * 2, cell, cell, eyeCol)
        case .normal: px(x, y, 1.5, 2, eyeCol)
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
    if p.gear.contains(.scepter) {
        px(16.5, -1.5, 0.75, 6, gold); px(15.75, -3.25, 2.25, 2, gold); px(16.25, -2.75, 1.25, 1, red); px(16.5, -4, 0.75, 0.75, gold)
    }
    if p.gear.contains(.staff) {
        px(17, -4, 1, 12, wood); px(16.5, -4, 2, 0.75, wood); px(16.75, -6, 1.5, 2, cyan); px(17, -5.75, 0.5, 0.5, white)
    }
    if p.gear.contains(.axe) {
        px(17, -3, 0.75, 11, wood); px(17.75, -3.5, 2.25, 3.5, steel); px(19.5, -4, 1, 4.5, steelLight); px(15.75, -3, 1.25, 2.5, steel)
    }
    drawHat(p.hat, t: t, crooked: p.crooked, hat)
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
    case .ironhelm:
        hat(4, -1.5, 10, 1.5, armorRed); hat(5, -2.5, 8, 1, armorRed); hat(6.5, -3, 5, 0.5, armorRedDark)
        hat(7.75, -3, 2.5, 3, armorGold); hat(7.75, -3, 0.5, 3, armorGoldDark)
    case .laurel:   // a wreath, and on a very small senator
        hat(3.5, -0.75, 11, 0.75, leaf)
        for x in [3.5, 5.5, 7.5, 9.5, 11.5, 13.5] as [CGFloat] { hat(x, -1.5, 1, 0.75, rgb(0x82C255)) }
        hat(8.5, -1.5, 1, 0.75, gold)
    case .kabuto:
        hat(5, -2, 8, 2, plagueBlack); hat(6, -3, 6, 1, plagueBlack); hat(6, -3, 6, 0.5, rgb(0x55545C))
        hat(3, -0.75, 3, 1.75, lacquer); hat(12, -0.75, 3, 1.75, lacquer); hat(3, -0.75, 12, 0.5, gold)
        hat(5.5, -5.5, 1, 2.5, gold); hat(11.5, -5.5, 1, 2.5, gold); hat(6.25, -3.5, 5.5, 0.75, gold)
    case .bubble:
        hat(4, -1.5, 10, 1.5, white); hat(5, -2.5, 8, 1, white); hat(6, -3, 6, 0.5, whiteShade)
        hat(12.5, -5.5, 0.5, 3, steel); hat(12.25, -6.25, 1, 0.75, red)
    case .beak:
        hat(5, -2.5, 8, 2, plagueDark); hat(2, -0.75, 14, 0.75, plagueDark); hat(5, -1, 8, 0.5, rgb(0x5C4A32))
        hat(7.75, 2.75, 2.5, 1.25, bone); hat(8.25, 4, 1.5, 1.25, bone); hat(8.75, 5.25, 0.5, 1, whiteShade)
    case .tricorn:
        hat(3, -1, 12, 1, plagueDark); hat(4.5, -2.5, 9, 1.5, plagueDark); hat(6.5, -3.5, 5, 1, plagueDark)
        hat(3, -1, 12, 0.25, gold); hat(8, -2.5, 2, 1.25, white); hat(8.25, -2.25, 0.5, 0.5, eyeBlack); hat(9.25, -2.25, 0.5, 0.5, eyeBlack)
        hat(3, 0.75, 12, 0.25, eyeBlack); hat(4.5, 1, 2.75, 2.5, eyeBlack)   // and the eyepatch, which the hat insists on
    case .none:
        break
    }
}

func drawSuit(_ suit: Suit, t: CGFloat, wave: Int, _ px: Paint) {
    switch suit {
    case .none:
        break
    case .ironman:
        px(3.75, 0.5, 10.5, 3.75, armorGold); px(3.75, 0.5, 10.5, 0.5, armorGoldDark)
        px(3, 4.5, 12, 0.5, armorRedDark); px(1, 3, 2, 0.5, armorGold)
        px(8, 4.5, 2, 1, rgb(0x8FE9FF)); px(8.5, 4.75, 1, 0.5, rgb(0xE8FBFF))   // the arc reactor
    case .manhattan:
        px(3, 0, 12, 0.25, manhattanLight); px(3, 0, 0.25, 6, manhattanLight)
        // The hydrogen atom, on his forehead.
        px(8, 0.25, 2, 0.25, manhattanLight); px(8, 1.25, 2, 0.25, manhattanLight)
        px(7.75, 0.5, 0.25, 0.75, manhattanLight); px(10, 0.5, 0.25, 0.75, manhattanLight)
        px(8.75, 0.75, 0.5, 0.25, white)
    case .spider:
        px(3, 3.75, 12, 2.25, spiderBlue)
        let web = rgb(0x6E0E16)   // just enough to read as webbing, so the eyes stay the loudest thing
        for x in [4.5, 9, 13.5] as [CGFloat] { px(x, 0, 0.25, 3.75, web) }
        px(3, 0.75, 12, 0.25, web)
        px(3, 3.75, 3, 1, spiderRed); px(12, 3.75, 3, 1, spiderRed)
        px(8.5, 4.25, 1, 1, eyeBlack); px(7.25, 4, 3.5, 0.25, eyeBlack); px(7.25, 5, 3.5, 0.25, eyeBlack)
    case .toga:
        px(3, 3.5, 12, 2.5, white); px(3, 5.5, 12, 0.5, whiteShade)
        for i in 0..<5 { let k = CGFloat(i); px(6 + k * 1.5, 3.5 + k * 0.5, 2, 0.5, robe) }   // the senator's purple stripe
        px(15, 2, 2, 0.5, white); px(16.5, 1.5, 2.5, 2.5, bone); px(16.5, 1.5, 0.5, 2.5, whiteShade)   // his speech, unabridged
    case .samurai:
        px(3, 3.75, 12, 2.25, lacquer)
        for y in [4.5, 5.25] as [CGFloat] { px(3, y, 12, 0.25, gold) }
        for x in [5, 8, 11] as [CGFloat] { px(x, 3.75, 0.25, 2.25, rgb(0x4E0F0F)) }
        px(1, 2.5, 2.5, 2, lacquer); px(1, 3.5, 2.5, 0.25, gold); px(14.5, 2.5, 2.5, 2, lacquer); px(14.5, 3.5, 2.5, 0.25, gold)
        px(15, 4.5, 6, 0.75, rgb(0x7A7A86)); px(13.5, 4.5, 1.5, 0.75, gold); px(11, 4.5, 2.5, 0.75, brown)   // the sword, in its scabbard
    case .astronaut:
        px(3.75, 0.5, 10.5, 3.25, visor); px(4.25, 0.75, 2.5, 0.5, rgb(0x5A7CA8))
        px(6.5, 4.5, 1, 0.75, red); px(8.5, 4.5, 1, 0.75, cyan); px(10.5, 4.5, 1, 0.75, gold)
    case .plague:
        px(3, 3.75, 12, 2.25, plagueDark); px(8.75, 3.75, 0.5, 2.25, rgb(0x5C4A32))
        px(17, -3, 0.75, 11, wood); px(16.5, -3.25, 1.75, 0.75, gold)   // the cane, for poking at the dying
    case .pirate:
        px(3, 3.75, 12, 2.25, rgb(0x6E1F2A)); px(7.5, 3.75, 3, 2.25, white); px(3, 5.25, 12, 0.5, brown); px(8.25, 5.25, 1.5, 0.5, gold)
        px(16.5, -3, 1, 5, steelLight); px(17.25, -3.5, 0.75, 4.5, steel); px(15.5, 2, 3, 0.75, gold); px(16.5, 2.75, 1, 1, brown)
    }
}

func drawDrape(_ px: Paint, t: CGFloat, main: CGColor, light: CGColor, trim: CGColor? = nil) {
    let sway = t * 0.5
    px(2, 0.5, 1.5, 1, main); px(1, 1.5, 2.5, 1, main); px(0, 2.5, 3.5, 1, main)
    px(-1 + sway * 0.5, 3.5, 4.5, 1, main); px(-2.5 + sway, 4.5, 6, 1, main); px(-3.5 + sway, 5.5, 7, 1, main)
    px(-4 + sway * 2, 6.5, 6.5, 1, main)
    px(-4 + sway * 2, 7.5, 1.5, 1, main); px(-1.5 + sway * 2, 7.5, 1.5, 0.75, main); px(1 + sway, 7.5, 1.25, 1, main)
    px(-4 + sway * 2, 8.5, 0.75, 0.75, main)
    px(2, 0.5, 1, 0.5, light); px(1, 1.5, 1, 0.5, light); px(0, 2.5, 1, 0.5, light)
    px(-1 + sway * 0.5, 3.5, 1, 0.5, light); px(-2.5 + sway, 4.5, 1.25, 0.5, light)
    px(-3.5 + sway, 5.5, 1, 0.5, light); px(-4 + sway * 2, 6.5, 0.75, 0.5, light)
    if let e = trim { // ermine along the hem
        px(-4 + sway * 2, 7.5, 1.5, 0.75, e); px(-1.5 + sway * 2, 7.5, 1.5, 0.75, e); px(1 + sway, 7.5, 1.25, 0.75, e)
        px(-3.25 + sway * 2, 7.75, 0.5, 0.5, eyeBlack); px(1.25 + sway, 7.75, 0.5, 0.5, eyeBlack)
    }
}

// A hat on its own, for when it's flying through the air.
func hatImage(_ kind: Hat) -> CGImage {
    let side = Int(canvasUnits * spritePx), c = context(side, side), m = CGFloat(side) / 2
    c.setShouldAntialias(false)
    drawHat(kind, t: 0, crooked: false) { x, y, w, h, col in
        c.setFillColor(col)
        c.fill(CGRect(x: m + (x - 9) * spritePx, y: m - (y - 3.5 + h) * spritePx, width: w * spritePx, height: h * spritePx))
    }
    return c.makeImage()!
}

func drawGlow(_ c: CGContext, center: CGPoint, radius: CGFloat, colors tint: [CGColor]? = nil) {
    let colors = (tint ?? [rgb(0xE8743F, 0.34), rgb(0xD9633A, 0.13), rgb(0xB84A2E, 0.035), rgb(0xB84A2E, 0)]) as CFArray
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

// The big slab. x runs hilt to tip, in sprite pixels. The shape has to say "sword" on its own:
// a wide crossguard, a dark fuller down the blade, and a point that's obviously a point.
func makeSwordImage() -> CGImage {
    let p = spritePx, c = context(Int(swordLength * p), Int(swordHeight * p))
    c.setShouldAntialias(false)
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        c.setFillColor(col); c.fill(CGRect(x: x * p, y: (y + swordHeight / 2) * p, width: w * p, height: h * p))
    }
    func cut(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        c.clear(CGRect(x: x * p, y: (y + swordHeight / 2) * p, width: w * p, height: h * p))
    }
    let blade = rgb(0x6A6E75), top = rgb(0xE4E7EA), upper = rgb(0x9499A0), low = rgb(0x3F4147), ink = rgb(0x26272B)
    let wrap = rgb(0x4A3322), wrapLight = rgb(0x8A6A4C), brass = rgb(0xC39A3C), brassDark = rgb(0x7E6020)
    let taper: CGFloat = 58   // where the point starts
    // The blade, narrowing to a sharp point in steps
    r(12, -5.5, taper - 12, 11, blade); r(12, 1.5, taper - 12, 3, upper); r(12, 4.5, taper - 12, 1, top); r(12, -5.5, taper - 12, 1.25, low)
    let steps = 7
    for i in 0..<steps {
        let x = taper + CGFloat(i) * 2, half = 5.5 * (1 - CGFloat(i + 1) / CGFloat(steps + 1))
        r(x, -half, 2, half * 2, blade)
        r(x, half * 0.3, 2, half * 0.5, upper)
        r(x, half - 0.75, 2, 0.75, top)
        r(x, -half, 2, 0.75, low)
    }
    // Ink hatching on the shadow side, so it sits with the manga art
    var hx: CGFloat = 12.5, hi = 0
    while hx < taper - 1 {
        let len: CGFloat = [1.5, 2.25, 1, 1.75, 2.5][hi % 5]
        r(hx, -5.25, 0.5, len, ink)
        hx += [1.25, 1.75, 1, 2.25][hi % 4]; hi += 1
    }
    // The fuller
    r(12, -1, taper - 6, 1.5, ink); r(12, 0.5, taper - 6, 0.5, top)
    // Scars from years of hard use, and chips in both edges
    for (x, y, w) in [(15, 2.25, 6), (24, 3, 4), (30, 2.5, 3.5), (38, 2, 7), (47, 2.75, 3), (53, 3, 4)] as [(CGFloat, CGFloat, CGFloat)] {
        r(x, y, w, 0.5, low)
    }
    for (x, w) in [(18, 1.25), (33, 0.75), (44, 1.5), (54, 1)] as [(CGFloat, CGFloat)] { cut(x, 5, w, 0.5) }
    for (x, w) in [(23, 1), (37, 1.5), (51, 0.75)] as [(CGFloat, CGFloat)] { cut(x, -5.5, w, 0.5) }
    // A wrapped grip and a heavy pommel
    r(1.75, -1.5, 8, 3, wrap)
    for i in 0..<4 { r(2.25 + CGFloat(i) * 2, -1.5, 0.75, 3, wrapLight) }
    r(0, -2.5, 2, 5, brassDark); r(0, 0.5, 2, 2, brass)
    // The crossguard, wide and flared, in a colour the blade isn't
    r(9.5, -9, 2.5, 18, brassDark); r(10.5, -9, 1.5, 18, brass)
    r(8.5, -11, 4.5, 3, brassDark); r(9.5, -11, 3.5, 3, brass)
    r(8.5, 8, 4.5, 3, brassDark); r(9.5, 8, 3.5, 3, brass); r(9.5, 10.25, 3.5, 0.75, top)
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
func noAnim(_ l: CALayer) { l.actions = ["position": NSNull(), "contents": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(), "hidden": NSNull()] }

struct Spark { let layer: CALayer; var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat; let dies: Double }
enum Scene { case sword, eclipse, change, summon }

// Is the desktop the thing under this point, rather than a window? Clicks reach us wherever they
// land. Only ordinary windows count: transparent overlays above them (a notch app, a dictation
// pill) sit over the moon without hiding it. Reads window positions only, no names or contents.
func desktopIsUnder(_ p: CGPoint) -> Bool {
    guard let primary = NSScreen.screens.first,
          let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
    let flipped = CGPoint(x: p.x, y: primary.frame.height - p.y)
    return !list.contains { w in
        guard let layer = w[kCGWindowLayer as String] as? Int, (0..<20).contains(layer),
              (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = w[kCGWindowBounds as String], let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return false }
        return rect.contains(flipped)
    }
}

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
    var currentHat = Hat.santa, currentGear: [Gear] = [], currentSuit = Suit.none, drawnGlow = Suit.none
    // The rotation: Santa, then a look for a while, then Santa again, then the next look.
    let cycleLooks: [Look], every: Double, cycling: Bool
    var lookIndex = 0, wearing: Look? = nil, nextCycle = 0.0
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
    var verbIndex = Int.random(in: 0..<100), verbStart = 0.0
    var nextSlow = 0.0, battery: Int? = nil, lateNight = false, simBattery: Int? = nil

    // Moods
    var sleeping = false, sleepForced = false
    var wideUntil = 0.0, hopStart = -10.0, hopHeight: CGFloat = 3, happyUntil = 0.0, flinchUntil = 0.0, flinchX: CGFloat = 0
    var dizzyUntil = 0.0, spin: CGFloat = 0, lastAngle: CGFloat? = nil, pulling = false, pullStart = 0.0

    // Sparks, and hats in flight
    var sparks: [Spark] = []
    var flyHat: CALayer?, dropHat: CALayer?, swapStage = 0, changeTarget = santaLook

    // Scenes
    var scene: Scene? = nil, sceneStart = 0.0
    var swordLayer: CALayer?
    var swordTimes = (leave: 2.2, drag: 0.0, pant: 1.6, lift: 2.6, fall: 1.8, up: 0.5, stare: 2.2, surge: 1.8, swap: 1.4, power: 3.0, sheathe: 0.9, back: 0.0)
    var parkX: CGFloat = 50        // how far right of home he stops, with all of the sword on screen
    var moonWindow: NSWindow?, moonDisc: CALayer?, moonRing: CALayer?
    // The blood moon, from clicking on the moon.
    var bloodWindow: NSWindow?, bloodLayer: CALayer?, bloodStart = 0.0, bloodFadeStart: Double? = nil
    var desktopUnder: (CGPoint) -> Bool = desktopIsUnder

    init(screen s: NSScreen, hat: Hat?, gear: [Gear]?, suit: Suit? = nil, show: Bool = true, cycle: [Look] = looks, every minutes: Double = defaultEveryMinutes) {
        screen = s
        cycleLooks = cycle; every = minutes * 60
        cycling = hat == nil && gear == nil && !cycle.isEmpty   // choosing an outfit yourself fixes it
        currentHat = hat ?? .santa; currentGear = gear ?? []; currentSuit = suit ?? Suit.none
        nextCycle = every
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
        // Reaches from the screen edge to past where he stops with the sword; only as tall as he needs.
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
        endEclipse(); endBlood(); window.orderOut(nil)
    }

    var visible: Bool {
        [window, moonWindow, bloodWindow].contains { $0?.occlusionState.contains(.visible) ?? false }
    }

    var desiredInterval: TimeInterval {
        let t = lastT
        if sleeping { return 1 }
        if scene != nil || bloodWindow != nil || pulling || t < dizzyUntil || t - hopStart < 0.6 || t < waveUntil || t < tapUntil || t - lastMoveT < 1.5 { return 1.0 / 10 }
        if tired || ProcessInfo.processInfo.isLowPowerModeEnabled { return 0.5 }
        return 1.0 / 3
    }

    var tired: Bool { (simBattery ?? battery ?? 100) < 10 }

    // MARK: Input

    // Returns true if the click set something off that shouldn't wait for the next tick.
    @discardableResult func handleClick(at p: CGPoint) -> Bool {
        if hypot(p.x - moon.x, p.y - moon.y) < moonRadius * 1.05, desktopUnder(p) { return summon(now) }
        guard !sleeping, scene == nil else { return false }
        let d = hypot(p.x - (center.x + pos.x * u), p.y - (center.y + pos.y * u))
        if d < 9 * u {
            hopStart = lastT; hopHeight = 4; happyUntil = lastT + 0.9
        } else if d < 40 * u {
            flinchUntil = lastT + 0.35; wideUntil = lastT + 0.45
            flinchX = p.x > center.x ? -1 : 1
        }
        return false
    }

    // The moon goes red, he notices, and then he goes for the sword, whatever he was doing.
    // A fixed outfit stays fixed, and the sword scene is already what you asked for.
    func summon(_ t: Double) -> Bool {
        guard cycling else { return false }
        if bloodWindow == nil { startBlood(t) } else { bloodFadeStart = nil }
        if scene == .sword || scene == .summon { return true }
        endEclipse()
        flyHat?.removeFromSuperlayer(); flyHat = nil; dropHat?.removeFromSuperlayer(); dropHat = nil; swapStage = 0
        sleeping = false; sleepForced = false; lastMoveT = t
        pulling = false; spin = 0; lastAngle = nil; dizzyUntil = 0
        scene = .summon; sceneStart = t
        return true
    }

    let dragHand: CGFloat = -8               // where his left arm has the grip, from his centre
    let dragStride: CGFloat = 6, dragBeat = 0.8

    func demo(_ name: String) {
        let t = now
        switch name {
        case "eclipse": startEclipse(t)
        case "sleep": sleeping = true; sleepForced = true
        case "dizzy": dizzyUntil = t + 3.5
        case "battery": simBattery = 7
        case "click": handleClick(at: center)
        case "moon": _ = summon(t)
        case "sword": startLook(looks[0], t)
        case let n where looks.contains { $0.name == n }: startLook(looks.first { $0.name == n }!, t)
        default: print("unknown demo \(name)")
        }
    }

    // MARK: Tick

    func tick() {
        let t = now
        let gap = t - lastT
        let dt = min(gap, 0.6); lastT = t
        let mouse = mouseNow
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y) > 1
        if moved { lastMouse = mouse; lastMoveT = t; idleTarget = nil }
        let idle = t - lastMoveT

        if t > nextSlow {      // once a minute is plenty for these
            nextSlow = t + 60
            battery = batteryPercent()
            let hour = Calendar.current.component(.hour, from: Date())
            lateNight = hour < 6
        }

        // Sleep and waking
        if sleeping {
            if moved {
                sleeping = false; sleepForced = false
                nextCycle = max(nextCycle, t + every)   // waking up shouldn't set off a change on the spot
                hopStart = t; hopHeight = 5; wideUntil = t + 0.9
                verbStart = t
            }
        } else if scene == nil, wearing == nil, idle > (lateNight ? 60 : 300) {
            sleeping = true
        }

        // The rotation only runs on a long visit: a spell behind windows starts it over.
        if cycling {
            if gap > coveredReset {
                nextCycle = t + every
                if wearing != nil {
                    if scene == nil { wearing = nil; dress(santaLook); verbStart = t }
                    else { nextCycle = t }   // mid-change: let it finish, then straight back to Santa
                }
            } else if wearing != nil, t >= nextCycle {
                // Time's up, and nothing gets to keep him dressed up.
                if sleeping {
                    wearing = nil; dress(santaLook); nextCycle = t + every   // he wakes up as Santa
                } else if scene == nil, !pulling, t > dizzyUntil {
                    wearing = nil; startChange(santaLook, t); nextCycle = t + every
                }
            } else if wearing == nil, scene == nil, !sleeping, !tired, !pulling, t > dizzyUntil, t >= nextCycle {
                startLook(cycleLooks[lookIndex % cycleLooks.count], t); lookIndex += 1
            }
        }

        // Rare events
        if randomEvents, scene == nil, !sleeping, !tired, !pulling, t > dizzyUntil {
            if Double.random(in: 0..<1) < dt / eclipseMeanSeconds { startEclipse(t) }
        }

        // Defaults for this frame
        var p = Pose(hat: currentHat, gear: currentGear, suit: currentSuit)
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
        if scene == .change { updateChange(t, &p, &status, &detail, &target) }
        if scene == .summon { updateSummon(t, &p, &status, &detail, &target, &shake) }
        updateBlood(t)
        if scene == nil, !pulling { offset = .zero }

        // Eyes
        let dx = target.x - (center.x + pos.x * u), dy = target.y - (center.y + pos.y * u), d = max(hypot(dx, dy), 0.001)
        let mag = min(1, d / (24 * u))
        if scene == nil || p.lookX == 0 {
            p.lookX = ((dx / d * mag) * 2).rounded() / 2
            p.lookY = ((-dy / d * mag * 0.5) * 4).rounded() / 4
        }
        if t > nextBlink {
            blinkUntil = t + 0.34
            nextBlink = t + (Int.random(in: 0..<5) == 0 ? 0.7 : Double.random(in: 2.5...6.5))
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
        updateSparks(t, dt)

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
        let lineup = (wearing ?? santaLook).verbs
        if t - verbStart > 16 { verbIndex += 1; verbStart = t }
        let line = status ?? lineup[verbIndex % lineup.count]
        let info = detail ?? (tired ? "" : "(esc to interrupt)")
        if tired && status == nil {
            setText("Running on fumes…", "(\(simBattery ?? battery ?? 0)% · esc to interrupt)")
        } else {
            setText(line, info)
        }
        let spinIndex = sleeping ? 0 : Int(t * 2) % spinner.count
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
        if drawnGlow != currentSuit {
            if drawnGlow.glow != nil || currentSuit.glow != nil {
                let gc = context(180, 180)
                drawGlow(gc, center: CGPoint(x: 90, y: 90), radius: 90, colors: currentSuit.glow)
                glow.contents = gc.makeImage()
            }
            drawnGlow = currentSuit
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

    // MARK: Sparks

    func burst(_ color: CGColor, count: Int, t: Double) {
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi + .random(in: -0.3...0.3)
            let speed = CGFloat.random(in: 7...15)
            let l = CALayer(); noAnim(l)
            l.backgroundColor = color
            l.bounds = CGRect(x: 0, y: 0, width: 0.75 * u, height: 0.75 * u)
            root.addSublayer(l)
            sparks.append(Spark(layer: l, x: pos.x + cos(a) * 3, y: pos.y + 3 + sin(a) * 3, vx: cos(a) * speed, vy: sin(a) * speed + 4,
                                dies: t + Double.random(in: 0.6...1.2)))
            l.position = CGPoint(x: home.x + sparks.last!.x * u, y: home.y + sparks.last!.y * u)
        }
    }

    func updateSparks(_ t: Double, _ dt: Double) {
        guard !sparks.isEmpty else { return }
        var keep: [Spark] = []
        for var f in sparks {
            if t >= f.dies { f.layer.removeFromSuperlayer(); continue }
            f.vy -= 22 * CGFloat(dt)
            f.x += f.vx * CGFloat(dt); f.y += f.vy * CGFloat(dt)
            f.layer.position = CGPoint(x: home.x + (f.x * 2).rounded() / 2 * u, y: home.y + (f.y * 2).rounded() / 2 * u)
            keep.append(f)
        }
        sparks = keep
    }

    // MARK: Changing looks

    func startLook(_ look: Look, _ t: Double) {
        wearing = look
        if look.name == looks[0].name {
            startSword(t, target: look)
            nextCycle = t + holdSeconds + 40
        } else {
            startChange(look, t)
            nextCycle = t + holdSeconds
        }
    }

    func dress(_ look: Look, gear: [Gear]? = nil) {
        currentHat = look.hat; currentGear = gear ?? look.gear; currentSuit = look.suit
    }

    func startChange(_ look: Look, _ t: Double) {
        scene = .change; sceneStart = t; changeTarget = look; swapStage = 0
    }

    func hatLayer(_ kind: Hat) -> CALayer {
        let l = CALayer(); noAnim(l)
        l.contents = hatImage(kind)
        l.magnificationFilter = .nearest
        l.bounds = sprite.bounds
        root.addSublayer(l)
        return l
    }

    // The old hat flies off, the new one drops on, and on landing the outfit is his.
    // `s` is seconds since the swap began. Returns true once it has landed.
    func updateSwap(_ s: Double, flyTime: Double, dropTime: Double, to look: Look, gear: [Gear], _ p: inout Pose, _ t: Double) -> Bool {
        let base = CGPoint(x: home.x + pos.x * u, y: home.y + pos.y * u)
        if swapStage == 0 {
            if currentHat != .none { flyHat = hatLayer(currentHat) }
            swapStage = 1
        }
        if swapStage == 1 {
            let k = CGFloat(min(1, s / flyTime))
            flyHat?.position = CGPoint(x: base.x - 20 * u * k, y: base.y + u * (26 * k - 14 * k * k))
            flyHat?.setAffineTransform(CGAffineTransform(rotationAngle: k * 2.6))
            flyHat?.opacity = Float(1 - k * k * k)
            if k >= 1 {
                flyHat?.removeFromSuperlayer(); flyHat = nil
                if look.hat != .none { dropHat = hatLayer(look.hat) }
                swapStage = 2
            }
        }
        if swapStage == 2 {
            let k = CGFloat(min(1, max(0, s - flyTime) / dropTime))
            dropHat?.position = CGPoint(x: base.x, y: base.y + u * 26 * (1 - k * k))
            dropHat?.opacity = Float(min(1, k * 5))
            if k >= 1 {
                dropHat?.removeFromSuperlayer(); dropHat = nil
                dress(look, gear: gear)
                hopStart = t; hopHeight = 2
                burst(look.spark, count: 14, t: t)
                swapStage = 3
            }
        }
        if swapStage >= 3 { p.hat = currentHat; p.gear = currentGear; p.suit = currentSuit; p.crooked = false; return true }
        p.hat = .none
        return false
    }

    func updateChange(_ t: Double, _ p: inout Pose, _ status: inout String?, _ detail: inout String?, _ target: inout CGPoint) {
        let s = t - sceneStart, lookUp = 0.5, fly = 0.6, drop = 0.8, settle = 1.4
        detail = ""
        if s < lookUp {
            target = CGPoint(x: center.x, y: center.y + 2000)
            status = "Changing outfits…"
            return
        }
        target = CGPoint(x: center.x, y: center.y + 2000)
        if updateSwap(s - lookUp, flyTime: fly, dropTime: drop, to: changeTarget, gear: changeTarget.gear, &p, t) {
            p.eyes = .happy
            status = changeTarget.arrival
        } else {
            status = "Changing outfits…"
        }
        if s > lookUp + fly + drop + settle { scene = nil; swapStage = 0; verbStart = t }
    }

    // MARK: The sword

    func startSword(_ t: Double, target: Look) {
        scene = .sword; sceneStart = t; changeTarget = target; swapStage = 0
        // He drags it in flat, blade trailing behind him, and stops once the tip has cleared the edge.
        parkX = swordLength - swordGrip - dragHand - homeToEdge + 2
        swordTimes.drag = ((parkX + homeToEdge + 13) / dragStride).rounded(.up) * dragBeat
        swordTimes.back = Double(parkX / 30)
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
        let farLeft = -(homeToEdge + 13)
        // The pommel sits just past his hand, and the blade runs left from there: tip last, hilt first.
        func pommel(at x: CGFloat) -> CGFloat { x + dragHand + swordGrip }
        var swordX = pommel(at: parkX), swordLift: CGFloat = 0, angle: CGFloat = .pi, size: CGFloat = 1
        func walk() { p.legs = Int(t * 6) % 2 == 0 ? 1 : 2 }
        func lookAtGuts() {
            let dx = guts.x - center.x, dy = guts.y - center.y, d = hypot(dx, dy)
            p.lookX = max(0.5, ((dx / d) * 2).rounded() / 2); p.lookY = ((-dy / d * 0.5) * 4).rounded() / 4
        }
        status = "Fetching something…"; detail = ""
        defer {
            // Flipped as well as turned, so the light stays on the sword's upper side.
            swordLayer?.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: size, y: -size))
            swordLayer?.position = CGPoint(x: (home.x + swordX * u).rounded(), y: home.y + (swordLift - 0.5) * u)
        }
        if s < T.leave {                        // wander off the left edge
            off = CGPoint(x: farLeft * CGFloat(s / T.leave), y: 0); walk()
            p.lookX = -1
            swordX = farLeft - 10               // waiting out of sight, blade further off still
            return true
        }
        s -= T.leave
        if s < T.drag {                         // he comes back first, the hilt in his hand, hauling the rest after him
            let n = floor(s / dragBeat), frac = (s / dragBeat) - n
            let x = min(parkX, farLeft + dragStride * (CGFloat(n) + CGFloat(min(1, frac / 0.55))))
            off = CGPoint(x: x, y: 0); swordX = pommel(at: x)
            if frac < 0.55 { walk() }
            p.lookX = 1; p.eyes = frac < 0.55 ? .happy : .normal
            status = "Too big, too thick, too heavy…"
            return true
        }
        s -= T.drag; off = CGPoint(x: parkX, y: 0)
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
        if s < T.up {
            p.crooked = true
            if t - hopStart > 1 { hopStart = t; hopHeight = 2 }
            p.lookX = 1; status = "Struggling…"
            return true
        }
        s -= T.up
        if s < T.stare {                        // Guts stares at the moon, unmoved
            p.crooked = true; lookAtGuts()
            status = "Awaiting Guts's approval…"
            return true
        }
        s -= T.stare
        if s < T.surge {                        // no approval, so he makes a different kind of deal
            p.crooked = true; p.eyes = .wide; lookAtGuts()
            shake = Int(t * 12) % 2 == 0 ? 0.5 : -0.5
            if Int(t * 6) != Int((t - 1.0 / 12) * 6) { burst(changeTarget.spark, count: 2, t: t) }
            status = "Reading the Armor's terms…"
            return true
        }
        s -= T.surge
        let bodyGear = changeTarget.gear.filter { $0 != .sword }
        if s < T.swap {                         // the helm drops on and the armour clamps shut
            _ = updateSwap(s, flyTime: 0.5, dropTime: 0.7, to: changeTarget, gear: bodyGear, &p, t)
            status = changeTarget.arrival
            return true
        }
        s -= T.swap
        if swapStage < 3 {                      // never left half-dressed, however long the pause was
            flyHat?.removeFromSuperlayer(); flyHat = nil; dropHat?.removeFromSuperlayer(); dropHat = nil
            dress(changeTarget, gear: bodyGear); p.hat = currentHat; p.gear = currentGear; p.suit = currentSuit; swapStage = 3
        }
        p.crooked = false
        if s < T.power {                        // and now it weighs nothing
            let top: CGFloat = .pi / 10
            if s < 0.5 { angle = .pi - top * CGFloat(s / 0.5) }
            else if s < 2.2 { angle = .pi - top }
            else if s < 2.35 { angle = .pi - top * CGFloat(1 - (s - 2.2) / 0.15) }
            else if s < 2.8 { shake = Int(t * 12) % 2 == 0 ? 0.75 : -0.75 }
            p.wave = s < 2.2 ? 1 : 0
            if s >= 2.35, s < 2.35 + 1.0 / 12 { burst(steelLight, count: 10, t: t) }
            p.lookX = 1
            status = s < 2.2 ? "Not so heavy now…" : "Too big, too thick, just right…"
            return true
        }
        s -= T.power
        if s < T.sheathe {                      // somehow it fits on his back
            size = max(0.1, 1 - CGFloat(s / T.sheathe) * 0.9)
            status = "Sheathing it, somehow…"
            return true
        }
        s -= T.sheathe
        if swordLayer != nil {
            swordLayer?.removeFromSuperlayer(); swordLayer = nil
            currentGear = changeTarget.gear; p.gear = currentGear
            burst(steelLight, count: 8, t: t)
            hopStart = t; hopHeight = 2
        }
        if s < T.back {                         // and back to where he started, a lot lighter
            off = CGPoint(x: parkX * CGFloat(1 - s / T.back), y: 0); walk()
            p.lookX = -1
            status = changeTarget.verbs[0]
            return true
        }
        scene = nil; swapStage = 0; verbStart = t
        off = .zero
        return true
    }

    // MARK: The blood moon

    func updateSummon(_ t: Double, _ p: inout Pose, _ status: inout String?, _ detail: inout String?,
                      _ target: inout CGPoint, _ shake: inout CGFloat) {
        let s = t - sceneStart
        target = moon; p.eyes = .wide; detail = ""
        status = s < 0.6 ? "Hearing the moon…" : "Going to get something…"
        shake = Int(t * 12) % 2 == 0 ? 0.25 : -0.25
        if s > 1.3 {
            let berserker = looks[0]
            // That's his turn taken, so the rotation doesn't send him straight back for it.
            if !cycleLooks.isEmpty, cycleLooks[lookIndex % cycleLooks.count].name == berserker.name { lookIndex += 1 }
            scene = nil
            startLook(berserker, t)
        }
    }

    func startBlood(_ t: Double) {
        let r = moonRadius, side = r * 6
        let frame = NSRect(x: moon.x - side / 2, y: moon.y - side / 2, width: side, height: side)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false; w.ignoresMouseEvents = true
        w.level = window.level; w.collectionBehavior = window.collectionBehavior
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(origin: .zero, size: frame.size)); v.wantsLayer = true
        w.contentView = v
        // Stains the moon's own disc red, so its craters still show through, and glows beyond the edge.
        let px = 384, c = context(px, px), m = CGFloat(px) / 2, edge: CGFloat = 1.0 / 3
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0xE01208, 0.74), rgb(0xE8160A, 0.74), rgb(0xFF3A1E, 0.80), rgb(0xE02012, 0.42), rgb(0x9C120C, 0.12), rgb(0x8A1008, 0)] as CFArray,
                           locations: [0, edge - 0.01, edge + 0.004, edge + 0.05, edge + 0.3, 1])!
        c.drawRadialGradient(g, startCenter: CGPoint(x: m, y: m), startRadius: 0, endCenter: CGPoint(x: m, y: m), endRadius: m, options: [])
        let l = CALayer(); noAnim(l)
        l.contents = c.makeImage()
        l.frame = CGRect(x: 0, y: 0, width: side, height: side)
        l.opacity = 0
        v.layer!.addSublayer(l)
        if randomEvents { w.orderFront(nil) }
        bloodWindow = w; bloodLayer = l; bloodStart = t; bloodFadeStart = nil
    }

    func endBlood() {
        bloodWindow?.orderOut(nil); bloodWindow = nil; bloodLayer = nil; bloodFadeStart = nil
    }

    // Stays red for as long as the change is happening, then drains away.
    func updateBlood(_ t: Double) {
        guard let l = bloodLayer else { return }
        if scene != .summon && scene != .sword {
            if bloodFadeStart == nil { bloodFadeStart = t }
        } else { bloodFadeStart = nil }
        var level = min(1, (t - bloodStart) / 0.35) * (0.88 + 0.12 * sin(t * 3))
        if let f = bloodFadeStart {
            let k = (t - f) / 2.5
            if k >= 1 { endBlood(); return }
            level *= 1 - k
        }
        l.opacity = Float(level)
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
    var hat: Hat?, gear: [Gear]?, suit: Suit?, cycle: [Look] = looks, everyMinutes = defaultEveryMinutes, demoName: String?, awake = true, wasVisible: Bool? = nil
    var clickMonitor: Any?

    // Where the rotation has got to. It outlives any one Clawd, because a rebuild replaces them all
    // and would otherwise send him back to the first look. Starts past the Berserker, so opening
    // the app isn't always the sword; the moon is the way to ask for that.
    lazy var rotation = cycle.count > 1 ? Int.random(in: 1..<cycle.count) : 0
    var showWindows = true, screenKey = ""

    func currentScreenKey() -> String {
        NSScreen.screens.map { "\($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0) \($0.frame) \($0.backingScaleFactor)" }.joined(separator: "|")
    }
    // macOS sends this for plenty that doesn't change the screens' layout, such as the Dock or menu bar.
    func screensMayHaveChanged() {
        if currentScreenKey() != screenKey { rebuild() }
    }
    func rebuild() {
        rotation = clawds.map(\.lookIndex).max() ?? rotation
        screenKey = currentScreenKey()
        clawds.forEach { $0.close() }
        clawds = NSScreen.screens.map {
            let c = Clawd(screen: $0, hat: hat, gear: gear, suit: suit, show: showWindows, cycle: cycle, every: everyMinutes)
            c.lookIndex = rotation
            return c
        }
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
        t.tolerance = i >= 0.3 ? i * 0.5 : i * 0.1   // lets macOS group wake-ups together when idle
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
        if !vis { schedule(5); return }   // covered: draw nothing; macOS tells us when that changes, this is a backstop
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clawds.forEach { $0.tick() }
        CATransaction.commit()
        schedule(clawds.map(\.desiredInterval).min() ?? 1.0 / 6)
    }
    func run() {
        rebuild(); schedule(1.0 / 6)
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.screensMayHaveChanged() }
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
            guard let self else { return }
            // Not short-circuited: every screen hears the click, and any of them can react right away.
            if self.clawds.map({ $0.handleClick(at: p) }).contains(true) { self.tickAll() }
        }
        if let d = demoName {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.clawds.forEach { $0.demo(d) } }
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

func bake(input: String, output: String, hat: Hat, gear: [Gear], suit: Suit = Suit.none) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot read \(input)") }
    let c = context(img.width, img.height)
    c.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    // On a 1710pt display this image is shown at 1107/4320, so match the live sprite's size.
    let k = 1107 / CGFloat(img.height)
    let u = (baseUnit / k).rounded()
    let center = CGPoint(x: (CGFloat(img.width) * anchorFrac.x).rounded(), y: (CGFloat(img.height) * (1 - anchorFrac.y)).rounded())
    drawGlow(c, center: center, radius: 30 * u)
    let pose = Pose(lookX: 1, lookY: -0.25, hat: hat, gear: gear, suit: suit)
    drawSprite(c, center: center, u: u, pose: pose)
    drawText(c, statusString("✻ Struggling…", "(esc to interrupt)", size: 13 / k), at: CGPoint(x: center.x - 8 * u, y: center.y - 7.75 * u))
    writeImage(c.makeImage()!, to: output)
}

func sheet(output: String) {
    var poses: [Pose] = [Pose(lookX: 1, lookY: -0.25)]
    for (i, l) in looks.enumerated() {
        let dir: CGFloat = i % 3 == 2 ? -1 : 1
        poses.append(Pose(lookX: dir, lookY: i % 2 == 0 ? -0.25 : 0, eyes: l.name == "party" ? .happy : .normal, hat: l.hat, gear: l.gear, suit: l.suit))
    }
    poses += [
        Pose(lookX: 1, wave: 1, hat: .helm, gear: [.armor, .cape]),
        Pose(eyes: .dizzy(2), crooked: true),
        Pose(lookX: 0.5, lookY: -0.5, eyes: .wide),
        Pose(eyes: .blink, hat: .crown, gear: [.robe], z: 2),
    ]
    let cell = 620, cols = 6, rows = (poses.count + cols - 1) / cols
    let c = context(cell * cols, cell * rows)
    c.setFillColor(rgb(0x000000)); c.fill(CGRect(x: 0, y: 0, width: cell * cols, height: cell * rows))
    for (i, p) in poses.enumerated() {
        let center = CGPoint(x: cell * (i % cols) + cell / 2, y: cell * (rows - 1 - i / cols) + cell / 2 + 20)
        c.saveGState(); c.clip(to: CGRect(x: cell * (i % cols), y: cell * (rows - 1 - i / cols), width: cell, height: cell))
        drawGlow(c, center: center, radius: 480, colors: p.suit.glow)
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
    var cursorUntouched = false     // true lets him get sleepy, like a real visit where nobody moves the mouse
    init(hat: Hat?, gear: [Gear]?, screen: NSScreen, every: Double = defaultEveryMinutes) {
        c = Clawd(screen: screen, hat: hat, gear: gear, show: false, every: every)
        c.desktopUnder = { _ in true }
        c.randomEvents = false; c.simBattery = 100; c.nextTap = 1e9; c.fakeMouse = parked; c.lastMouse = parked
        c.fakeT = t; c.lastT = t; c.tick()
    }
    func run(_ seconds: Double, each: (() -> Void)? = nil) {
        let end = t + seconds
        while t < end { t += step; c.fakeT = t; if !cursorUntouched { c.lastMoveT = max(c.lastMoveT, t - 200) }; c.tick(); each?() }
    }
    var swordTotal: Double {
        let T = c.swordTimes
        return T.leave + T.drag + T.pant + T.lift + T.fall + T.up + T.stare + T.surge + T.swap + T.power + T.sheathe + T.back
    }
    func clean() -> Bool {
        c.scene == nil && c.swordLayer == nil && c.moonWindow == nil && c.bloodWindow == nil && c.flyHat == nil && c.dropHat == nil
            && c.root.sublayers?.count == 4 + c.sparks.count
            && c.sprite.affineTransform() == .identity && abs(c.pos.x) < 0.5 && abs(c.pos.y) < 0.5
    }
}

func selftest() -> Bool {
    guard let screen = NSScreen.main else { print("no screen"); return false }
    var failures: [String] = [], runs = 0
    func check(_ ok: Bool, _ what: String) { if !ok { failures.append(what) } }
    var gearSets: [[Gear]] = [[]]
    for g in Gear.allCases { gearSets += gearSets.map { $0 + [g] } }

    // Every outfit through everything except the sword, which always ends in the same place.
    for hat in Hat.allCases { for gear in gearSets {
        let name = "\(hat.rawValue)+\(gear.map(\.rawValue).joined(separator: ","))"
        let sim = Sim(hat: hat, gear: gear, screen: screen), c = sim.c
        // Fixed outfits never change on their own.
        sim.run(1) ; check(c.currentHat == hat && c.currentGear == gear && !c.cycling, "\(name): outfit not applied")
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
        // Sleep and waking
        c.sleeping = true
        sim.run(3)
        check(c.pose.z >= 0 && c.pose.eyes == .blink, "\(name): sleep: not asleep")
        check(c.desiredInterval == 1, "\(name): sleep: not throttled")
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
        sim.run(6) {
            let a = CGFloat(sim.t) * 2 * .pi * 1.2
            c.fakeMouse = CGPoint(x: c.center.x + cos(a) * 20 * c.u, y: c.center.y + sin(a) * 20 * c.u)
            if c.pulling { pulled = true }
            if case .dizzy = c.pose.eyes { dizzy = true }
        }
        check(pulled, "\(name): chase: never pulled")
        check(dizzy, "\(name): chase: never dizzy")
        c.fakeMouse = sim.parked; sim.run(6)
        check(sim.clean() && !c.pulling, "\(name): chase: did not settle")
        // Covered mid-scene and uncovered much later
        c.startEclipse(sim.t); sim.run(10); sim.t += 3000; sim.run(0.5)
        check(sim.clean(), "\(name): pause: eclipse not clean after a long pause")
        c.sleeping = false; c.lastMoveT = sim.t; sim.run(0.2)
        // Low battery
        c.fakeMouse = CGPoint(x: c.center.x + 300, y: c.center.y)
        c.simBattery = 7; sim.run(1)
        check(c.pose.eyes == .tired || c.pose.eyes == .blink, "\(name): battery: not tired")
        check(c.drawnText.hasPrefix("Running on fumes"), "\(name): battery: wrong status")
        c.simBattery = 100
        check(c.currentHat == hat && c.currentGear == gear, "\(name): outfit changed by itself")
        runs += 1
    } }

    // The sword scene and the armour, starting from each hat.
    let berserker = looks[0]
    for hat in Hat.allCases { for gear in [[], [Gear.cape], [.robe, .scepter], Gear.allCases] {
        let name = "sword from \(hat.rawValue)+\(gear.count)"
        let sim = Sim(hat: hat, gear: gear, screen: screen), c = sim.c
        c.startLook(berserker, sim.t)
        var fell = false, lifted = false, offLeft = false, swung = false, sawHalf = false, order: [String] = []
        var showedAll = false, enteredFirst = true, stayedFlat = true, bodyClipped = false
        var maxRight = -CGFloat.infinity, maxTop = -CGFloat.infinity, minBottom = CGFloat.infinity
        sim.run(sim.swordTotal + 3) {
            if c.sprite.affineTransform() != .identity { fell = true }
            if let l = c.swordLayer {
                let m = l.affineTransform()
                let tip = CGPoint(x: l.position.x + m.a * swordLength * c.u, y: l.position.y + m.b * swordLength * c.u)
                maxRight = max(maxRight, l.position.x); maxTop = max(maxTop, tip.y - c.window.frame.height); minBottom = min(minBottom, l.frame.minY)
                let dragging = c.drawnText.hasPrefix("Too big, too thick, too heavy") && c.currentHat == hat
                if dragging && abs(m.b) > 0.001 { stayedFlat = false }    // it's pulled along the ground, never lifted
                if dragging && abs(l.position.y - (c.home.y - 0.5 * c.u)) > 0.1 { stayedFlat = false }
                if c.drawnText.hasPrefix("Lifted") && l.position.y > c.home.y - 0.5 * c.u + 0.1 { lifted = true }
                if c.drawnText.hasPrefix("Not so heavy") && abs(m.b) > 0.1 { swung = true }
                // The moment you see any of him coming back, the crossguard has to be right behind him.
                if dragging, c.pos.x > -c.homeToEdge - 8, c.pos.x < -c.homeToEdge {
                    let guardX = l.position.x - 11 * c.u
                    if guardX < c.home.x + (c.pos.x - 14) * c.u { enteredFirst = false }
                }
                // Stopped: the whole of it on screen, tip included.
                if c.drawnText.hasPrefix("Catching breath"), tip.x >= 0, abs(tip.y - l.position.y) < 0.5 { showedAll = true }
            }
            if c.home.x + (c.pos.x + 10) * c.u > c.window.frame.width { bodyClipped = true }
            if c.swordLayer != nil, hat != .helm, c.pose.hat == .helm, !c.currentGear.contains(.armor) { sawHalf = true }
            if c.pos.x < -(c.homeToEdge + 12) { offLeft = true }
            let line = String(c.drawnText.split(separator: "|").first ?? "")
            if order.last != line { order.append(line) }
        }
        check(fell, "\(name): never fell over")
        check(lifted, "\(name): never lifted 1px")
        check(swung, "\(name): never swung it")
        check(offLeft, "\(name): never left the screen")
        check(!sawHalf, "\(name): helm on before the armour")
        check(maxRight <= c.window.frame.width + 1, "\(name): hilt clipped on the right (\(maxRight))")
        check(!bodyClipped, "\(name): walked out of his window")
        check(maxTop <= 1, "\(name): swing clipped at the top (\(maxTop))")
        check(showedAll, "\(name): never showed the whole sword")
        check(enteredFirst, "\(name): the blade came on screen without the hilt")
        check(stayedFlat, "\(name): the sword left the ground while he was dragging it")
        check(minBottom >= -1, "\(name): swing clipped at the bottom (\(minBottom))")
        check(sim.clean(), "\(name): not clean afterwards")
        check(c.currentHat == .helm && Set(c.currentGear) == Set(berserker.gear), "\(name): wrong outfit afterwards: \(c.currentHat) \(c.currentGear)")
        check(!c.pose.crooked, "\(name): helm still crooked")
        for want in ["Fetching something…", "Catching breath…", "Lifted it 1px…", "Struggling…", "Reading the Armor's terms…", "Not so heavy now…"] {
            check(order.contains(want), "\(name): missing status \(want)")
        }
        // Covered part way through: he must still end up fully dressed.
        for at in [5.0, 25.0, 33.0, 35.0, 38.0] {
            let s2 = Sim(hat: .santa, gear: [], screen: screen), c2 = s2.c
            c2.startLook(berserker, s2.t); s2.run(at); s2.t += 500; s2.run(2)
            check(s2.clean() && c2.currentHat == .helm && Set(c2.currentGear) == Set(berserker.gear), "\(name): paused at \(at)s: \(c2.currentHat) \(c2.currentGear) scene \(String(describing: c2.scene))")
            if hat != .santa { break }
        }
        runs += 1
    } }

    // The rotation
    do {
        let sim = Sim(hat: nil, gear: nil, screen: screen), c = sim.c
        check(c.cycling && c.currentHat == .santa && c.currentGear.isEmpty, "rotation: doesn't start as Santa")
        sim.run(c.every - 10)
        check(c.scene == nil && c.currentHat == .santa, "rotation: changed too early")
        for (i, look) in (looks + looks).enumerated() {
            sim.run(max(0, c.nextCycle - sim.t) + 1)
            check(c.wearing?.name == look.name, "rotation \(i): expected \(look.name), got \(c.wearing?.name ?? "nothing")")
            check(c.scene != nil, "rotation \(i): \(look.name) started without a scene")
            sim.run(look.name == "berserker" ? sim.swordTotal + 2 : 6)
            check(sim.clean() && c.currentHat == look.hat && Set(c.currentGear) == Set(look.gear) && c.currentSuit == look.suit, "rotation \(i): \(look.name) not on: \(c.currentHat) \(c.currentGear) \(c.currentSuit)")
            check(look.verbs.contains { c.drawnText.hasPrefix($0) }, "rotation \(i): wrong status: \(c.drawnText)")
            let left = c.nextCycle - sim.t
            check(left > holdSeconds * 0.5 && left <= holdSeconds + 40, "rotation \(i): holds for \(left)s")
            sim.run(left + 1)
            check(c.wearing == nil && c.scene == .change, "rotation \(i): not heading back to Santa")
            sim.run(6)
            check(sim.clean() && c.currentHat == .santa && c.currentGear.isEmpty && c.currentSuit == .none, "rotation \(i): not back to Santa: \(c.currentHat) \(c.currentGear) \(c.currentSuit)")
            check(abs(c.nextCycle - sim.t - c.every) < 10, "rotation \(i): next change in \(c.nextCycle - sim.t)s")
        }
        // One new look every 50 seconds, Santa for only a few of them.
        check(abs(holdSeconds + c.every - 50) < 0.01, "rotation: period is \(holdSeconds + c.every)s")
        do {
            let m = Sim(hat: nil, gear: nil, screen: screen), r = m.c
            r.lookIndex = 1   // past the Berserker, whose longer scene is measured below
            var starts: [Double] = [], santa = 0, frames = 0, was: String? = nil
            m.run(330) {
                if let w = r.wearing?.name, w != was { starts.append(m.t) }
                was = r.wearing?.name
                if r.wearing?.name != "berserker", starts.count >= 1 { frames += 1; if r.currentHat == .santa && r.currentSuit == .none && r.scene == nil { santa += 1 } }
            }
            let gaps = zip(starts.dropFirst(), starts).map { $0 - $1 }.filter { $0 < 60 }
            check(!gaps.isEmpty && gaps.allSatisfy { abs($0 - 50) < 1 }, "rotation: gaps between looks: \(gaps)")
            check(Double(santa) / Double(max(frames, 1)) < 0.15, "rotation: Santa \(santa) of \(frames) frames")
        }
        // A short visit never gets there: being covered starts it over.
        c.nextCycle = sim.t + 5; sim.run(1); sim.t += coveredReset + 5; sim.run(1)
        check(c.scene == nil && c.currentHat == .santa && c.nextCycle > sim.t + c.every * 0.5, "rotation: being covered didn't restart it")
        // Covered while wearing a look: back as Santa.
        c.startLook(looks[1], sim.t); sim.run(6); check(c.currentHat == .crown, "rotation: crown not on")
        sim.t += coveredReset + 5; sim.run(1)
        check(c.currentHat == .santa && c.currentGear.isEmpty && c.wearing == nil, "rotation: still in a look after being covered")
        // Asleep: it waits.
        c.sleeping = true; c.nextCycle = sim.t + 1; sim.run(5)
        check(c.scene == nil && c.wearing == nil, "rotation: changed while asleep")
        c.sleeping = false; sim.run(1)
        check(c.wearing != nil, "rotation: didn't resume after sleep")
        // Nobody touching the mouse: the armour still has to come off by itself.
        do {
            let idle = Sim(hat: nil, gear: nil, screen: screen, every: 1.5), i = idle.c
            idle.cursorUntouched = true
            idle.run(i.every + idle.swordTotal + holdSeconds + 40 + 5)
            check(i.currentHat == .santa && i.currentGear.isEmpty && i.wearing == nil,
                  "untouched: still dressed up after the hold: \(i.currentHat) \(i.currentGear), asleep \(i.sleeping)")
            idle.run(400)
            check(i.currentHat == .santa && i.sleeping, "untouched: should end up asleep as Santa: \(i.currentHat), asleep \(i.sleeping)")
            // Waking him shouldn't set off a change on the spot.
            idle.t += 1; i.fakeMouse = CGPoint(x: i.center.x + 100, y: i.center.y); idle.run(1)
            check(!i.sleeping && i.scene == nil && i.nextCycle > idle.t + i.every * 0.5, "untouched: waking set off a change: scene \(String(describing: i.scene)), next in \(i.nextCycle - idle.t)")
            // On the default short cycle he still finds a Santa moment to fall asleep in.
            let quick = Sim(hat: nil, gear: nil, screen: screen), q = quick.c
            quick.cursorUntouched = true; quick.run(420)
            check(q.sleeping && q.currentHat == .santa && q.scene == nil, "short cycle: never fell asleep: \(q.currentHat), asleep \(q.sleeping)")
            // Put to sleep in a look: wakes up as Santa.
            let s3 = Sim(hat: nil, gear: nil, screen: screen), j = s3.c
            j.startLook(looks[1], s3.t); s3.run(6); j.sleeping = true; s3.run(holdSeconds + 5)
            check(j.currentHat == .santa && j.wearing == nil, "asleep in a look: never went back: \(j.currentHat)")
            // Low battery shouldn't keep him dressed up either.
            let s4 = Sim(hat: nil, gear: nil, screen: screen), k = s4.c
            k.startLook(looks[1], s4.t); s4.run(6); k.simBattery = 5; s4.run(holdSeconds + 8)
            check(k.currentHat == .santa && k.wearing == nil, "low battery in a look: never went back: \(k.currentHat)")
            // Covered part way through a change: comes back to Santa soon after.
            let s5 = Sim(hat: nil, gear: nil, screen: screen), m = s5.c
            m.startLook(looks[1], s5.t); s5.run(1); s5.t += coveredReset + 5; s5.run(8)
            check(m.currentHat == .santa && m.wearing == nil, "covered during a change: still \(m.currentHat)")
        }
        // Fixed outfits stay put.
        let fixed = Sim(hat: .crown, gear: [.cape], screen: screen)
        fixed.run(800)
        check(fixed.c.scene == nil && fixed.c.currentHat == .crown && fixed.c.wearing == nil, "rotation: a fixed outfit changed")
        runs += 1
    }

    // The Berserker takes its turn with everyone else.
    do {
        let m = Sim(hat: nil, gear: nil, screen: screen), r = m.c
        var order: [String] = [], swords: [Double] = [], was: String? = nil
        m.run(45 * 60) {
            if let w = r.wearing?.name, w != was { order.append(w); if w == "berserker" { swords.append(m.t) } }
            was = r.wearing?.name
        }
        let first = Array(order.prefix(looks.count))
        check(first == looks.map(\.name), "rotation order: \(first)")
        let gaps = zip(swords.dropFirst(), swords).map { $0 - $1 }
        check(gaps.count >= 2 && gaps.allSatisfy { abs($0 - (Double(looks.count) * 50 + 40)) < 2 }, "sword gaps: \(gaps)")
    }
    // Rebuilding keeps his place in the rotation, and nothing rebuilds unless the screens changed.
    do {
        let k = Controller(); k.showWindows = false; k.cycle = looks; k.rotation = 4
        k.rebuild()
        check(k.clawds.allSatisfy { $0.lookIndex == 4 }, "rebuild: lost its starting place")
        for c in k.clawds { c.lookIndex = 7 }
        let same = k.clawds.first
        k.screensMayHaveChanged()
        check(k.clawds.first === same, "rebuild: a notice with no real change rebuilt him")
        k.screenKey = "something else"; k.screensMayHaveChanged()
        check(k.clawds.first !== same && k.clawds.allSatisfy { $0.lookIndex == 7 }, "rebuild: went back to the first look")
        k.clawds.forEach { $0.close() }
        for _ in 0..<50 {
            let fresh = Controller(); fresh.cycle = looks
            check(fresh.rotation % looks.count != 0, "launch: opened on the Berserker")
        }
        let one = Controller(); one.cycle = [looks[1]]; check(one.rotation == 0, "launch: one-look rotation")
    }

    // Clicking on the moon
    do {
        func onMoon(_ c: Clawd) -> CGPoint { CGPoint(x: c.moon.x + c.moonRadius * 0.5, y: c.moon.y) }
        func fullChange(_ s: Sim, _ what: String) {
            let c = s.c
            check(c.bloodWindow != nil && c.scene == .summon, "moon \(what): didn't start")
            s.run(0.5); check((c.bloodLayer?.opacity ?? 0) > 0.7, "moon \(what): not red yet")
            s.run(1.2); check(c.scene == .sword && c.wearing?.name == "berserker", "moon \(what): not going for the sword")
            check(c.bloodWindow != nil, "moon \(what): red gone too soon")
            s.run(s.swordTotal + 4)
            check(s.clean() && c.currentHat == .helm && c.currentSuit == .none && Set(c.currentGear) == Set(looks[0].gear), "moon \(what): not dressed: \(c.currentHat) \(c.currentGear) \(c.currentSuit) \(String(describing: c.scene))")
        }
        // Past the edge, or behind a window: nothing.
        let a = Sim(hat: nil, gear: nil, screen: screen)
        a.c.handleClick(at: CGPoint(x: a.c.moon.x + a.c.moonRadius * 1.3, y: a.c.moon.y)); a.run(0.2)
        check(a.c.bloodWindow == nil && a.c.scene == nil, "moon: a click beside it set it off")
        a.c.desktopUnder = { _ in false }
        check(!a.c.handleClick(at: onMoon(a.c)) && a.c.bloodWindow == nil, "moon: a click on a window over it set it off")
        a.c.desktopUnder = { _ in true }
        // Idle, then back to the normal rotation, without doing the berserker twice.
        check(a.c.handleClick(at: onMoon(a.c)), "moon: click didn't count")
        fullChange(a, "idle")
        a.run(max(0, a.c.nextCycle - a.t) + 5)
        check(a.c.wearing == nil && a.c.currentHat == .santa, "moon: never went back to Santa")
        a.run(max(0, a.c.nextCycle - a.t) + 1)
        check(a.c.wearing?.name == looks[1].name, "moon: rotation didn't resume at the next look: \(a.c.wearing?.name ?? "nothing")")
        // Rotation had already got past the berserker: stays where it was.
        let b = Sim(hat: nil, gear: nil, screen: screen)
        b.c.lookIndex = 3; b.c.handleClick(at: onMoon(b.c)); fullChange(b, "mid-rotation")
        check(b.c.lookIndex == 3, "moon: rotation lost its place")
        // From any other state, right away.
        let asleep = Sim(hat: nil, gear: nil, screen: screen)
        asleep.c.sleeping = true; asleep.run(1); check(asleep.c.handleClick(at: onMoon(asleep.c)), "moon: asleep ignored"); fullChange(asleep, "asleep")
        let ecl = Sim(hat: nil, gear: nil, screen: screen)
        ecl.c.startEclipse(ecl.t); ecl.run(5); ecl.c.handleClick(at: onMoon(ecl.c)); check(ecl.c.moonWindow == nil, "moon: eclipse left running"); fullChange(ecl, "eclipse")
        let mid = Sim(hat: nil, gear: nil, screen: screen)
        mid.c.startLook(looks[1], mid.t); mid.run(0.8); mid.c.handleClick(at: onMoon(mid.c)); fullChange(mid, "mid-change")
        for look in looks {   // and out of every other look, including from the armour itself
            let l = Sim(hat: nil, gear: nil, screen: screen)
            l.c.startLook(look, l.t); l.run(look.name == "berserker" ? l.swordTotal + 2 : 6)
            l.c.handleClick(at: onMoon(l.c)); fullChange(l, "from \(look.name)")
        }
        // Mid-sword: glows, but doesn't restart him.
        let sw = Sim(hat: nil, gear: nil, screen: screen)
        sw.c.startLook(looks[0], sw.t); sw.run(4); let began = sw.c.sceneStart
        check(sw.c.handleClick(at: onMoon(sw.c)) && sw.c.sceneStart == began && sw.c.bloodWindow != nil, "moon: restarted a sword scene")
        // Paused half way through: still ends up dressed and tidy.
        let pause = Sim(hat: nil, gear: nil, screen: screen)
        pause.c.handleClick(at: onMoon(pause.c)); pause.run(0.5); pause.t += 500; pause.run(1); pause.run(pause.swordTotal + 4)
        check(pause.clean() && pause.c.currentSuit == .none, "moon: long pause left a mess")
        // A fixed outfit stays fixed.
        let fixed = Sim(hat: .crown, gear: [.cape], screen: screen)
        check(!fixed.c.handleClick(at: onMoon(fixed.c)) && fixed.c.bloodWindow == nil && fixed.c.scene == nil, "moon: changed a fixed outfit")
        runs += 1
    }
    // The real window check: whatever it answers, it must not crash, and it must be honest about windows.
    _ = desktopIsUnder(CGPoint(x: 10, y: 10))

    for f in failures.prefix(40) { print("FAIL", f) }
    print("\(runs) runs, \(failures.count) failures")
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
    for m in [c.bloodWindow, c.moonWindow].compactMap({ $0 }) {
        guard let l = m.contentView?.layer else { continue }
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
    func shoot(_ name: String, hat: Hat? = .santa, gear: [Gear]? = [], times: [Double], cols: Int = 3, scale: CGFloat = 0.5, setup: (Sim) -> Void, each: ((Sim) -> Void)? = nil) {
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
    probe.c.startLook(looks[0], probe.t)
    let T = probe.c.swordTimes
    var m = T.leave
    let swordTimes: [Double] = {
        var r: [Double] = [1.0]
        r += [m + T.drag * 0.12, m + T.drag * 0.2, m + T.drag * 0.3, m + T.drag * 0.5, m + T.drag * 0.75]; m += T.drag
        r += [m + 0.8]; m += T.pant
        r += [m + 2.2]; m += T.lift
        r += [m + 0.9]; m += T.fall + T.up
        r += [m + 1.2]; m += T.stare
        r += [m + 1.0]; m += T.surge
        r += [m + 0.3, m + 0.9, m + 1.3]; m += T.swap
        r += [m + 0.6, m + 2.0, m + 2.45]; m += T.power
        r += [m + 0.5, m + T.sheathe + 0.8, m + T.sheathe + T.back + 3]
        return r
    }()
    probe.c.swordLayer?.removeFromSuperlayer()
    shoot("sword", hat: .santa, gear: [], times: swordTimes, cols: 4, setup: { $0.c.startLook(looks[0], $0.t) })
    shoot("moon", hat: nil, gear: nil, times: [0.1, 0.5, 1.2, 2.5, 5, 40, 42, 45, 49], setup: { $0.c.handleClick(at: $0.c.moon) })
    shoot("eclipse", times: [5, 11, 15, 17, 20, 25, 28, 31, 35, 39], setup: { $0.c.startEclipse($0.t) })
    let closeUp = CGRect(x: 0, y: 0, width: 760, height: 760)
    func close(_ name: String, hat: Hat? = .santa, gear: [Gear]? = [], times: [Double], setup: (Sim) -> Void, each: ((Sim) -> Void)? = nil) {
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
    for look in looks.dropFirst() {
        close("look-" + look.name, times: [0.3, 0.8, 1.0, 1.4, 1.75, 2.0, 2.6, 3.6], setup: { $0.c.startLook(look, $0.t) })
    }
    close("back-to-santa", hat: nil, gear: nil, times: [0.3, 0.8, 1.0, 1.4, 1.75, 2.0, 2.6, 3.6], setup: { s in
        s.c.currentHat = .helm; s.c.currentGear = looks[0].gear; s.c.wearing = looks[0]; s.c.startChange(santaLook, s.t); s.c.wearing = nil
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
    print("--look   " + looks.map(\.name).joined(separator: ", ") + " (one outfit, no changes)")
    print("--cycle  a comma list of those looks, to rotate through")
    print("--every  minutes as Santa between looks (default \(String(format: "%.2f", defaultEveryMinutes)), so a new look every \(Int(holdSeconds + defaultEveryMinutes * 60)) seconds)")
    print("--hat    " + Hat.allCases.map(\.rawValue).joined(separator: ", "))
    print("--wear   none, or a comma list of: " + Gear.allCases.map(\.rawValue).joined(separator: ", "))
    print("--suit   " + Suit.allCases.map(\.rawValue).joined(separator: ", "))
    print("--demo   " + looks.map(\.name).joined(separator: ", ") + ", moon, eclipse, sleep, dizzy, battery, click")
    exit(0)
}
func parseHat(_ v: String) -> Hat {
    guard let h = Hat(rawValue: v) else { print("unknown hat \(v), try --list"); exit(1) }
    return h
}
func parseGear(_ v: String) -> [Gear] {
    if v == "none" { return [] }
    return v.split(separator: ",").map { n in
        guard let g = Gear(rawValue: String(n)) else { print("unknown gear \(n), try --list"); exit(1) }
        return g
    }
}
func parseSuit(_ v: String) -> Suit {
    guard let s = Suit(rawValue: v) else { print("unknown suit \(v), try --list"); exit(1) }
    return s
}
func parseLook(_ v: String) -> Look {
    if v == "santa" { return santaLook }
    guard let l = looks.first(where: { $0.name == v }) else { print("unknown look \(v), try --list"); exit(1) }
    return l
}
var chosenHat = option("--hat").map(parseHat)
var chosenGear = option("--wear").map(parseGear)
var chosenSuit = option("--suit").map(parseSuit)
if let v = option("--look") { let l = parseLook(v); chosenHat = l.hat; chosenGear = l.gear; chosenSuit = l.suit }
if chosenSuit != nil && chosenHat == nil && chosenGear == nil { chosenHat = Hat.none; chosenGear = [] }
if chosenHat != nil && chosenGear == nil { chosenGear = [] }
if chosenGear != nil && chosenHat == nil { chosenHat = Hat.none }
let chosenCycle = option("--cycle")?.split(separator: ",").map { parseLook(String($0)) }.filter { $0.name != "santa" } ?? looks
let chosenEvery = max(0.05, option("--every").flatMap(Double.init) ?? defaultEveryMinutes)
let demoScene = option("--demo")
if args.count == 3, args[0] == "--bake" { bake(input: args[1], output: args[2], hat: chosenHat ?? .santa, gear: chosenGear ?? [], suit: chosenSuit ?? Suit.none); exit(0) }
if args.count == 2, args[0] == "--sheet" { sheet(output: args[1]); exit(0) }
if args.first == "--selftest" { _ = NSApplication.shared; exit(selftest() ? 0 : 1) }
if args.first == "--frames", args.count >= 2 { _ = NSApplication.shared; renderFrames(dir: args[1], wallpaper: args.count > 2 ? args[2] : nil); exit(0) }

// Installed as ClawdWallpaper.app, he opens at login like any other app.
// `--no-login` takes him off the login items and quits.
if Bundle.main.bundleURL.pathExtension == "app" {
    let login = SMAppService.mainApp
    if args.contains("--no-login") {
        try? login.unregister()
        print("removed from login items")
        exit(0)
    }
    if login.status != .enabled {
        do { try login.register() } catch { print("couldn't add to login items: \(error)") }
    }
}

// Only ever one copy running.
let lock = open(NSTemporaryDirectory() + "clawd-wallpaper.lock", O_CREAT | O_RDWR, 0o600)
if flock(lock, LOCK_EX | LOCK_NB) != 0 { print("already running"); exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
controller.hat = chosenHat
controller.gear = chosenGear
controller.suit = chosenSuit
controller.cycle = chosenCycle
controller.everyMinutes = chosenEvery
controller.demoName = demoScene
controller.run()
app.run()
