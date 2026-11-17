import Testing
import Foundation
@testable import Ink

@MainActor
struct EditorSessionsTests {
    let a = URL(fileURLWithPath: "/tmp/Ink/수학.inknote")
    let b = URL(fileURLWithPath: "/tmp/Ink/폴더/영어.inknote")

    @Test func windowsKeepSeparateTabs() {
        let sessions = EditorSessions()
        let left = Router(sessions: sessions), right = Router(sessions: sessions)
        left.openEditor(a)
        right.openEditor(b)
        #expect(left.openNotebooks == [a])
        #expect(right.openNotebooks == [b])
        #expect(left.isEditorPresented && right.isEditorPresented)
    }

    @Test func openingInAnotherWindowMovesTabAndKeepsModel() {
        let sessions = EditorSessions()
        let left = Router(sessions: sessions), right = Router(sessions: sessions)
        left.openEditor(a)
        let model = left.editorModel(for: a)

        right.openEditor(a)

        #expect(left.openNotebooks.isEmpty)
        #expect(!left.isEditorPresented)
        #expect(right.openNotebooks == [a])
        #expect(right.editorModel(for: a) === model)
        #expect(sessions.openURLs == [a])
    }

    @Test func trailingSlashURLIsSameNotebook() {
        let sessions = EditorSessions()
        let router = Router(sessions: sessions)
        router.openEditor(a)
        router.openEditor(URL(fileURLWithPath: a.path + "/", isDirectory: true))
        #expect(router.openNotebooks == [a])
    }

    @Test func closeEverywhereClosesTabsInAllWindows() async {
        let sessions = EditorSessions()
        let left = Router(sessions: sessions), right = Router(sessions: sessions)
        left.openEditor(a)
        _ = left.editorModel(for: a)
        right.openEditor(b)
        _ = right.editorModel(for: b)

        await right.closeTabsAndWait(under: URL(fileURLWithPath: "/tmp/Ink/폴더"))
        #expect(right.openNotebooks.isEmpty)
        #expect(left.openNotebooks == [a])

        await right.closeTabAndWait(a)
        #expect(left.openNotebooks.isEmpty)
        #expect(sessions.openURLs.isEmpty)
    }

    @Test func closingWindowReleasesItsDocuments() async {
        let sessions = EditorSessions()
        let kept = Router(sessions: sessions)
        kept.openEditor(a)
        _ = kept.editorModel(for: a)
        do {
            let closed = Router(sessions: sessions)
            closed.openEditor(b)
            _ = closed.editorModel(for: b)
        }
        // 라우터 deinit이 메인 액터로 넘긴 정리 작업을 기다린다.
        for _ in 0..<10 { await Task.yield() }
        #expect(sessions.openURLs == [a])
    }
}
