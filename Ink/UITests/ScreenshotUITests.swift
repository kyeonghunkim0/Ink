import XCTest

/// fastlane snapshot용 스크린샷. `--screenshot-demo`로 데모 노트를 만든 뒤 화면을 찍는다.
@MainActor
final class ScreenshotUITests: XCTestCase {
    func testTakeScreenshots() {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += ["--screenshot-demo"]
        app.launch()

        let linear = app.staticTexts["선형대수 3강"].firstMatch
        XCTAssertTrue(linear.waitForExistence(timeout: 20))
        sleep(2)
        snapshot("01-Library")

        linear.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["선형대수 3강"].waitForExistence(timeout: 10))
        sleep(3)
        snapshot("02-Editor")

        // 2쪽(그래프)로 이동
        app.staticTexts["2"].firstMatch.tap()
        sleep(2)
        snapshot("03-Graph")

        // 검색: 텍스트 상자·PDF·손글씨 인식 결과에서 찾는다.
        let searchButton = app.buttons.matching(NSPredicate(format: "label == '검색' OR label == 'Search'")).firstMatch
        if searchButton.waitForExistence(timeout: 3) { searchButton.tap() }
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("고유벡터\n")
            sleep(2)
            snapshot("04-Search")
            let cancel = app.buttons.matching(NSPredicate(format: "label == '취소' OR label == 'Cancel'")).firstMatch
            if cancel.exists { cancel.tap() }
        }

        // 라이브러리로 돌아가 화이트보드를 연다 → 탭 두 개
        app.buttons["닫기"].firstMatch.tap()
        let board = app.staticTexts["아이디어 보드"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        board.tap()
        XCTAssertTrue(app.navigationBars.staticTexts["아이디어 보드"].waitForExistence(timeout: 10))
        sleep(3)
        snapshot("05-Whiteboard")
    }
}
