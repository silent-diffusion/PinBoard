// options.swift — draws the PinBoard app icon options, each in three looks (light, dark
// and tinted), an Icon Composer file for each, and a contact sheet.
//
// Every option draws its picture from named colour roles (background, main colour,
// second colour, card, and so on). The light, dark and tinted looks only swap the
// colours behind those roles, so the shapes stay the same in all three, as Apple asks.
//
//   light.png    1024 × 1024, opaque, square corners (iOS rounds them).
//   dark.png     the same picture on a dark background, with the red made brighter.
//   tinted.png   the same picture in shades of grey on black. iOS colours it with the
//                tint the user picks: white takes the full tint, black none.
//   AppIcon.icon an Icon Composer file for iOS 26's Liquid Glass icons: the background as
//                a gradient fill (light and dark) and the picture as one glass layer, with
//                its cut-outs as real holes. iOS makes the clear and tinted looks from it.
//
// Usage (from AppStore/icon):
//   swiftc -O options.swift -o .icon-options && ./.icon-options options ../../Xcode/App && rm .icon-options
// Writes options/NN-name/… for each option, options/contact-sheet.png and AppIcon-1024.png, and
// puts the icons and their Settings previews into the Xcode build (see "The app's icons" below).

import AppKit

let S: CGFloat = 1024

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}
func grey(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: v, green: v, blue: v, alpha: a) }

enum Look: String, CaseIterable { case light, dark, tinted }

/// The background an option uses in its light look. Dark and tinted always use their own.
enum Backdrop { case white, red, warm }

/// The colour roles the drawings use.
struct Palette {
    var bgTop: CGColor, bgBottom: CGColor
    var main: CGColor        // the main shape: red on light backgrounds, white on red
    var second: CGColor      // a softer partner to the main colour
    var middle: CGColor      // between main and second
    var deep: CGColor        // a darker main colour, for shading
    var card: CGColor        // paper, cards and photo frames
    var card2: CGColor       // a fold or second tone on a card
    var onCard: CGColor      // red marks drawn on a card
    var lines: CGColor       // text lines on a card
    var metal: CGColor       // a pin's needle
    var cutout: CGColor      // holes and glyphs cut out of the main shape
    var edge: CGColor        // a thin edge round a card
}

func palette(_ backdrop: Backdrop, _ look: Look) -> Palette {
    switch look {
    case .dark:
        // Apple: use the light icon as the basis; dark icons are more subdued, avoid very
        // bright images. So the background goes dark, white cards go dark grey, and the
        // red is lifted so it still reads on black.
        return Palette(bgTop: hex(0x2E2E33), bgBottom: hex(0x111113),
                       main: hex(0xFF3B55), second: hex(0x7A2838), middle: hex(0xB02B41), deep: hex(0xC21A33),
                       card: hex(0x3A3A40), card2: hex(0x505057), onCard: hex(0xFF3B55), lines: hex(0x7C7C84),
                       metal: hex(0xC7C7CC), cutout: hex(0x1A1A1D), edge: hex(0x4A4A51))
    case .tinted:
        // Greyscale on black: the brightest parts carry the user's tint.
        return Palette(bgTop: grey(0), bgBottom: grey(0),
                       main: grey(1), second: grey(0.42), middle: grey(0.64), deep: grey(0.8),
                       card: grey(0.27), card2: grey(0.42), onCard: grey(1), lines: grey(0.55),
                       metal: grey(0.72), cutout: grey(0), edge: grey(0.32))
    case .light:
        var p = Palette(bgTop: hex(0xFFFFFF), bgBottom: hex(0xF6F0F1),
                        main: hex(0xE60023), second: hex(0xFFD3DA), middle: hex(0xFF7A8C), deep: hex(0xB0001B),
                        card: hex(0xFFFFFF), card2: hex(0xFFE0E5), onCard: hex(0xE60023), lines: hex(0xFFC1CA),
                        metal: hex(0x8E8E93), cutout: hex(0xFFFFFF), edge: hex(0xE9DCD2))
        switch backdrop {
        case .white: break
        case .red:
            p.bgTop = hex(0xF51C3D); p.bgBottom = hex(0xD10020)
            p.main = hex(0xFFFFFF); p.second = hex(0xFFAEBB); p.deep = hex(0x9E0018)
        case .warm: p.bgTop = hex(0xFCF7F1); p.bgBottom = hex(0xF1E6DA)
        }
        return p
    }
}

