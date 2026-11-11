import SwiftUI

@main
struct NoteApp: App {
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .task { await store.start() }
        }
    }
}
