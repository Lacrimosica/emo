// Renders Emo's artwork: an empty newsreader's desk with a microphone, out in a field, under a
// mustard sun, with chunky "Emo" lettering. Everything is drawn here from shapes (no photos,
// no fonts), so the result is original artwork.
//
// usage: swift render.swift <out.png> <art|mac|ios> <pixels>
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 4, let pixels = Int(args[3]) else {
    fatalError("usage: render.swift <out.png> <art|mac|ios> <pixels>")
}
let outPath = args[1], mode = args[2]
let size = CGFloat(pixels)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let paper = rgb(0xEFE2C8), ink = rgb(0x2B2118), sun = rgb(0xE6B23A)
let fieldBack = rgb(0x7E9150), fieldFront = rgb(0x9AAA62)
let wood = rgb(0x7A5030), woodDark = rgb(0x4A2E1A), woodEdge = rgb(0x6B4428)
let cream = rgb(0xF7ECD6), chrome = rgb(0xCFC8B8), leather = rgb(0x3E2A1E)

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
        ctx.setFillColor(rgb(0x6B5A40, 0.05 + random() * 0.07))
        ctx.fillEllipse(in: CGRect(x: random() * 1000, y: random() * 1000, width: r, height: r))
    }

    // Sun.
    ctx.setFillColor(sun)
    ctx.fillEllipse(in: CGRect(x: 500 - 300, y: 400 - 300, width: 600, height: 600))

    // Two rolling fields.
    let back = CGMutablePath()
    back.move(to: CGPoint(x: 0, y: 600))
    back.addCurve(to: CGPoint(x: 1000, y: 570), control1: CGPoint(x: 300, y: 545), control2: CGPoint(x: 700, y: 620))
    back.addLine(to: CGPoint(x: 1000, y: 1000)); back.addLine(to: CGPoint(x: 0, y: 1000)); back.closeSubpath()
    fill(back, fieldBack)
    let front = CGMutablePath()
    front.move(to: CGPoint(x: 0, y: 690))
    front.addCurve(to: CGPoint(x: 1000, y: 660), control1: CGPoint(x: 350, y: 640), control2: CGPoint(x: 650, y: 700))
    front.addLine(to: CGPoint(x: 1000, y: 1000)); front.addLine(to: CGPoint(x: 0, y: 1000)); front.closeSubpath()
    fill(front, fieldFront)
    // A few grass tufts.
    for (x, y) in [(120.0, 760.0), (210, 715), (840, 735), (905, 790), (70, 850), (950, 880)] as [(CGFloat, CGFloat)] {
        let tuft = CGMutablePath()
        for dx in [-10.0, 0, 10] as [CGFloat] {
            tuft.move(to: CGPoint(x: x + dx * 0.4, y: y))
            tuft.addLine(to: CGPoint(x: x + dx, y: y - 18 - abs(dx) * -0.4))
        }
        stroke(tuft, rgb(0x6E8044), 4)
    }

    // Shadow of the desk on the grass.
    ctx.setFillColor(rgb(0x2B2118, 0.22))
    ctx.fillEllipse(in: CGRect(x: 230, y: 728, width: 540, height: 34))

    // The empty chair behind the desk: the presenter has just stepped away.
    fill(rect(438, 410, 562, 580, radius: 26), leather)
    for (x, y) in [(470.0, 445.0), (500, 445), (530, 445), (485, 480), (515, 480), (470, 515), (500, 515), (530, 515)] as [(CGFloat, CGFloat)] {
        ctx.setFillColor(rgb(0x1E140E, 0.7))
        ctx.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
    }

    // Desk: top slab and front panel down to the grass.
    fill(rect(290, 580, 710, 742), wood)
    stroke(rect(310, 600, 690, 724, radius: 4), woodDark, 5)
    fill(rect(262, 556, 738, 584, radius: 6), woodDark)
    fill(rect(262, 556, 738, 564, radius: 4), woodEdge)
    stroke(rect(290, 580, 710, 742), ink, 5)
    stroke(rect(262, 556, 738, 584, radius: 6), ink, 5)

    // Papers on the desk.
    ctx.saveGState()
    ctx.translateBy(x: 612, y: 548); ctx.rotate(by: -0.06)
    fill(rect(-56, -9, 56, 9, radius: 2), cream)
    stroke(rect(-56, -9, 56, 9, radius: 2), ink, 4)
    stroke({ let p = CGMutablePath(); p.move(to: CGPoint(x: -40, y: 0)); p.addLine(to: CGPoint(x: 30, y: 0)); return p }(), rgb(0x2B2118, 0.5), 3)
    ctx.restoreGState()

    // Microphone: weighted base, stem, and an old broadcast mic head with a grille.
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: 360, y: 544, width: 84, height: 18))
    fill(rect(396, 470, 408, 552, radius: 4), ink)
    let head = rect(366, 380, 438, 478, radius: 34)
    fill(head, chrome)
    ctx.saveGState()
    ctx.addPath(head); ctx.clip()
    var y: CGFloat = 392
    while y < 478 {
        let line = CGMutablePath()
        line.move(to: CGPoint(x: 366, y: y)); line.addLine(to: CGPoint(x: 438, y: y))
        stroke(line, rgb(0x2B2118, 0.45), 3)
        y += 11
    }
    ctx.restoreGState()
    stroke(head, ink, 7)
    // The yoke holding the head.
    let yoke = CGMutablePath()
    yoke.move(to: CGPoint(x: 356, y: 430))
    yoke.addCurve(to: CGPoint(x: 448, y: 430), control1: CGPoint(x: 356, y: 500), control2: CGPoint(x: 448, y: 500))
    stroke(yoke, ink, 7)

    // "On air" marks beside the mic.
    for (x0, y0, x1, y1) in [(318.0, 392.0, 336.0, 420.0), (300, 440, 330, 446), (318, 470, 338, 488)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        let mark = CGMutablePath()
        mark.move(to: CGPoint(x: x0, y: y0)); mark.addLine(to: CGPoint(x: x1, y: y1))
        stroke(mark, ink, 11)
    }

    drawLettering()
}

