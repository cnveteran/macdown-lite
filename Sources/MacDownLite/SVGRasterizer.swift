import AppKit

/// Rasterises a self-contained SVG (a MathJax formula) into PNG data.
///
/// AppKit can decode SVG through ImageIO, but it honours the document's
/// `width`/`height` attributes — the extractor therefore writes real CSS pixel
/// dimensions onto the clone. We then redraw at `scale` for print sharpness.
enum SVGRasterizer {

    static func png(fromSVG svg: String,
                    cssWidth: Double,
                    cssHeight: Double,
                    scale: CGFloat = 3) -> Data? {
        guard cssWidth > 0, cssHeight > 0, let data = svg.data(using: .utf8) else { return nil }
        guard let image = NSImage(data: data) else { return nil }

        let w = CGFloat(cssWidth) * scale
        let h = CGFloat(cssHeight) * scale
        guard w > 0, h > 0, w < 20000, h < 20000 else { return nil }

        let canvas = NSImage(size: NSSize(width: w, height: h))
        canvas.lockFocus()
        // Flatten onto white: a transparent formula would otherwise print black
        // in Word.
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        canvas.unlockFocus()

        guard let tiff = canvas.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
