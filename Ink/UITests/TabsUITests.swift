import XCTest

final class TabsUITests: XCTestCase {
    func testOpenSecondNotebookInTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        let tabs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '탭 닫기'"))
        XCTAssertEqual(tabs.count, 0, "탭이 하나면 스트립이 없다")

        // 라이브러리로 돌아가 새 노트를 만들면 두 번째 탭으로 열린다.
        app.buttons["닫기"].firstMatch.tap()
        XCTAssertTrue(app.buttons["새 노트"].waitForExistence(timeout: 5))
        app.buttons["새 노트"].tap()
        let create = app.buttons["만들기"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["새 노트"].waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(tabs.count, 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "tabs"; shot.lifetime = .keepAlways; add(shot)

        // 첫 탭으로 전환한 뒤 닫으면 스트립이 사라진다.
        app.buttons["샘플"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 5))
        app.buttons["탭 닫기 샘플"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["새 노트"].waitForExistence(timeout: 5))
        XCTAssertEqual(tabs.count, 0)
    }
}
