import AppKit
import CoreImage
import CoreGraphics

/// Estimates the background color surrounding a text bounding box on a
/// CGImage so the compositor can mask the original text with something close
/// to its backdrop. Samples four thin strips just outside the rect (top,
/// bottom, left, right) and averages them — the rect interior is dominated
/// by ink, so sampling inside would just give us the text color.
enum BackgroundColorSampler {
    /// Width of each strip sampled around the rect, in pixels. 4px is thick
    /// enough to smooth out minor edge noise but thin enough to stay on the
    /// actual background and not spill into neighbouring text.
    private static let stripThickness: CGFloat = 4

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func sample(cgImage: CGImage, pixelRect: CGRect) -> (color: NSColor, isDark: Bool) {
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let ciImage = CIImage(cgImage: cgImage)

        // Vision rects are in top-left-origin pixel space; CIImage uses
        // bottom-left. Flip Y once here.
        let flippedRect = CGRect(
            x: pixelRect.minX,
            y: CGFloat(cgImage.height) - pixelRect.maxY,
            width: pixelRect.width,
            height: pixelRect.height
        )

        let t = stripThickness
        let strips: [CGRect] = [
            // above
            CGRect(x: flippedRect.minX, y: flippedRect.maxY, width: flippedRect.width, height: t),
            // below
            CGRect(x: flippedRect.minX, y: flippedRect.minY - t, width: flippedRect.width, height: t),
            // left
            CGRect(x: flippedRect.minX - t, y: flippedRect.minY, width: t, height: flippedRect.height),
            // right
            CGRect(x: flippedRect.maxX, y: flippedRect.minY, width: t, height: flippedRect.height)
        ]
            .map { $0.intersection(imageRect) }
            .filter { !$0.isEmpty }

        guard !strips.isEmpty else {
            return fallback(for: ciImage, imageRect: imageRect)
        }

        var rSum: CGFloat = 0
        var gSum: CGFloat = 0
        var bSum: CGFloat = 0
        var aSum: CGFloat = 0
        var counted = 0

        for strip in strips {
            if let color = averageColor(of: ciImage, in: strip) {
                rSum += color.red
                gSum += color.green
                bSum += color.blue
                aSum += color.alpha
                counted += 1
            }
        }

        guard counted > 0 else {
            return fallback(for: ciImage, imageRect: imageRect)
        }

        let n = CGFloat(counted)
        let color = NSColor(srgbRed: rSum / n, green: gSum / n, blue: bSum / n, alpha: aSum / n)
        return (color, isDark: luminance(r: rSum / n, g: gSum / n, b: bSum / n) < 0.5)
    }

    private static func fallback(for ciImage: CIImage, imageRect: CGRect) -> (NSColor, Bool) {
        if let c = averageColor(of: ciImage, in: imageRect) {
            let color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
            return (color, luminance(r: c.red, g: c.green, b: c.blue) < 0.5)
        }
        return (NSColor.white, false)
    }

    private static func averageColor(of image: CIImage, in rect: CGRect) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        let extent = CIVector(cgRect: rect)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: extent
        ]), let output = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return (
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }

    private static func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        0.299 * r + 0.587 * g + 0.114 * b
    }
}
