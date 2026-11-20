// Renders Emo's artwork: an abstract, poster-like take on the newsreader's desk out in a field
// ("and now for something completely different"): a black slab on a horizon line, a microphone
// stand, a mustard sun, and "E mo?" built from bars and arcs. Everything is drawn here from
// shapes (no photos, no fonts), so the result is original artwork.
//
// usage: swift render.swift <out.png> <art|mac|ios|sheet> <pixels> [mustard|night|swiss|teal|lilac]
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 4, let pixels = Int(args[3]) else {
    fatalError("usage: render.swift <out.png> <art|mac|ios|sheet> <pixels> [palette]")
}
let outPath = args[1], mode = args[2]
let size = CGFloat(pixels)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Background, foreground (desk, mic, lettering) and sun colours, plus the grain's colour.
struct Palette {
    var paper: UInt32, ink: UInt32, sun: UInt32, grain: UInt32
}
let palettes: [String: Palette] = [
    "mustard": Palette(paper: 0xEFE2C8, ink: 0x2B2118, sun: 0xE6B23A, grain: 0x6B5A40),
    "night": Palette(paper: 0x1E2940, ink: 0xF3EADB, sun: 0xE8553D, grain: 0xFFFFFF),
    "swiss": Palette(paper: 0xF4F1EA, ink: 0x1A1A1A, sun: 0xD93A2B, grain: 0x6B6B6B),
    "teal": Palette(paper: 0x234B45, ink: 0xF6EFE2, sun: 0xF2A65A, grain: 0xFFFFFF),
    "lilac": Palette(paper: 0xE6DEF0, ink: 0x2A1F3D, sun: 0x6C4AB6, grain: 0x4A3D60),
]
/// The comparison sheet's four palettes, left to right, top to bottom.
let sheetPalettes = ["night", "swiss", "teal", "lilac"]
/// Lilac is Emo's main look; the others are the alternate icons offered in Settings.
var palette = palettes[args.count > 4 ? args[4] : "lilac"] ?? palettes["lilac"]!
var paper: CGColor { rgb(palette.paper) }
var ink: CGColor { rgb(palette.ink) }
var sun: CGColor { rgb(palette.sun) }

let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    // iOS icons must be opaque; the macOS icon needs transparency around its tile.
                    bitmapInfo: (mode == "mac" ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
// Design space: 1000 × 1000, origin top-left, y down.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: size / 1000, y: -size / 1000)

func fill(_ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}
func stroke(_ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(color); ctx.setLineWidth(width)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
}
func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, radius: CGFloat = 0) -> CGPath {
    CGPath(roundedRect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0),
           cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// The scene, in design space.
func drawArt() {
    // Paper, with a faint deterministic grain.
    fill(rect(0, 0, 1000, 1000), paper)
    var seed: UInt64 = 0x5EED
    func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 10_000) / 10_000
    }
    for _ in 0..<5000 {
        let r = 0.6 + random() * 1.4
        ctx.setFillColor(rgb(palette.grain, 0.04 + random() * 0.06))
        ctx.fillEllipse(in: CGRect(x: random() * 1000, y: random() * 1000, width: r, height: r))
    }

    // Sun.
    ctx.setFillColor(sun)
    ctx.fillEllipse(in: CGRect(x: 690 - 225, y: 360 - 225, width: 450, height: 450))

    // Horizon.
    fill(rect(0, 637, 1000, 643), ink)

    // The desk: a slab on two legs, standing on the horizon.
    fill(rect(205, 490, 585, 520), ink)
    fill(rect(232, 520, 252, 640), ink)
    fill(rect(538, 520, 558, 640), ink)

    // The microphone: a thin stand on a small base, and a capsule head.
    fill(rect(296, 482, 348, 490), ink)
    fill(rect(318, 404, 326, 482), ink)
    fill(rect(300, 326, 344, 408, radius: 22), ink)
    fill(rect(310, 344, 334, 348), paper)
    fill(rect(310, 358, 334, 362), paper)
    fill(rect(310, 372, 334, 376), paper)

    drawLettering()
}

/// "E mo?" from straight bars and arcs, in ink.
func drawLettering() {
    let weight: CGFloat = 30
    // E, from four bars.
    fill(rect(140, 765, 140 + weight, 945), ink)
    fill(rect(140, 765, 250, 765 + weight), ink)
    fill(rect(140, 840, 232, 840 + weight), ink)
    fill(rect(140, 945 - weight, 255, 945), ink)

    func line(_ path: CGPath) {
        ctx.addPath(path); ctx.setStrokeColor(ink); ctx.setLineWidth(weight)
        ctx.setLineCap(.butt); ctx.setLineJoin(.miter); ctx.strokePath()
    }
    // m: a stem and two arches.
    let m = CGMutablePath()
    m.move(to: CGPoint(x: 345, y: 945)); m.addLine(to: CGPoint(x: 345, y: 838))
    m.move(to: CGPoint(x: 345, y: 885))
    m.addCurve(to: CGPoint(x: 420, y: 885), control1: CGPoint(x: 345, y: 836), control2: CGPoint(x: 420, y: 836))
    m.addLine(to: CGPoint(x: 420, y: 945))
    m.move(to: CGPoint(x: 420, y: 885))
    m.addCurve(to: CGPoint(x: 495, y: 885), control1: CGPoint(x: 420, y: 836), control2: CGPoint(x: 495, y: 836))
    m.addLine(to: CGPoint(x: 495, y: 945))
    line(m)
    // o: a ring.
    line(CGPath(ellipseIn: CGRect(x: 545, y: 853, width: 77, height: 77), transform: nil))
    // ?: a hook over a short stem, and a dot.
    let q = CGMutablePath()
    q.move(to: CGPoint(x: 668, y: 812))
    q.addCurve(to: CGPoint(x: 748, y: 812), control1: CGPoint(x: 668, y: 760), control2: CGPoint(x: 748, y: 760))
    q.addCurve(to: CGPoint(x: 708, y: 872), control1: CGPoint(x: 748, y: 845), control2: CGPoint(x: 708, y: 845))
    q.addLine(to: CGPoint(x: 708, y: 895))
    line(q)
    fill(rect(693, 915, 723, 945), ink)
}

switch mode {
case "art":
    drawArt()
case "sheet":
    // 2 × 2 comparison of `sheetPalettes`, each as the full artwork.
    for (index, name) in sheetPalettes.enumerated() {
        palette = palettes[name]!
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(index % 2) * 500, y: CGFloat(index / 2) * 500)
        ctx.scaleBy(x: 0.5, y: 0.5)
        ctx.addPath(rect(6, 6, 994, 994)); ctx.clip()
        drawArt()
        ctx.restoreGState()
    }
case "mac", "ios":
    // macOS icons carry their own rounded square with a margin; iOS icons are full-bleed squares.
    if mode == "mac" {
        let tile = rect(100, 100, 924, 924, radius: 185)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(0x000000, 0.35))
        fill(tile, paper)
        ctx.restoreGState()
        ctx.addPath(tile); ctx.clip()
        ctx.translateBy(x: 100, y: 100)
        ctx.scaleBy(x: 0.824, y: 0.824)
    }
    drawArt()
default:
    fatalError("mode must be art, mac, ios or sheet")
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
