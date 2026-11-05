// compose.swift — frames raw simulator screenshots for the App Store: a headline and a
// subheadline above the screenshot, on a soft background, at Apple's exact pixel sizes.
//
// Usage: swift compose.swift <shots.json> <raw folder> <output folder>
// shots.json: {"canvas":[w,h], "shotWidth":w, "shotTop":y, "corner":r,
//              "shots":[{"file":"1-pins.png","title":"…","subtitle":"…"}]}

import AppKit

struct Shot: Decodable { let file: String; let title: String; let subtitle: String }
struct Spec: Decodable {
    let canvas: [Int]
    let shotWidth: Double
    let shotTop: Double
    let corner: Double
    let titleSize: Double
    let subtitleSize: Double
    let shots: [Shot]
}

let args = CommandLine.arguments
let spec = try! JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
let rawFolder = args[2], outFolder = args[3]
try? FileManager.default.createDirectory(atPath: outFolder, withIntermediateDirectories: true)

let width = spec.canvas[0], height = spec.canvas[1]
let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let soft = NSColor(srgbRed: 0.40, green: 0.38, blue: 0.40, alpha: 1)
let accent = NSColor(srgbRed: 0.90, green: 0.0, blue: 0.14, alpha: 1)   // the app's red
let top = NSColor(srgbRed: 1.00, green: 0.96, blue: 0.95, alpha: 1)
let bottom = NSColor(srgbRed: 0.99, green: 0.89, blue: 0.88, alpha: 1)

func paragraph() -> NSMutableParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineHeightMultiple = 0.95
    return style
}

for (index, shot) in spec.shots.enumerated() {
    // Opaque RGB (no alpha channel): App Store Connect turns down screenshots with transparency.
    let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip so y grows downwards, like a page, and tell AppKit so text is drawn the right way up.
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(starting: top, ending: bottom)!.draw(in: canvas, angle: 90)

    // Headline and subheadline.
    let margin = Double(width) * 0.07
    let textWidth = Double(width) - margin * 2
    let title = NSAttributedString(string: shot.title, attributes: [
        .font: NSFont.systemFont(ofSize: spec.titleSize, weight: .bold),
        .foregroundColor: ink, .paragraphStyle: paragraph(), .kern: -spec.titleSize * 0.01])
    let titleBox = title.boundingRect(with: NSSize(width: textWidth, height: 2000),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
    let titleTop = spec.shotTop * 0.16
    title.draw(with: NSRect(x: margin, y: titleTop, width: textWidth, height: titleBox.height),
               options: [.usesLineFragmentOrigin, .usesFontLeading])
    let subtitle = NSAttributedString(string: shot.subtitle, attributes: [
        .font: NSFont.systemFont(ofSize: spec.subtitleSize, weight: .medium),
        .foregroundColor: soft, .paragraphStyle: paragraph()])
    let subtitleTop = titleTop + titleBox.height + spec.subtitleSize * 0.55
    subtitle.draw(with: NSRect(x: margin, y: subtitleTop, width: textWidth, height: spec.subtitleSize * 3),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])

    // A small red rule between the words and the screenshot.
    accent.setFill()
    let ruleWidth = Double(width) * 0.06
    NSBezierPath(roundedRect: NSRect(x: (Double(width) - ruleWidth) / 2, y: spec.shotTop - spec.subtitleSize * 0.9,
                                     width: ruleWidth, height: spec.subtitleSize * 0.14),
                 xRadius: 4, yRadius: 4).fill()

    // The screenshot, rounded like the device, with a soft shadow. It may run off the bottom.
    let image = NSImage(contentsOfFile: "\(rawFolder)/\(shot.file)")!
    let pixel = image.representations.first!
    let scale = spec.shotWidth / Double(pixel.pixelsWide)
    let shotRect = NSRect(x: (Double(width) - spec.shotWidth) / 2, y: spec.shotTop,
                          width: spec.shotWidth, height: Double(pixel.pixelsHigh) * scale)
    let rounded = NSBezierPath(roundedRect: shotRect, xRadius: spec.corner, yRadius: spec.corner)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
    shadow.shadowBlurRadius = Double(width) * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -Double(width) * 0.008)
    shadow.set()
    NSColor.white.setFill()
    rounded.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    rounded.addClip()
    // Drawing an image in a flipped context needs respectFlipped, or it comes out upside down.
    image.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 0, alpha: 0.08).setStroke()
    rounded.lineWidth = 2
    rounded.stroke()

    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
    let name = String(format: "%02d-", index + 1) + shot.file
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outFolder)/\(name)"))
    print("wrote \(name) \(rep.pixelsWide)x\(rep.pixelsHigh)")
}
