import XCTest
@testable import Captr

final class ClipboardServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    // MARK: - PNG conversion from CGImage-backed NSImage

    func testCopyImage_CGImageBacked_writesPNGAndTIFF() {
        let image = makeTestImage(width: 100, height: 100)

        ClipboardService.copyImage(image)

        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []

        XCTAssertTrue(types.contains(.png), "Pasteboard should contain PNG type")
        XCTAssertTrue(types.contains(.tiff), "Pasteboard should contain TIFF type")

        let pngData = pasteboard.data(forType: .png)
        XCTAssertNotNil(pngData, "PNG data should be non-nil")
        XCTAssertTrue((pngData?.count ?? 0) > 0, "PNG data should be non-empty")

        let tiffData = pasteboard.data(forType: .tiff)
        XCTAssertNotNil(tiffData, "TIFF data should be non-nil")
    }

    // MARK: - Bitmap-backed NSImage

    func testCopyImage_bitmapBacked_writesPNG() {
        let image = NSImage(size: NSSize(width: 50, height: 50))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 50, height: 50))
        image.unlockFocus()

        ClipboardService.copyImage(image)

        let pasteboard = NSPasteboard.general
        let pngData = pasteboard.data(forType: .png)
        XCTAssertNotNil(pngData, "PNG data should be available for bitmap-backed image")
    }

    // MARK: - Round-trip: paste produces valid image

    func testCopyImage_roundTrip_producesValidImage() {
        let original = makeTestImage(width: 200, height: 150)

        ClipboardService.copyImage(original)

        let pasteboard = NSPasteboard.general
        guard let pngData = pasteboard.data(forType: .png) else {
            XCTFail("No PNG data on pasteboard")
            return
        }

        let restored = NSImage(data: pngData)
        XCTAssertNotNil(restored, "Should be able to create NSImage from pasted PNG data")
    }

    // MARK: - Successive writes replace previous

    func testCopyImage_successiveWrites_replacesPrevious() {
        let image1 = makeTestImage(width: 10, height: 10)
        let image2 = makeTestImage(width: 20, height: 20)

        ClipboardService.copyImage(image1)
        let data1 = NSPasteboard.general.data(forType: .png)

        ClipboardService.copyImage(image2)
        let data2 = NSPasteboard.general.data(forType: .png)

        XCTAssertNotEqual(data1, data2, "Second write should replace first")
    }

    // MARK: - Helpers

    private func makeTestImage(width: Int, height: Int) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