// MARK: - Drawing helpers (the context is flipped, so y grows downwards)

func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), transform: nil)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
/// When drawing a see-through foreground layer, the cut-out colour is set to this marker,
/// and anything painted in it becomes a real hole instead.
let holeMarker = hex(0x00FF01)
func fill(_ c: CGContext, _ p: CGPath, _ col: CGColor) {
    c.saveGState()
    if col == holeMarker { c.setBlendMode(.clear) }
    c.addPath(p); c.setFillColor(col); c.fillPath()
    c.restoreGState()
}
/// Turns the drawing by `degrees` (clockwise on screen) about a point, for the length of `body`.
func turned(_ c: CGContext, _ degrees: CGFloat, about x: CGFloat, _ y: CGFloat, _ body: () -> Void) {
    c.saveGState()
    c.translateBy(x: x, y: y); c.rotate(by: degrees * .pi / 180); c.translateBy(x: -x, y: -y)
    body()
    c.restoreGState()
}
func polygon(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p }

/// A sun over two hills, filling `r`: the picture sign used on several options.
func landscape(_ c: CGContext, in r: CGRect, _ col: CGColor) {
    let w = r.width, h = r.height, x = r.minX, y = r.minY
    fill(c, polygon([CGPoint(x: x, y: y + h), CGPoint(x: x, y: y + h * 0.78), CGPoint(x: x + w * 0.34, y: y + h * 0.38),
                     CGPoint(x: x + w * 0.6, y: y + h * 0.7), CGPoint(x: x + w * 0.74, y: y + h * 0.54),
                     CGPoint(x: x + w, y: y + h * 0.84), CGPoint(x: x + w, y: y + h)]), col)
    fill(c, circle(x + w * 0.74, y + h * 0.2, w * 0.1), col)
}

// MARK: - The options
//
// Ten were drawn; the owner dropped 6 (private bookmark) and 10 (heart pin) and picked 3.
// The rest keep their numbers. `pickerOrder` is the order Settings will list them in:
// the default first, then the runner-up, then the others.

let defaultNumber = 3
let pickerOrder = [3, 8, 1, 2, 4, 5, 7, 9]

struct Option {
    let number: Int          // the number the owner chose by; kept when options were dropped
    let slug: String
    let name: String
    let backdrop: Backdrop
    let draw: (CGContext, Palette) -> Void
}