/// "Emo" in chunky rounded strokes with an ink outline and a drop shadow.
func drawLettering() {
    let letters = CGMutablePath()
    // E
    letters.move(to: CGPoint(x: 282, y: 750)); letters.addLine(to: CGPoint(x: 180, y: 750))
    letters.addLine(to: CGPoint(x: 180, y: 925)); letters.addLine(to: CGPoint(x: 287, y: 925))
    letters.move(to: CGPoint(x: 180, y: 838)); letters.addLine(to: CGPoint(x: 262, y: 838))
    // m
    letters.move(to: CGPoint(x: 352, y: 800)); letters.addLine(to: CGPoint(x: 352, y: 925))
    letters.move(to: CGPoint(x: 352, y: 845))
    letters.addCurve(to: CGPoint(x: 457, y: 845), control1: CGPoint(x: 356, y: 782), control2: CGPoint(x: 453, y: 782))
    letters.addLine(to: CGPoint(x: 457, y: 925))
    letters.move(to: CGPoint(x: 457, y: 845))
    letters.addCurve(to: CGPoint(x: 562, y: 845), control1: CGPoint(x: 461, y: 782), control2: CGPoint(x: 558, y: 782))
    letters.addLine(to: CGPoint(x: 562, y: 925))
    // o
    letters.addEllipse(in: CGRect(x: 622, y: 800, width: 125, height: 125))

    // Centre horizontally.
    let bounds = letters.boundingBoxOfPath
    var shift = CGAffineTransform(translationX: 500 - bounds.midX, y: 0)
    let word = letters.copy(using: &shift)!
    var drop = CGAffineTransform(translationX: 9, y: 11)
    let shadow = word.copy(using: &drop)!

    let body: CGFloat = 46, outline: CGFloat = 15
    stroke(shadow, ink, body + outline * 2)
    stroke(word, ink, body + outline * 2)
    stroke(word, cream, body)
}

switch mode {
case "art":
    drawArt()
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
    fatalError("mode must be art, mac or ios")
}

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
