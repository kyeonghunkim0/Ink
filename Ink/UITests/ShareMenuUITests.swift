import XCTest

final class ShareMenuUITests: XCTestCase {
    func testShareMenuHasAirDropItems() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        app.buttons["공유"].firstMatch.tap()
        XCTAssertTrue(app.buttons["PDF를 AirDrop으로 보내기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["노트 파일을 AirDrop으로 보내기"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "share-menu"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["노트 파일을 AirDrop으로 보내기"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForExistence(timeout: 10))
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "airdrop-sheet"; shot2.lifetime = .keepAlways; add(shot2)
    }
}