let options: [Option] = [
    // 1. Today's icon, tidied: a tilted outlined photo with a pin on its corner.
    Option(number: 1, slug: "pinned-photo", name: "Pinned photo (today's look)", backdrop: .white) { c, p in
        turned(c, -10, about: 512, 530) {
            let card = rounded(CGRect(x: 272, y: 300, width: 480, height: 440), 76)
            fill(c, card, p.card)
            c.addPath(card); c.setStrokeColor(p.main); c.setLineWidth(60); c.strokePath()
            c.setLineCap(.round); c.setLineJoin(.round); c.setLineWidth(50)
            c.move(to: CGPoint(x: 352, y: 640)); c.addLine(to: CGPoint(x: 452, y: 530))
            c.addLine(to: CGPoint(x: 540, y: 618)); c.addLine(to: CGPoint(x: 590, y: 568))
            c.addLine(to: CGPoint(x: 672, y: 648)); c.strokePath()
            fill(c, circle(636, 440, 42), p.main)
            fill(c, circle(398, 300, 104), p.cutout)
            fill(c, circle(398, 300, 76), p.main)
        }
    },
    // 2. A classic push-pin seen from the side, leaning into the board.
    Option(number: 2, slug: "push-pin", name: "Push-pin", backdrop: .white) { c, p in
        turned(c, 32, about: 512, 512) {
            c.translateBy(x: 512, y: 520); c.scaleBy(x: 1.12, y: 1.12); c.translateBy(x: -512, y: -520)
            fill(c, polygon([CGPoint(x: 494, y: 590), CGPoint(x: 530, y: 590), CGPoint(x: 512, y: 880)]), p.metal)       // needle
            fill(c, rounded(CGRect(x: 342, y: 520, width: 340, height: 92), 46), p.main)       // base
            fill(c, polygon([CGPoint(x: 432, y: 250), CGPoint(x: 592, y: 250),
                             CGPoint(x: 572, y: 540), CGPoint(x: 452, y: 540)]), p.deep)       // neck
            fill(c, rounded(CGRect(x: 362, y: 150, width: 300, height: 120), 60), p.main)      // cap
        }
    },
    // 3. A masonry mood board: tiles of different heights in three columns.
    Option(number: 3, slug: "mood-board", name: "Mood board", backdrop: .red) { c, p in
        let cols: [[(CGFloat, Bool)]] = [[(240, true), (292, false)], [(330, false), (202, true)], [(180, false), (352, true)]]
        for (i, col) in cols.enumerated() {
            var y: CGFloat = 232
            for (h, strong) in col {
                fill(c, rounded(CGRect(x: 232 + CGFloat(i) * 196, y: y, width: 168, height: h), 46), strong ? p.main : p.second)
                y += h + 28
            }
        }
    },
    // 4. A note card with a folded corner, pinned up.
    Option(number: 4, slug: "folded-note", name: "Folded note", backdrop: .red) { c, p in
        let x0: CGFloat = 262, y0: CGFloat = 222, x1: CGFloat = 762, y1: CGFloat = 802, fold: CGFloat = 170, r: CGFloat = 60
        let card = CGMutablePath()
        card.move(to: CGPoint(x: x0 + r, y: y0))
        card.addLine(to: CGPoint(x: x1 - fold, y: y0))
        card.addLine(to: CGPoint(x: x1, y: y0 + fold))
        card.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x0, y: y1), radius: r)
        card.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y0), radius: r)
        card.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x1, y: y0), radius: r)
        card.closeSubpath()
        fill(c, card, p.card)
        let flap = CGMutablePath()
        flap.move(to: CGPoint(x: x1 - fold, y: y0)); flap.addLine(to: CGPoint(x: x1, y: y0 + fold))
        flap.addArc(tangent1End: CGPoint(x: x1 - fold, y: y0 + fold), tangent2End: CGPoint(x: x1 - fold, y: y0), radius: 30)
        flap.closeSubpath()
        fill(c, flap, p.card2)
        for (i, w) in [CGFloat(360), 360, 240].enumerated() {
            fill(c, rounded(CGRect(x: 332, y: 490 + CGFloat(i) * 92, width: w, height: 44), 22), p.lines)
        }
        fill(c, circle(372, 340, 62), p.onCard)
    },
    // 5. Three cards fanned out, the front one showing a picture.
    Option(number: 5, slug: "card-stack", name: "Card stack", backdrop: .white) { c, p in
        let card = CGRect(x: 312, y: 262, width: 400, height: 500)
        turned(c, -16, about: 512, 760) { fill(c, rounded(card, 64), p.second) }
        turned(c, -5, about: 512, 760) { fill(c, rounded(card, 64), p.middle) }
        turned(c, 7, about: 512, 760) {
            fill(c, rounded(card, 64), p.main)
            c.saveGState(); c.addPath(rounded(card, 64)); c.clip()
            landscape(c, in: CGRect(x: 312, y: 400, width: 400, height: 362), p.cutout)
            c.restoreGState()
        }
    },
    // 7. A letter P drawn as a pin: the bowl is the pin's head, the stem its needle.
    Option(number: 7, slug: "pin-p", name: "Pin \"P\" monogram", backdrop: .red) { c, p in
        let cx: CGFloat = 548, cy: CGFloat = 392, r: CGFloat = 168, w: CGFloat = 100
        c.addPath(circle(cx, cy, r)); c.setStrokeColor(p.main); c.setLineWidth(w); c.strokePath()
        let sx = cx - r
        fill(c, polygon([CGPoint(x: sx - w / 2, y: cy), CGPoint(x: sx + w / 2, y: cy),
                         CGPoint(x: sx + w / 2, y: 700), CGPoint(x: sx, y: 850), CGPoint(x: sx - w / 2, y: 700)]), p.main)
        fill(c, circle(cx, cy, 62), p.second)
    },
    // 8. Four tiles for the four kinds of thing you can keep: pictures, videos, notes, quotes.
    Option(number: 8, slug: "four-kinds", name: "Four kinds", backdrop: .white) { c, p in
        let a: CGFloat = 228, gap: CGFloat = 40, o: CGFloat = 512 - a - gap / 2, r: CGFloat = 58
        let tl = CGRect(x: o, y: o, width: a, height: a), tr = tl.offsetBy(dx: a + gap, dy: 0)
        let bl = tl.offsetBy(dx: 0, dy: a + gap), br = tl.offsetBy(dx: a + gap, dy: a + gap)
        fill(c, rounded(tl, r), p.main)
        c.saveGState(); c.addPath(rounded(tl, r)); c.clip()
        landscape(c, in: tl.insetBy(dx: 0, dy: 34).offsetBy(dx: 0, dy: 34), p.cutout)
        c.restoreGState()
        fill(c, rounded(tr, r), p.second)
        fill(c, polygon([CGPoint(x: tr.midX - 34, y: tr.midY - 56), CGPoint(x: tr.midX + 58, y: tr.midY),
                         CGPoint(x: tr.midX - 34, y: tr.midY + 56)]), p.main)
        fill(c, rounded(bl, r), p.second)
        for (i, w) in [CGFloat(132), 132, 84].enumerated() {
            fill(c, rounded(CGRect(x: bl.minX + 48, y: bl.minY + 56 + CGFloat(i) * 46, width: w, height: 26), 13), p.main)
        }
        fill(c, rounded(br, r), p.main)
        for dx in [CGFloat(-42), 42] {   // a pair of quotation marks
            let x = br.midX + dx, y = br.midY - 8
            fill(c, circle(x, y, 32), p.cutout)
            fill(c, polygon([CGPoint(x: x + 30, y: y + 8), CGPoint(x: x - 2, y: y + 30), CGPoint(x: x - 34, y: y + 74)]), p.cutout)
        }
    },
    // 9. A scrapbook snapshot, held on with two strips of tape.
    Option(number: 9, slug: "taped-snapshot", name: "Taped snapshot", backdrop: .warm) { c, p in
        turned(c, -6, about: 512, 520) {
            let frame = CGRect(x: 292, y: 250, width: 440, height: 520)
            fill(c, rounded(frame, 28), p.card)
            c.addPath(rounded(frame, 28)); c.setStrokeColor(p.edge); c.setLineWidth(8); c.strokePath()
            let photo = CGRect(x: 330, y: 288, width: 364, height: 364)
            fill(c, rounded(photo, 14), p.main)
            c.saveGState(); c.addPath(rounded(photo, 14)); c.clip()
            landscape(c, in: photo.insetBy(dx: 0, dy: 40).offsetBy(dx: 0, dy: 40), p.cutout)
            c.restoreGState()
            for (x, a) in [(CGFloat(300), CGFloat(-38)), (CGFloat(724), CGFloat(38))] {
                turned(c, a, about: x, 262) { fill(c, CGPath(rect: CGRect(x: x - 92, y: 230, width: 184, height: 64), transform: nil), p.middle.copy(alpha: 0.72)!) }
            }
        }
    },

]

