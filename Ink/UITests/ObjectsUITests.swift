import XCTest

final class ObjectsUITests: XCTestCase {
    func testInsertTextBoxAndSticker() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        sleep(1)

        app.buttons["삽입"].firstMatch.tap()
        let textBox = app.buttons["텍스트 상자"].firstMatch
        XCTAssertTrue(textBox.waitForExistence(timeout: 5))
        textBox.tap()
        // 삽입 후 객체 모드가 켜진다.
        let objectMode = app.buttons["객체 선택"].firstMatch
        XCTAssertTrue(objectMode.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))

        app.buttons["삽입"].firstMatch.tap()
        let sticker = app.buttons["스티커"].firstMatch
        XCTAssertTrue(sticker.waitForExistence(timeout: 5))
        sticker.tap()
        let star = app.buttons["⭐️"].firstMatch
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "objects-inserted"; shot.lifetime = .keepAlways; add(shot)

        // 객체 모드를 끄면 필기 캔버스가 다시 활성화된다.
        objectMode.tap()
        sleep(1)
    }
}
