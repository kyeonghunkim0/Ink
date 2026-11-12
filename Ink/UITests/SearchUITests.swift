import XCTest

final class SearchUITests: XCTestCase {
    /// iOS 26의 접힌 검색 버튼을 눌러 검색 필드를 연다.
    private func openSearchField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 2) {
            let button = app.buttons.matching(NSPredicate(format: "label == '검색' OR label == 'Search'")).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
        }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    func testEditorSearchFindsTextBoxPage() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample", "--objects"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        let field = openSearchField(app)
        field.tap()
        field.typeText("텍스트")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1쪽'")).firstMatch.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "editor-search"; shot.lifetime = .keepAlways; add(shot)
    }

    func testLibrarySearchByTitle() {
        let app = XCUIApplication()
        app.launchArguments = ["--open-sample"]
        app.launch()
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        app.buttons["닫기"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["모든 노트"].waitForExistence(timeout: 5))
        let field = openSearchField(app)
        field.tap()
        field.typeText("없는이름")
        XCTAssertTrue(app.staticTexts["노트가 없습니다"].waitForExistence(timeout: 5))
        // 검색을 닫으면 목록이 돌아온다.
        let cancel = app.buttons.matching(NSPredicate(format: "label == '취소' OR label == 'Cancel'")).firstMatch
        if cancel.waitForExistence(timeout: 2) { cancel.tap() } else { field.buttons.firstMatch.tap() }
        XCTAssertTrue(app.staticTexts["샘플"].firstMatch.waitForExistence(timeout: 5))
    }
}