// MARK: - Rendering

func bitmap(_ w: Int, _ h: Int, alpha: Bool = false) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue)!
    c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
    return c
}

/// The whole icon: background and picture, opaque.
func render(_ o: Option, _ look: Look) -> CGImage {
    let c = bitmap(Int(S), Int(S))
    let p = palette(o.backdrop, look)
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [p.bgTop, p.bgBottom] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: S), options: [])
    o.draw(c, p)
    return c.makeImage()!
}

/// The picture alone on a see-through background, with its cut-outs as real holes:
/// the foreground layer for an Icon Composer (Liquid Glass) icon.
func renderLayer(_ o: Option, _ look: Look) -> CGImage {
    let c = bitmap(Int(S), Int(S), alpha: true)
    var p = palette(o.backdrop, look)
    p.cutout = holeMarker
    o.draw(c, p)
    return c.makeImage()!
}

func writePNG(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func srgb(_ c: CGColor) -> String {
    let k = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
    let v = k.count == 2 ? [k[0], k[0], k[0], k[1]] : k
    return "srgb:" + v.map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
}

/// Writes an Icon Composer file: the background as a gradient fill (with a dark version)
/// and the picture as one glass layer (with a dark version). iOS makes the clear and
/// tinted looks from these itself.
func writeIconComposer(_ o: Option, _ dir: String) {
    let bundle = "\(dir)/AppIcon.icon"
    try! FileManager.default.createDirectory(atPath: "\(bundle)/Assets", withIntermediateDirectories: true)
    writePNG(renderLayer(o, .light), "\(bundle)/Assets/picture.png")
    writePNG(renderLayer(o, .dark), "\(bundle)/Assets/picture-dark.png")
    let light = palette(o.backdrop, .light), dark = palette(o.backdrop, .dark)
    func gradient(_ p: Palette) -> [String: Any] {
        ["linear-gradient": [srgb(p.bgTop), srgb(p.bgBottom)],
         "orientation": ["start": ["x": 0.5, "y": 0], "stop": ["x": 0.5, "y": 1]]]
    }
    let json: [String: Any] = [
        "fill-specializations": [["value": gradient(light)], ["appearance": "dark", "value": gradient(dark)]],
        "groups": [[
            "layers": [[
                "name": "picture",
                "image-name": "picture.png",
                "image-name-specializations": [["value": "picture.png"], ["appearance": "dark", "value": "picture-dark.png"]],
                "glass": true,
            ]],
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.2],
        ]],
        "supported-platforms": ["squares": "shared"],
    ]
    let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: "\(bundle)/icon.json"))
}

