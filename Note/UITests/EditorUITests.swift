import XCTest

/// 시뮬레이터에서 실제 터치로 필기·페이지 추가·닫기를 검증한다.
final class EditorUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--open-sample", "--finger"]
        app.launch()
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDrawAddPageAndClose() {
        let title = app.navigationBars.staticTexts["샘플"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        sleep(2)

        // 캔버스 가운데에서 드래그해 스트로크를 그린다.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let mid = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: mid, withVelocity: .slow, thenHoldForDuration: 0.05)
        mid.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        sleep(1)
        attach("01-after-draw")

        // 페이지 추가는 현재 페이지 뒤에 삽입되고 그 페이지로 이동한다.
        app.buttons["페이지 추가"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["2 / 4"].waitForExistence(timeout: 5))
        attach("02-after-add-page")

        // 저장 debounce(2초) 이후 닫기.
        sleep(3)
        app.buttons["닫기"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["모든 노트"].waitForExistence(timeout: 5))
        sleep(1)
        attach("03-library")
    }
}
