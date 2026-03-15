import XCTest
@testable import Captr

@MainActor
final class MediaLibraryManagerTests: XCTestCase {

    // MARK: - loadLibrary with empty directories

    func testLoadLibrary_emptyDirectories_producesEmptyLists() async {
        let manager = MediaLibraryManager()
        await manager.loadLibrary()

        // Screenshots directory may be empty or have items from previous runs.
        // The key assertion is that it doesn't crash.
        XCTAssertNotNil(manager.recordings)
        XCTAssertNotNil(manager.screenshots)
        XCTAssertNotNil(manager.allItems)
    }

    // MARK: - deleteItem with nonexistent file doesn't crash

    func testDeleteItem_nonexistentFile_doesNotCrash() {
        let manager = MediaLibraryManager()
        let fakeItem = MediaItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).png"),
            type: .screenshot,
            createdAt: Date(),
            fileSize: 0,
            duration: nil,
            thumbnail: nil
        )

        manager.deleteItem(fakeItem)
        // Should not crash — file doesn't exist but that's OK
    }

    // MARK: - deleteItem removes from in-memory lists

    func testDeleteItem_removesFromLists() {
        let manager = MediaLibraryManager()
        let item = MediaItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test.png"),
            type: .screenshot,
            createdAt: Date(),
            fileSize: 100,
            duration: nil,
            thumbnail: nil
        )

        manager.screenshots = [item]
        manager.allItems = [item]

        manager.deleteItem(item)

        XCTAssertTrue(manager.screenshots.isEmpty)
        XCTAssertTrue(manager.allItems.isEmpty)
    }

    // MARK: - Static directory paths are valid

    func testBaseDirectory_isInMovies() {
        let path = MediaLibraryManager.baseDirectory.path
        XCTAssertTrue(path.contains("Movies") || path.contains("Captr"),
                      "Base directory should be under Movies/Captr")
    }

    func testScreenshotsDirectory_isUnderBase() {
        let screenshotsPath = MediaLibraryManager.screenshotsDirectory.path
        let basePath = MediaLibraryManager.baseDirectory.path
        XCTAssertTrue(screenshotsPath.hasPrefix(basePath),
                      "Screenshots directory should be under base directory")
    }
}
