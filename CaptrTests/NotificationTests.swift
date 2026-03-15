import XCTest
@testable import Captr

@MainActor
final class NotificationTests: XCTestCase {

    // MARK: - Notification state updates correctly

    func testShowSavedNotification_setsState() {
        let appState = AppState()
        appState.showSavedNotification("Test message")

        XCTAssertTrue(appState.showNotification)
        XCTAssertEqual(appState.notificationMessage, "Test message")
        XCTAssertFalse(appState.notificationIsError)
    }

    // MARK: - Successive notifications update message

    func testSuccessiveNotifications_showsLatestMessage() {
        let appState = AppState()

        appState.showSavedNotification("First")
        appState.showSavedNotification("Second")

        XCTAssertEqual(appState.notificationMessage, "Second",
                       "Latest notification should be shown")
        XCTAssertTrue(appState.showNotification)
    }

    // MARK: - Auto-dismiss after delay

    func testNotification_autoDismisses() async throws {
        let appState = AppState()
        appState.showSavedNotification("Dismissing soon")

        XCTAssertTrue(appState.showNotification)

        // Wait slightly longer than the 3-second dismiss duration
        try await Task.sleep(nanoseconds: 3_500_000_000)

        XCTAssertFalse(appState.showNotification,
                       "Notification should auto-dismiss after timeout")
    }

    // MARK: - New notification resets dismiss timer

    func testNewNotification_resetsDismissTimer() async throws {
        let appState = AppState()

        appState.showSavedNotification("First")

        // Wait 2 seconds (less than the 3-second dismiss)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Show a second notification — this should reset the timer
        appState.showSavedNotification("Second")

        // Wait 2 more seconds (4s total from first, but only 2s from second)
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // The first timer would have fired at 3s, but since we reset it,
        // the notification should still be visible (only 2s into the new timer)
        XCTAssertTrue(appState.showNotification,
                      "Notification should still be visible because the timer was reset")
        XCTAssertEqual(appState.notificationMessage, "Second")
    }
}
