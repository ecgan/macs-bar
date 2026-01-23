import XCTest
@testable import MacWindowTracker

final class MacWindowTrackerTests: XCTestCase {
    func testTrackedWindowEquality() {
        let window1 = TrackedWindow(
            id: 123,
            title: "Test Window",
            appName: "TestApp",
            appBundleId: "com.test.app",
            appPid: 1234,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            monitorId: 1,
            isFocused: true
        )

        let window2 = TrackedWindow(
            id: 123,
            title: "Different Title",
            appName: "TestApp",
            appBundleId: "com.test.app",
            appPid: 1234,
            frame: CGRect(x: 100, y: 100, width: 800, height: 600),
            monitorId: 2,
            isFocused: false
        )

        // Windows with same ID should be equal
        XCTAssertEqual(window1, window2)
        XCTAssertEqual(window1.hashValue, window2.hashValue)
    }

    func testTrackedMonitorEquality() {
        let monitor1 = TrackedMonitor(
            id: 1,
            name: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055),
            isMain: true
        )

        let monitor2 = TrackedMonitor(
            id: 1,
            name: "Different Name",
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 25, width: 2560, height: 1415),
            isMain: false
        )

        // Monitors with same ID should be equal
        XCTAssertEqual(monitor1, monitor2)
        XCTAssertEqual(monitor1.hashValue, monitor2.hashValue)
    }

    func testRunLoopJobCancellation() {
        let job = RunLoopJob()
        XCTAssertFalse(job.isCancelled)

        job.cancel()
        XCTAssertTrue(job.isCancelled)

        // Should throw CancellationError
        XCTAssertThrowsError(try job.checkCancellation()) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCGWindowListOnScreenWindows() {
        // This test will actually query the system
        // Just verify it doesn't crash and returns an array
        let windows = CGWindowList.onScreenWindows()
        XCTAssertNotNil(windows)
        // Can't assert specific count as it depends on what's running
    }
}
