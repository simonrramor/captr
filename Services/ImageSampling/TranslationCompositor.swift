import AppKit
import CoreGraphics

/// Pure pixels-in/pixels-out stage that produces the image shown in the
/// in-place translation overlay. For each enriched `VisionTextBlock` it masks
/// the original text region with the sampled background color, then draws the
/// translated string (shrunk-to-fit) on top. Blocks with no translation are
/// left untouched — the user sees the original text unchanged.
enum TranslationCompositor {
    /// - Parameters:
    ///   - cgImage: the source screenshot at native pixel resolution
    ///   - blocks: Vision blocks already enriched with `translatedText` and
    ///     `backgroundColor`. Blocks whose translation is nil are skipped.
    ///   - pointSize: the point-space size of the overlay panel (used to
    ///     convert font sizes from pixels to points for `FontFitter`).
    /// - Returns: an `NSImage` sized in points (matching the overlay panel)
    ///   but backed by pixels at the source's native resolution so Retina
    ///   rendering stays crisp.
    static func composite(cgImage: CGImage, blocks: [VisionTextBlock], pointSize: CGSize) -> NSImage {
        let pixelW = cgImage.width
        let pixelH = cgImage.height

        // Explicit NSBitmapImageRep at the source's native pixel dimensions.
        // Going via `NSImage.lockFocus` would give us a context at point
        // density, which on Retina produces a 2x backing store and makes
        // pixel-space coordinates land at half-size.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ), let gc = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(cgImage: cgImage, size: pointSize)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc

        // Base layer: the original screenshot at native pixels.
        NSImage(cgImage: cgImage, size: NSSize(width: pixelW, height: pixelH))
            .draw(in: NSRect(x: 0, y: 0, width: pixelW, height: pixelH))

        // Overlay layer: masks + translated text. Bitmap rep context is
        // bottom-left origin; our pixelRects are top-left origin, so we
        // flip Y once per block when drawing.
        let pixelHF = CGFloat(pixelH)
        let displayScale = pixelHF / max(pointSize.height, 1)

        for block in blocks {
            guard let translated = block.translatedText,
                  !translated.isEmpty,
                  let bgColor = block.backgroundColor else {
                continue
            }

            let blRect = CGRect(
                x: block.pixelRect.minX,
                y: pixelHF - block.pixelRect.maxY,
                width: block.pixelRect.width,
                height: block.pixelRect.height
            )

            bgColor.setFill()
            NSBezierPath(rect: blRect).fill()

            let textColor: NSColor = block.isBackgroundDark ? .white : .black
            let startPointSize = (block.pixelRect.height / displayScale) * 0.8
            let attributed = FontFitter.fit(
                text: translated,
                in: CGSize(width: blRect.width / displayScale, height: blRect.height / displayScale),
                color: textColor,
                startPointSize: startPointSize
            )

            let scaled = attributed.scaledCopy(by: displayScale)
            scaled.draw(in: blRect)
        }

        NSGraphicsContext.restoreGraphicsState()

        // Report the rep as point-sized so AppKit renders 1:1 on Retina —
        // the backing pixels stay at native resolution.
        rep.size = pointSize
        let result = NSImage(size: pointSize)
        result.addRepresentation(rep)
        return result
    }
}

private extension NSAttributedString {
    /// Returns a copy where every `NSFont` attribute is multiplied by `factor`.
    /// Used to turn point-sized attributes into pixel-sized ones for drawing
    /// into a native-resolution bitmap.
    func scaledCopy(by factor: CGFloat) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let scaled = NSFont.systemFont(ofSize: font.pointSize * factor, weight: FontFitter.weight)
            mutable.addAttribute(.font, value: scaled, range: range)
        }
        return mutable
    }
}
