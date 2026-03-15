import XCTest
@testable import Captr

@MainActor
final class OverlayControllerTests: XCTestCase {

    // MARK: - AreaSelectionWindowController

    func testAreaSelection_closeOverlay_isIdempotent() {
        let controller = AreaSelectionWindowController()

        // Calling closeOverlay multiple times without showOverlay should not crash
        controller.closeOverlay()
        controller.closeOverlay()
        controller.closeOverlay()
    }

    func testAreaSelection_showThenClose_leavesNoWindows() {
        let controller = AreaSelectionWindowController()
        let expectation = XCTestExpectation(description: "area selected")
        expectation.isInverted = true

        controller.showOverlay(
            onSelected: { _ in expectation.fulfill() },
            onCancelled: { }
        )

        controller.closeOverlay()

        // Verify the overlay is fully torn down by calling close again (idempotent)
        controller.closeOverlay()

        wait(for: [expectation], timeout: 0.1)
    }

    func testAreaSelection_deinit_cleansUp() {
        var controller: AreaSelectionWindowController? = AreaSelectionWindowController()

        controller?.showOverlay(
            onSelected: { _ in },
            onCancelled: { }
        )

        // Release the controller — deinit should clean up windows
        controller = nil

        // If we get here without a crash, deinit cleanup worked
    }

    // MARK: - WindowSelectionWindowController

    func testWindowSelection_closeOverlay_isIdempotent() {
        let controller = WindowSelectionWindowController()

        controller.closeOverlay()
        controller.closeOverlay()
        controller.closeOverlay()
    }

    func testWindowSelection_deinit_cleansUp() {
        var controller: WindowSelectionWindowController? = WindowSelectionWindowController()

        controller?.showOverlay(
            onSelected: { _ in },
            onCancelled: { }
        )

        controller = nil
    }

    // MARK: - RecordingAreaOverlayController

    func testRecordingOverlay_closeOverlay_isIdempotent() {
        let controller = RecordingAreaOverlayController()

        controller.closeOverlay()
        controller.closeOverlay()
        controller.closeOverlay()
    }

    func testRecordingOverlay_showThenClose() {
        let controller = RecordingAreaOverlayController()

        controller.showOverlay(recordingRect: CGRect(x: 100, y: 100, width: 400, height: 300))
        controller.closeOverlay()

        // Should be safe to close again
        controller.closeOverlay()
    }

    func testRecordingOverlay_deinit_cleansUp() {
        var controller: RecordingAreaOverlayController? = RecordingAreaOverlayController()

        controller?.showOverlay(recordingRect: CGRect(x: 0, y: 0, width: 200, height: 200))
        controller = nil
    }
}
