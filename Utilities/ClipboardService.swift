import AppKit
import UniformTypeIdentifiers

enum ClipboardService {

    /// Writes a single PNG representation to the system clipboard. Advertising
    /// TIFF alongside PNG makes some browser and Electron uploaders select the
    /// TIFF payload and reject it as an unsupported file type.
    static func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        pasteboard.writeObjects([item])
    }
}