/// iOS's rounded icon shape (a "squircle"), close enough to judge by eye.
func iconMask(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n), y = (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        let pt = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    return p
}

/// Draws an image upright into a flipped context, clipped to the icon shape.
func place(_ c: CGContext, _ img: CGImage, _ r: CGRect, masked: Bool = true, tint: CGColor? = nil) {
    c.saveGState()
    if masked { c.addPath(iconMask(r)); c.clip() }
    c.interpolationQuality = .high
    c.saveGState()
    c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(origin: .zero, size: r.size))
    c.restoreGState()
    if let tint { c.setBlendMode(.multiply); c.setFillColor(tint); c.fill(r) }
    c.restoreGState()
}

func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ weight: NSFont.Weight, _ col: NSColor) {
    (s as NSString).draw(at: NSPoint(x: x, y: y),
                         withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: col])
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "options"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var images: [Int: [Look: CGImage]] = [:]
for o in options {
    let dir = "\(outDir)/\(String(format: "%02d", o.number))-\(o.slug)"
    try? FileManager.default.removeItem(atPath: dir)
    try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var set: [Look: CGImage] = [:]
    for look in Look.allCases {
        let img = render(o, look)
        writePNG(img, "\(dir)/\(look.rawValue).png")
        set[look] = img
    }
    writeIconComposer(o, dir)
    images[o.number] = set
}

// MARK: - The app's icons
//
// The default icon's light look is also AppIcon-1024.png (the App Store's copy). With a second
// argument, the Xcode/App folder, the icons go into the Xcode build as well:
// AppIcon.icon for the default, AppIcon-<Name>.icon for each alternate (the names
// make-project.py lists), and a small light and dark preview of each in Assets.xcassets
// (IconPreview-<Name>) for the picker in Settings › Appearance. AppIconPicker.swift uses the
// same names.

let iconNames: [Int: String] = [3: "MoodBoard", 8: "FourKinds", 1: "PinnedPhoto", 2: "PushPin",
                                4: "FoldedNote", 5: "CardStack", 7: "PinP", 9: "TapedSnapshot"]

func scaled(_ img: CGImage, _ side: Int) -> CGImage {
    let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
    return c.makeImage()!
}

writePNG(images[defaultNumber]![.light]!, "AppIcon-1024.png")

