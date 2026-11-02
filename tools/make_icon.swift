import AppKit

// Draws a simple rounded-square app icon: gradient + "M↓" mark.
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func makePNG(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.055
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)
    path.addClip()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.44, blue: 0.94, alpha: 1),
        NSColor(srgbRed: 0.58, green: 0.24, blue: 0.86, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -60)

    let text = "M↓" as NSString
    let font = NSFont.systemFont(ofSize: s * 0.44, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let bounds = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (s - bounds.width) / 2,
                          y: (s - bounds.height) / 2 + s * 0.015),
              withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// iconutil iconset naming
let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    let data = makePNG(size: spec.px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(spec.name).png"))
}
print("iconset written to \(outDir)")
