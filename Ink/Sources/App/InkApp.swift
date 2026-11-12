import SwiftUI

@main
struct InkApp: App {
    @State private var store = DocumentStore()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .environment(router)
                .task { await store.start() }
                // 파일 앱 등에서 .inknote를 열면 바로 편집기로 진입한다.
                .onOpenURL { url in
                    guard url.pathExtension == NotebookPackage.fileExtension else { return }
                    router.openEditor(url)
                }
        }
    }
}