if CommandLine.arguments.count > 2 {
    let app = CommandLine.arguments[2], fm = FileManager.default
    for o in options {
        let name = iconNames[o.number]!
        let icon = "\(app)/" + (o.number == defaultNumber ? "AppIcon" : "AppIcon-\(name)") + ".icon"
        try? fm.removeItem(atPath: icon)
        try! fm.copyItem(atPath: "\(outDir)/\(String(format: "%02d", o.number))-\(o.slug)/AppIcon.icon", toPath: icon)
        let set = "\(app)/Assets.xcassets/IconPreview-\(name).imageset"
        try? fm.removeItem(atPath: set)
        try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
        writePNG(scaled(images[o.number]![.light]!, 180), "\(set)/light.png")
        writePNG(scaled(images[o.number]![.dark]!, 180), "\(set)/dark.png")
        let contents = """
        {
          "images" : [
            { "filename" : "light.png", "idiom" : "universal" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "dark.png", "idiom" : "universal" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
        try! contents.write(toFile: "\(set)/Contents.json", atomically: true, encoding: .utf8)
    }
    print("installed \(options.count) icons and previews into \(app)")
}

// MARK: - Contact sheet: two columns, in the order Settings will list them. Each cell shows
// the light and dark icons large with iOS's rounded shape, then all three looks at
// home-screen size.

let byNumber = Dictionary(uniqueKeysWithValues: options.map { ($0.number, $0) })
let ordered = pickerOrder.map { byNumber[$0]! }
let rows = (ordered.count + 1) / 2
let cellW: CGFloat = 1200, cellH: CGFloat = 520, margin: CGFloat = 60, top: CGFloat = 170
let W = Int(margin * 2 + cellW * 2 + 40), H = Int(top + cellH * CGFloat(rows) + 40 * CGFloat(rows - 1) + margin)
let sheet = bitmap(W, H)
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: true)
sheet.setFillColor(hex(0xECECF1)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
text("PinBoard app icons — the default and seven alternates", margin, 52, 52, .bold, .black)
text("In Settings order. Large: light and dark, as iOS shapes them.  Small: light, dark and tinted (shown with an amber tint) at home-screen size.",
     margin, 118, 24, .regular, NSColor(white: 0.35, alpha: 1))

let red = NSColor(srgbRed: 230 / 255, green: 0, blue: 35 / 255, alpha: 1)
for (i, o) in ordered.enumerated() {
    let col = CGFloat(i % 2), row = CGFloat(i / 2)
    let x = margin + col * (cellW + 40), y = top + row * (cellH + 40)
    sheet.addPath(rounded(CGRect(x: x, y: y, width: cellW, height: cellH), 36)); sheet.setFillColor(grey(1)); sheet.fillPath()
    text("\(o.number)", x + 36, y + 26, 64, .heavy, red)
    text(o.name, x + 120, y + 30, 34, .semibold, .black)
    text(o.number == defaultNumber ? "Default icon" : "Alternate", x + 120, y + 76, 22, .medium,
         o.number == defaultNumber ? red : NSColor(white: 0.45, alpha: 1))
    let big: CGFloat = 340
    // The light icon sits on a pale grey tile so its white edges show; the dark one on a dark tile.
    sheet.addPath(rounded(CGRect(x: x + 20, y: y + 120, width: big + 40, height: big + 40), 28)); sheet.setFillColor(hex(0xE4E4EA)); sheet.fillPath()
    place(sheet, images[o.number]![.light]!, CGRect(x: x + 40, y: y + 140, width: big, height: big))
    sheet.addPath(rounded(CGRect(x: x + 410, y: y + 120, width: big + 40, height: big + 40), 28)); sheet.setFillColor(hex(0x1C1C1E)); sheet.fillPath()
    place(sheet, images[o.number]![.dark]!, CGRect(x: x + 430, y: y + 140, width: big, height: big))

    let px = x + 860, small: CGFloat = 64
    let walls: [(Look, CGColor, CGColor, String, CGColor?)] = [
        (.light, hex(0xDDE8F3), hex(0xF6E6EC), "light", nil),
        (.dark, hex(0x1D2430), hex(0x0E0F14), "dark", nil),
        (.tinted, hex(0x2A2418), hex(0x0F0D09), "tinted", hex(0xF6B544)),
    ]
    for (k, w) in walls.enumerated() {
        let wy = y + 40 + CGFloat(k) * 152
        let wr = CGRect(x: px, y: wy, width: 300, height: 136)
        sheet.saveGState(); sheet.addPath(rounded(wr, 22)); sheet.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [w.1, w.2] as CFArray, locations: [0, 1])!
        sheet.drawLinearGradient(g, start: CGPoint(x: wr.minX, y: wr.minY), end: CGPoint(x: wr.maxX, y: wr.maxY), options: [])
        sheet.restoreGState()
        place(sheet, images[o.number]![w.0]!, CGRect(x: px + 36, y: wy + 22, width: small, height: small), tint: w.4)
        text("PinBoard", px + 30, wy + 92, 14, .medium, w.0 == .light ? .black : .white)
        text(w.3, px + 140, wy + 52, 24, .medium, w.0 == .light ? NSColor(white: 0.3, alpha: 1) : NSColor(white: 0.85, alpha: 1))
    }
}
NSGraphicsContext.current = nil
writePNG(sheet.makeImage()!, "\(outDir)/contact-sheet.png")
print("wrote \(options.count) options × 3 looks, Icon Composer files, and \(outDir)/contact-sheet.png (\(W)×\(H))")
