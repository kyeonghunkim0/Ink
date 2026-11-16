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

final class WhiteboardAndRecordingUITests: XCTestCase {
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testWhiteboardDrawing() {
        let app = launch(["--open-sample", "--whiteboard", "--finger"])
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        sleep(2)
        let window = app.windows.firstMatch
        let a = window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
        let b = window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.7))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.05)
        sleep(1)
        attach(app, "whiteboard-after-draw")
        XCTAssertFalse(app.staticTexts["1 / 1"].exists, "화이트보드는 페이지 표시가 없어야 한다")
    }

    func testRecordPlaybackAndExport() {
        let app = launch(["--open-sample", "--finger"])
        XCTAssertTrue(app.navigationBars.staticTexts["샘플"].waitForExistence(timeout: 10))
        sleep(2)

        app.buttons["녹음"].firstMatch.tap()
        // 시뮬레이터는 마이크 입력이 없어 시작 실패 또는 "녹음된 오디오가 없습니다" 안내가 뜰 수 있다.
        let stop = app.buttons["정지"].firstMatch
        var recorded = false
        if stop.waitForExistence(timeout: 5) {
            let window = app.windows.firstMatch
            let a = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            let b = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.05)
            sleep(2)
            attach(app, "recording")
            stop.tap()
            XCTAssertFalse(stop.waitForExistence(timeout: 2))
            recorded = true
        }
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            attach(app, "recording-alert")
            alert.buttons["확인"].tap()
            recorded = false
        }
        if recorded {
            app.buttons["녹음"].firstMatch.press(forDuration: 1)
            let item = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '녹음 1'")).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.tap()
            XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 5))
            sleep(1)
            attach(app, "playback")
            app.buttons["xmark"].firstMatch.tap()
        }

        app.buttons["공유"].firstMatch.tap()
        let pdfAll = app.buttons["PDF로 내보내기 (전체)"].firstMatch
        XCTAssertTrue(pdfAll.waitForExistence(timeout: 5))
        pdfAll.tap()
        // 공유 시트가 뜨는지 확인한 뒤 닫는다.
        let sheet = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        attach(app, "share-sheet")
    }
}
