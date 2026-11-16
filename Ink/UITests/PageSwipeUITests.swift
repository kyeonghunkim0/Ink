import XCTest

/// 손가락 스와이프로 페이지 캐러셀이 넘어가는지 검증한다.
final class PageSwipeUITests: XCTestCase {
    func testSwipeTurnsPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        sleep(2)
        let window = app.windows.firstMatch
        let counter = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ / [0-9]+")).firstMatch
        func expect(_ label: String) {
            let ok = app.staticTexts[label].waitForExistence(timeout: 3)
            if !ok {
                let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
                print("SWIPE-FAIL expected \(label) got \(counter.exists ? counter.label : "none")")
            }
            XCTAssertTrue(ok, "expected \(label)")
        }
        window.swipeLeft(); expect("2 / 3")
        window.swipeLeft(); expect("3 / 3")
        window.swipeRight(); expect("2 / 3")
    }
}
