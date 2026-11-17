import SwiftUI
import InkCore

@main
struct InkApp: App {
    /// 저장소와 문서 세션은 앱 전체에서 하나, 라우터는 창마다 하나다.
    @State private var store = DocumentStore()
    @State private var sessions = EditorSessions()

    var body: some Scene {
        WindowGroup {
            SceneRoot(sessions: sessions)
                .environment(store)
                .task { await store.start() }
        }
    }
}

/// 창 하나의 루트. 창마다 자기 `Router`(경로·탭·편집기 표시)를 갖는다.
struct SceneRoot: View {
    @State private var router: Router

    init(sessions: EditorSessions) {
        _router = State(initialValue: Router(sessions: sessions))
    }

    var body: some View {
        LibraryView()
            .environment(router)
            // 파일 앱 등에서 .inknote를 열면 이 창의 편집기로 바로 진입한다.
            .onOpenURL { url in
                guard url.pathExtension == NotebookPackage.fileExtension else { return }
                router.openEditor(url)
            }
    }
}

#Preview {
    SceneRoot(sessions: EditorSessions())
        .environment(DocumentStore())
}
