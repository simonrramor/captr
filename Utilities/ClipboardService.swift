import AppKit
import UniformTypeIdentifiers

enum ClipboardService {

    /// Writes an image to the system clipboard in a format compatible with
    /// native macOS apps, Electron apps (WhatsApp, Slack, etc.), and browsers.
    ///
    /// Writes the NSImage directly (which provides `public.tiff` with full UTI
    /// conformance), then writes PNG data to a temporary file and puts the file
    /// URL on the pasteboard so Electron apps can read it as `image/png`.
    static func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            pasteboard.writeObjects([image])
            return
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        item.setData(tiffData, forType: .tiff)
        pasteboard.writeObjects([item])
    }
}
